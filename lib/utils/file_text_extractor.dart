import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

const supportedUploadExtensions = <String>[
  'txt',
  'md',
  'csv',
  'xlsx',
  'xls',
  'docx',
  'doc',
  'pdf',
];

bool isSupportedUploadExtension(String filename) {
  final extension = _fileExtension(filename);
  return extension != null && supportedUploadExtensions.contains(extension);
}

String extractTextFromFileBytes({required String filename, required Uint8List bytes}) {
  final extension = _fileExtension(filename);
  if (extension == null) {
    throw const FormatException('Missing file extension.');
  }
  switch (extension) {
    case 'txt':
    case 'md':
      return _decodeUtf8(bytes);
    case 'csv':
      return _extractCsv(bytes);
    case 'xlsx':
    case 'xls':
      return _extractExcel(bytes);
    case 'docx':
      return _extractDocx(bytes);
    case 'doc':
      return _extractDoc(bytes);
    case 'pdf':
      return _extractPdf(bytes);
    default:
      throw const FormatException('Unsupported file type.');
  }
}

String extractTextFromFileBytesIsolate(Map<String, Object?> args) {
  final filename = args['filename'] as String;
  final bytes = args['bytes'] as Uint8List;
  return extractTextFromFileBytes(filename: filename, bytes: bytes);
}

String? _fileExtension(String filename) {
  final index = filename.lastIndexOf('.');
  if (index == -1 || index == filename.length - 1) {
    return null;
  }
  return filename.substring(index + 1).toLowerCase();
}

String _decodeUtf8(Uint8List bytes) {
  return utf8.decode(bytes, allowMalformed: true);
}

String _extractCsv(Uint8List bytes) {
  final content = _decodeUtf8(bytes);
  final rows = const CsvToListConverter(eol: '\n').convert(content);
  final buffer = StringBuffer();
  for (final row in rows) {
    final cells = row.map((cell) => cell?.toString() ?? '').toList();
    buffer.writeln(cells.join('\t'));
  }
  return buffer.toString();
}

String _extractExcel(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  final buffer = StringBuffer();
  for (final sheetName in excel.tables.keys) {
    final sheet = excel.tables[sheetName];
    if (sheet == null) {
      continue;
    }
    buffer.writeln('[Sheet] $sheetName');
    for (final row in sheet.rows) {
      final cells = row.map((cell) => cell?.value?.toString() ?? '').toList();
      buffer.writeln(cells.join('\t'));
    }
    buffer.writeln();
  }
  return buffer.toString();
}

String _extractDocx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.files.firstWhere(
    (file) => file.name == 'word/document.xml',
    orElse: () => ArchiveFile('missing', 0, <int>[]),
  );
  if (docFile.name != 'word/document.xml') {
    throw const FormatException('Missing document.xml in docx.');
  }
  final xmlContent = utf8.decode(docFile.content as List<int>, allowMalformed: true);
  final document = XmlDocument.parse(xmlContent);
  final buffer = StringBuffer();
  for (final paragraph in document.descendants.whereType<XmlElement>()) {
    if (paragraph.name.local != 'p') {
      continue;
    }
    final text = paragraph.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 't')
        .map((node) => node.innerText)
        .join();
    if (text.trim().isNotEmpty) {
      buffer.writeln(text);
    }
  }
  return buffer.toString();
}

String _extractDoc(Uint8List bytes) {
  final decoded = latin1.decode(bytes, allowInvalid: true);
  final cleaned = decoded.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ');
  final normalized = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return normalized;
}

String _extractPdf(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  final text = PdfTextExtractor(document).extractText();
  document.dispose();
  return text;
}

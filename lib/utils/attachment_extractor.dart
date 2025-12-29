const attachmentImageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
};

const attachmentTextExtensions = <String>{
  'txt',
  'md',
  'csv',
  'json',
  'log',
  'yaml',
  'yml',
  'xml',
};

const attachmentSupportedExtensions = <String>{
  ...attachmentImageExtensions,
  ...attachmentTextExtensions,
  'pdf',
};

bool isSupportedAttachment(String filename) {
  final extension = _fileExtension(filename);
  return extension != null && attachmentSupportedExtensions.contains(extension);
}

bool isImageAttachment(String filename) {
  final extension = _fileExtension(filename);
  return extension != null && attachmentImageExtensions.contains(extension);
}

bool isTextAttachment(String filename) {
  final extension = _fileExtension(filename);
  return extension != null && attachmentTextExtensions.contains(extension);
}

bool isPdfAttachment(String filename) {
  final extension = _fileExtension(filename);
  return extension == 'pdf';
}

String? guessAttachmentMime(String filename) {
  final extension = _fileExtension(filename);
  switch (extension) {
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'md':
      return 'text/markdown';
    case 'csv':
      return 'text/csv';
    case 'json':
      return 'application/json';
    case 'yaml':
    case 'yml':
      return 'text/yaml';
    case 'xml':
      return 'application/xml';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    default:
      return null;
  }
}

String? _fileExtension(String filename) {
  final index = filename.lastIndexOf('.');
  if (index == -1 || index == filename.length - 1) {
    return null;
  }
  return filename.substring(index + 1).toLowerCase();
}

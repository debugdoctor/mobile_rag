const List<String> defaultChunkSeparators = ['\n'];

int getDefaultChunkMinSize(int chunkMaxSize) {
  final safeMax = chunkMaxSize > 0 ? chunkMaxSize.round() : 1;
  return (safeMax * 0.4).round().clamp(40, safeMax);
}

List<String>? parseChunkSeparators(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final separators = <String>[];
  final seen = <String>{};
  for (var index = 0; index < value.length; index += 1) {
    final char = value[index];
    if (char == '\\' && index + 1 < value.length && value[index + 1] == 'n') {
      if (seen.add('\n')) {
        separators.add('\n');
      }
      index += 1;
      continue;
    }
    if (char == '\n') {
      if (seen.add('\n')) {
        separators.add('\n');
      }
      continue;
    }
    if (RegExp(r'\s').hasMatch(char)) {
      continue;
    }
    if (seen.add(char)) {
      separators.add(char);
    }
  }
  return separators.isNotEmpty ? separators : null;
}

List<String> splitIntoChunks(
  String content,
  int chunkMaxSize,
  int chunkOverlap, {
  List<String>? separators,
  int? chunkMinSize,
}) {
  final normalized = content.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) {
    return [];
  }
  final safeMaxSize = chunkMaxSize > 0 ? chunkMaxSize.round() : 1;
  final resolvedMinSize = chunkMinSize != null
      ? chunkMinSize.round()
      : getDefaultChunkMinSize(safeMaxSize);
  final safeMinSize = resolvedMinSize.clamp(1, safeMaxSize);
  final safeOverlap = chunkOverlap.round().clamp(0, safeMaxSize - 1);
  final resolvedSeparators = _normalizeSeparators(separators);
  final chunks = <String>[];
  var start = 0;

  while (start < normalized.length) {
    final remaining = normalized.length - start;
    final maxEnd = (start + safeMaxSize).clamp(0, normalized.length);
    final punctEnd = _findNextSeparator(normalized, start, maxEnd, resolvedSeparators);
    final punctuationSize = punctEnd != null ? punctEnd - start : remaining;
    final targetSize = punctuationSize.clamp(safeMinSize, safeMaxSize);
    final end = (start + targetSize).clamp(0, normalized.length);
    final piece = normalized.substring(start, end).trim();
    if (piece.isNotEmpty) {
      chunks.add(piece);
    }
    if (end >= normalized.length) {
      break;
    }
    final nextStart = end - safeOverlap;
    start = nextStart > start ? nextStart : end;
    if (start < 0) {
      start = 0;
    }
  }

  return chunks;
}

List<String> _normalizeSeparators(List<String>? separators) {
  final source = (separators != null && separators.isNotEmpty)
      ? separators
      : defaultChunkSeparators;
  final seen = <String>{};
  for (final item in source) {
    if (item.isEmpty) {
      continue;
    }
    final normalized = item.replaceAll('\\n', '\n');
    if (normalized.isEmpty) {
      continue;
    }
    if (normalized.length == 1) {
      if (normalized == '\n' || !RegExp(r'\s').hasMatch(normalized)) {
        seen.add(normalized);
      }
      continue;
    }
    for (final char in normalized.split('')) {
      if (char == '\n' || !RegExp(r'\s').hasMatch(char)) {
        seen.add(char);
      }
    }
  }
  return seen.toList();
}

int? _findNextSeparator(String text, int start, int end, List<String> separators) {
  if (separators.isEmpty) {
    return null;
  }
  final separatorSet = separators.toSet();
  for (var index = start; index < end; index += 1) {
    if (separatorSet.contains(text[index])) {
      return index + 1;
    }
  }
  return null;
}

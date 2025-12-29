import 'dart:math';

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
  final separatorSet = resolvedSeparators.toSet();
  final chunks = <String>[];
  var start = 0;

  while (start < normalized.length) {
    while (start < normalized.length && separatorSet.contains(normalized[start])) {
      start += 1;
    }
    if (start >= normalized.length) {
      break;
    }
    final remaining = normalized.length - start;
    final maxEnd = (start + safeMaxSize).clamp(0, normalized.length);
    final separatorIndex = _findNextSeparatorIndex(normalized, start, maxEnd, separatorSet);
    final separatorSize = separatorIndex != null ? separatorIndex - start : remaining;
    final targetSize = remaining <= safeMinSize
        ? remaining
        : min(safeMaxSize, max(safeMinSize, separatorSize));
    final useRemainingTail = remaining - targetSize < safeMinSize;
    final end = (start + (useRemainingTail ? remaining : targetSize)).clamp(0, normalized.length);
    final piece = normalized.substring(start, end).trim();
    if (piece.isNotEmpty) {
      chunks.add(piece);
    }
    if (end >= normalized.length) {
      break;
    }
    var nextStart = end - safeOverlap;
    if (nextStart == end && separatorIndex == end) {
      nextStart = min(end + 1, normalized.length);
    }
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

int? _findNextSeparatorIndex(String text, int start, int end, Set<String> separators) {
  if (separators.isEmpty) {
    return null;
  }
  for (var index = start; index < end; index += 1) {
    if (separators.contains(text[index])) {
      return index;
    }
  }
  return null;
}

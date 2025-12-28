import 'dart:math';

String createId(String prefix) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final random = Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '${prefix}_${now}_$random';
}

/// 格式化持续时间为「X小时Y分钟」或「X分钟」或「不到1分钟」
String formatDuration(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes <= 0) return '不到1分钟';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return '$hours小时$minutes分钟';
  if (hours > 0) return '$hours小时';
  return '$minutes分钟';
}

/// 格式化时间段起点 - 终点，如「09:00 - 09:45」
String formatTimeRange(DateTime start, DateTime? end) {
  final s =
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  if (end == null) return '$s - 现在';
  final e =
      '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  return '$s - $e';
}

class EpgProgramme {
  final DateTime start;
  final DateTime stop;
  final String title;

  EpgProgramme({
    required this.start,
    required this.stop,
    required this.title,
  });

  /// 是否正在进行
  bool isPlayingAt(DateTime now) {
    return now.isAfter(start) && now.isBefore(stop);
  }

  /// 剩余时长
  Duration remainingAt(DateTime now) {
    if (!isPlayingAt(now)) return Duration.zero;
    return stop.difference(now);
  }

  /// 播放进度（0.0 ~ 1.0）
  double progressAt(DateTime now) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    final elapsed = now.difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// 开始时间格式化 HH:mm
  String get startLabel {
    return '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  }

  /// 结束时间格式化 HH:mm
  String get stopLabel {
    return '${stop.hour.toString().padLeft(2, '0')}:${stop.minute.toString().padLeft(2, '0')}';
  }
}
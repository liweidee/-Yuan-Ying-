import 'epg_programme.dart';

class EpgChannel {
  final String id;
  final String displayName;
  final List<EpgProgramme> programmes;

  EpgChannel({
    required this.id,
    required this.displayName,
    required this.programmes,
  });

  /// 当前节目
  EpgProgramme? currentProgramme([DateTime? now]) {
    final n = now ?? DateTime.now();
    for (final p in programmes) {
      if (p.isPlayingAt(n)) return p;
    }
    return null;
  }

  /// 下一个节目
  EpgProgramme? nextProgramme([DateTime? now]) {
    final n = now ?? DateTime.now();
    for (final p in programmes) {
      if (p.start.isAfter(n)) return p;
    }
    return null;
  }

  /// 今天的节目（已按 start 排序）
  List<EpgProgramme> todayProgrammes([DateTime? now]) {
    final n = now ?? DateTime.now();
    return programmes
        .where((p) => p.start.year == n.year
            && p.start.month == n.month
            && p.start.day == n.day)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }
}
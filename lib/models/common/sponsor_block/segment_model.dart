import 'package:yuanying/models/common/sponsor_block/segment_type.dart';
import 'package:yuanying/models/common/sponsor_block/skip_type.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class SegmentModel implements Comparable<SegmentModel> {
  SegmentModel({
    required this.uuid,
    required this.segmentType,
    required this.segment,
    required this.skipType,
  });
  final String uuid;
  final SegmentType segmentType;
  final (int, int) segment;
  final SkipType skipType;
  bool hasSkipped = false;

  // 简化工厂方法，不再依赖 BlockConfigMixin
  factory SegmentModel.fromSimple({
    required String uuid,
    required String category,
    required int start,
    required int end,
    SkipType? skipType,
  }) {
    final segmentType = SegmentType.values.byName(category);
    final segment = (start, end);
    
    // 使用 PlayerPref 中的配置
    final effectiveSkipType = skipType ?? _getDefaultSkipType(segmentType);
    
    return SegmentModel(
      uuid: uuid,
      segmentType: segmentType,
      segment: segment,
      skipType: effectiveSkipType,
    );
  }

  static SkipType _getDefaultSkipType(SegmentType type) {
    // 从 PlayerPref 读取，或返回默认值
    final prefValue = PlayerPref.getSkipTypeForSegment(type.index);
    if (prefValue != null) {
      return SkipType.values[prefValue];
    }
    // 默认：仅显示
    return SkipType.showOnly;
  }

  @override
  int compareTo(SegmentModel other) => segment.$1.compareTo(other.segment.$1);
}

extension IntRecordExt on (int, int) {
  bool get isEq => $1 == $2;
  int get length => $2 - $1;
  bool contains(num other) => $1 <= other && other < $2;
}
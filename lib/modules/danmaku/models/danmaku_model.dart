/// 弹幕数据模型（纯展示）
class DanmakuItem {
  final String content;      // 弹幕内容
  final int color;          // 颜色（十进制 RGB，无 Alpha）
  final int progress;       // 出现时间（毫秒）
  final int mode;           // 1滚动 4底部 5顶部
  final int fontSize;       // 字体大小

  DanmakuItem({
    required this.content,
    required this.color,
    required this.progress,
    required this.mode,
    required this.fontSize,
  });

  factory DanmakuItem.fromJson(Map<String, dynamic> json) {
    return DanmakuItem(
      content: json['content']?.toString() ?? '',
      color: json['color'] ?? 0xFFFFFFFF,
      progress: json['progress'] ?? 0,
      mode: json['mode'] ?? 1,
      fontSize: json['fontSize'] ?? 25,
    );
  }

  // 从标准弹幕格式解析（如 B站 XML 格式）
  factory DanmakuItem.fromXml(Map<String, dynamic> data) {
    return DanmakuItem(
      content: data['text']?.toString() ?? data['content']?.toString() ?? '',
      color: int.tryParse(data['color']?.toString() ?? '') ?? 0xFFFFFFFF,
      progress: int.tryParse(data['progress']?.toString() ?? '0') ?? 0,
      mode: int.tryParse(data['mode']?.toString() ?? '1') ?? 1,
      fontSize: int.tryParse(data['fontSize']?.toString() ?? '25') ?? 25,
    );
  }

  /// 获取带不透明 Alpha 通道的颜色值
  /// 因为原始 color 存储的是 0xRRGGBB，缺少 Alpha，我们补全为 0xFFRRGGBB
  int get opaqueColor => 0xFF000000 | (color & 0x00FFFFFF);
}
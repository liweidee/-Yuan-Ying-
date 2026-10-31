// lib/modules/agent_llm/models/playback_context.dart

/// 当前播放上下文（供 AI 工具读取）
///
/// 由 DetailController 在开始播放时写入，关闭时清理。
/// 独立于 DetailController 的 tag 机制，只保存"最近一次播放"的快照。
class PlaybackContext {
  final String vodId;
  final String vodName;
  final String episodeName;
  final String siteKey;
  final String siteName;
  final String controllerTag;

  const PlaybackContext({
    required this.vodId,
    required this.vodName,
    required this.episodeName,
    required this.siteKey,
    required this.siteName,
    required this.controllerTag,
  });

  Map<String, dynamic> toJson() => {
        'vodId': vodId,
        'vodName': vodName,
        'episodeName': episodeName,
        'siteKey': siteKey,
        'siteName': siteName,
      };
}

class PlaybackContextRegistry {
  PlaybackContextRegistry._();
  static final PlaybackContextRegistry instance = PlaybackContextRegistry._();

  PlaybackContext? _current;
  PlaybackContext? get current => _current;

  void set(PlaybackContext ctx) => _current = ctx;

  /// 仅当传入的 tag 与当前上下文一致时才清理，避免多标签页误清。
  void clearByTag(String? tag) {
    if (tag == null || tag.isEmpty) return;
    if (_current?.controllerTag == tag) {
      _current = null;
    }
  }

  void clear() => _current = null;
}
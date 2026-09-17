import 'package:yuanying/modules/video/controllers/playback_event_listener.dart';
import '../models/jellyfin_server_model.dart';
import 'jellyfin_api_service.dart';

/// 播放信息（itemId + mediaSourceId）
class JellyfinPlaybackTarget {
  final String itemId;
  final String mediaSourceId;

  const JellyfinPlaybackTarget({
    required this.itemId,
    required this.mediaSourceId,
  });
}

/// Jellyfin 播放事件监听器
class JellyfinPlaybackListener implements PlaybackEventListener {
  final JellyfinServer server;
  final String token;

  /// T4 侧 `Episode.name` → (itemId + mediaSourceId)
  final Map<String, JellyfinPlaybackTarget> nameToTarget;

  final JellyfinApiService _api = JellyfinApiService();

  String? _playSessionId;

  JellyfinPlaybackListener({
    required this.server,
    required this.token,
    required this.nameToTarget,
  });

  JellyfinPlaybackTarget? _resolveTarget(String episodeName) {
    if (episodeName.isEmpty) return null;
    return nameToTarget[episodeName];
  }

  bool get _isReady =>
      server.userId != null && server.userId!.isNotEmpty;

  String _generateSessionId() =>
      'yuanying_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void onPlaybackStart({
    required String episodeName,
    required Duration position,
    required Duration duration,
  }) {
    if (!_isReady) return;
    final target = _resolveTarget(episodeName);
    if (target == null) return;

    _playSessionId = _generateSessionId();

    _api.reportPlaybackStart(
      userId: server.userId!,
      token: token,
      baseUrl: server.baseUrl,
      itemId: target.itemId,
      mediaSourceId: target.mediaSourceId,
      playSessionId: _playSessionId!,
    );
  }

  @override
  void onPlaybackProgress({
    required String episodeName,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
  }) {
    if (!_isReady) return;
    final target = _resolveTarget(episodeName);
    if (target == null) return;
    _playSessionId ??= _generateSessionId();

    _api.reportPlaybackProgress(
      userId: server.userId!,
      token: token,
      baseUrl: server.baseUrl,
      itemId: target.itemId,
      mediaSourceId: target.mediaSourceId,
      playSessionId: _playSessionId!,
      position: position,
      isPaused: !isPlaying,
    );
  }

  @override
  void onPlaybackStop({
    required String episodeName,
    required Duration position,
    required Duration duration,
  }) {
    if (!_isReady) return;
    final target = _resolveTarget(episodeName);
    if (target == null) return;
    _playSessionId ??= _generateSessionId();

    _api.reportPlaybackStopped(
      userId: server.userId!,
      token: token,
      baseUrl: server.baseUrl,
      itemId: target.itemId,
      mediaSourceId: target.mediaSourceId,
      playSessionId: _playSessionId!,
      position: position,
    );

    // 播放超过 30 秒显式标记已看（保证进历史）
    if (position.inSeconds >= 30) {
      _api.markPlayed(
        userId: server.userId!,
        token: token,
        baseUrl: server.baseUrl,
        itemId: target.itemId,
      );
    }

    _playSessionId = null;
  }
}
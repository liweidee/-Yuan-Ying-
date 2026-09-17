/// 播放事件监听接口
///
/// T4 播放器通过 `args['playbackEventListener']` 接受外部监听器，
/// 在播放开始 / 进度更新 / 播放停止时回调。
///
/// **未注入时（默认）T4 播放器不做任何回调**，行为与原版完全一致。
///
/// 使用场景：Jellyfin 等需要客户端主动上报播放状态的服务器。
abstract class PlaybackEventListener {
  /// 播放开始（进入播放页或切换集时触发）
  void onPlaybackStart({
    required String episodeName,
    required Duration position,
    required Duration duration,
  });

  /// 播放进度更新（每 ~10 秒触发一次）
  void onPlaybackProgress({
    required String episodeName,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
  });

  /// 播放停止（页面关闭 / 播放完成 / 切集时触发）
  void onPlaybackStop({
    required String episodeName,
    required Duration position,
    required Duration duration,
  });
}
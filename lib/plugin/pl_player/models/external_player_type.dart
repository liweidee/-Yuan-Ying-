/// 第三方播放器类型
enum ExternalPlayerType {
  /// MPV（推荐）
  mpv('MPV'),

  /// VLC
  vlc('VLC'),

  /// PotPlayer
  potPlayer('PotPlayer');

  /// 用于 UI 展示的名称
  final String label;

  const ExternalPlayerType(this.label);
}
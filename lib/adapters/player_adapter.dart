import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/models/data_source.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'video_adapter.dart';

/// 播放器适配器
class PlayerAdapter {
  final PlPlayerController controller;
  String? currentVodId;
  List<PlayQuality>? currentQualities;
  String? _currentPlayUrl;

  String? get currentPlayUrl => _currentPlayUrl;

  PlayerAdapter({required this.controller});

  Future<void> loadPlayUrl(PlayUrl playUrl, {Duration? seekTo}) async {
    // 使用默认画质（第一个）
    final defaultUrl = playUrl.defaultUrl;
    if (defaultUrl == null) return;
    
    _currentPlayUrl = defaultUrl;
    final dataSource = VideoAdapter.toDataSource(playUrl);
    await controller.setDataSource(
      dataSource,
      autoplay: true,
      seekTo: seekTo,
    );
  }

  Future<void> loadPlayUrlWithQualities(
    PlayUrl playUrl, {
    Duration? seekTo,
  }) async {
    _currentPlayUrl = playUrl.defaultUrl;
    currentQualities = playUrl.qualities;
    
    if (playUrl.qualities.isNotEmpty) {
      await loadPlayUrl(playUrl, seekTo: seekTo);
    }
  }

  Future<void> switchQuality(PlayQuality quality, {Duration? seekTo}) async {
    _currentPlayUrl = quality.url;
    final position = seekTo ?? controller.position;
    final dataSource = NetworkSource(videoSource: quality.url, audioSource: null);
    await controller.setDataSource(
      dataSource,
      autoplay: true,
      seekTo: position,
    );
  }

  Future<void> switchEpisode(
    String playParams,
    Future<PlayUrl> Function(String params) fetchPlayUrl,
  ) async {
    final playUrl = await fetchPlayUrl(playParams);
    await loadPlayUrlWithQualities(playUrl);
  }

  List<PlayQuality>? getQualities() => currentQualities;

  void dispose() {
    controller.dispose();
  }
}
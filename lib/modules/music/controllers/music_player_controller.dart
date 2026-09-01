// lib/modules/music/controllers/music_player_controller.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/services/resource_sniffer.dart';
import 'package:yuanying/services/parser_service.dart';
import 'package:yuanying/modules/music/services/music_player.dart';
import 'package:yuanying/modules/music/services/audio_player_handler.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/core/constants/app_constants.dart';

// ===== 音频文件后缀列表 =====
const List<String> _audioExtensions = ['.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma', '.alac'];

enum MusicPlayMode {
  signalLoop(1, '单曲循环', Icons.repeat_one),
  random(2, '随机播放', Icons.shuffle),
  listLoop(3, '列表循环', Icons.repeat),
  listOrder(4, '顺序播放', Icons.list);

  const MusicPlayMode(this.value, this.name, this.icon);
  final int value;
  final String name;
  final IconData icon;

  static MusicPlayMode getByValue(int value) {
    return values.firstWhere((element) => element.value == value);
  }
}

class MusicPlayerController extends GetxController {
  final AudioPlayerHandler _handler = AudioPlayerHandler();
  AudioPlayerHandler get handler => _handler;

  final SourceManager _sourceManager = Get.find<SourceManager>();

  // ===== 播放列表 =====
  final RxList<Episode> playlist = <Episode>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool playing = false.obs;
  final RxBool isLoading = false.obs;

  // ===== 歌曲信息 =====
  final RxString coverUrl = ''.obs;
  final RxString author = ''.obs;
  final RxString albumName = ''.obs;
  final RxString lyric = ''.obs;
  final RxString currentPlayUrl = ''.obs;

  // ===== 播放模式 =====
  final Rx<MusicPlayMode> playMode = MusicPlayMode.listLoop.obs;

  final RxInt favoriteVersion = 0.obs;

  // ===== 解析相关 =====
  final RxList<ParserSource> parserSources = <ParserSource>[].obs;
  final Rxn<ParserSource> currentParser = Rxn<ParserSource>();
  final RxBool showParserButton = false.obs;
  final RxBool isManualParser = false.obs;

  // ===== 当前 vodId =====
  String? _currentVodId;
  String? get currentVodId => _currentVodId;

  // ===== 定时器相关 =====
  final RxInt timerMinutes = 0.obs;            // 0=无定时，-1=播放完当前曲目
  final RxBool stopAfterCurrent = false.obs;
  Timer? _timer;

  // ===== 倍速 =====
  final RxDouble speed = 1.0.obs;
  final List<double> speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ===== 跳过片头片尾（仅当前会话有效） =====
  final RxInt skipStartDuration = 0.obs;
  final RxInt skipEndDuration = 0.obs;

  Episode? get currentEpisode {
    if (playlist.isEmpty || currentIndex.value >= playlist.length) return null;
    return playlist[currentIndex.value];
  }

  VoidCallback? onPlayCompleted;

  @override
  void onInit() {
    super.onInit();
    _loadPlayMode();

    _handler.player.onPlayCompleted = _handlePlayCompleted;

    _handler.player.playingStream.listen((isPlaying) {
      playing.value = isPlaying;
    });

    // 监听位置变化以实现跳过片头片尾
    _handler.player.positionStream.listen((position) {
      _checkSkip(position);
    });
  }

  @override
  void onClose() {
    _cancelTimer();
    _handler.disposeHandler();
    super.onClose();
  }

  // ===== 初始化 =====
  Future<void> init() async {
    await _handler.player.init();
  }

  // ===== 播放列表 =====
  void setPlaylist(List<Episode> episodes, {int initialIndex = 0, String? vodId}) {
    if (episodes.isEmpty) return;
    playlist.value = episodes;
    _currentVodId = vodId;

    int savedIndex = initialIndex;
    if (vodId != null && vodId.isNotEmpty) {
      final loaded = _loadCurrentIndex(vodId);
      if (loaded != null && loaded >= 0 && loaded < episodes.length) {
        savedIndex = loaded;
      }
    }
    currentIndex.value = savedIndex;
  }

  void updateSongInfo({String? cover, String? author, String? album}) {
    if (cover != null) coverUrl.value = cover;
    if (author != null) this.author.value = author;
    if (album != null) albumName.value = album;
  }

  void setLyric(String lrcText) {
    lyric.value = lrcText;
  }

  void notifyFavoriteChanged() {
    favoriteVersion.value++;
  }

  void _addToHistory() {
    if (_currentVodId == null || _currentVodId!.isEmpty) return;
    final episode = currentEpisode;
    if (episode == null) return;
    final sourceManager = Get.find<SourceManager>();
    final site = sourceManager.currentSite.value;
    final apiUrl = site?['api']?.toString() ?? '';
    if (apiUrl.isEmpty) return;

    final historyList = GStorage.getHistory();
    final existingIndex = historyList.indexWhere(
      (item) => item['vod_id'] == _currentVodId && item['api_url'] == apiUrl,
    );

    final historyItem = {
      'vod_id': _currentVodId,
      'vod_name': episode.name,
      'vod_pic': coverUrl.value,
      'vod_remarks': episode.name,
      'vod_tag': '',
      'type_name': sourceManager.currentSite.value?['name']?.toString() ?? '音乐',
      'api_url': apiUrl,
      'site_key': site?['key']?.toString() ?? '',
      'config_key': sourceManager.currentConfigKey.value,
      'progress': '',  // 音乐无进度
      'watchTime': DateTime.now().millisecondsSinceEpoch,
      'detail_type': DetailType.audio,
    };

    if (existingIndex != -1) {
      historyList[existingIndex] = historyItem;
    } else {
      historyList.insert(0, historyItem);
    }
    GStorage.saveHistory(historyList);
  }

  // ===== 核心播放方法 =====
  bool _isAudioFileUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final ext = path.split('.').last.toLowerCase();
      return _audioExtensions.contains('.$ext');
    } catch (_) {
      return false;
    }
  }

  Future<void> playWithUrl(PlayUrl playUrl, {int? index}) async {
    final targetIndex = index ?? currentIndex.value;
    if (targetIndex < 0 || targetIndex >= playlist.length) return;

    isLoading.value = true;
    currentIndex.value = targetIndex;
    final episode = playlist[targetIndex];

    if (_currentVodId != null && _currentVodId!.isNotEmpty) {
      _saveCurrentIndex(_currentVodId!, targetIndex);
    }

    try {
      final url = playUrl.defaultUrl;
      if (url != null && _isAudioFileUrl(url)) {
        await _handleDirectPlay(playUrl, episode);
        return;
      }

      if (playUrl.needParser) {
        await _handleParser(playUrl, episode);
        return;
      }

      if (playUrl.isDirect) {
        await _handleDirectPlay(playUrl, episode);
        return;
      }

      if (playUrl.needSniff) {
        await _handleSniff(playUrl, episode);
        return;
      }

      ToastUtils.show('未知的播放类型');
    } catch (e) {
      ToastUtils.show('播放失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ===== 直链播放 =====
  Future<void> _handleDirectPlay(PlayUrl playUrl, Episode episode) async {
    final url = playUrl.defaultUrl;
    if (url == null || url.isEmpty) {
      ToastUtils.show('获取播放地址失败');
      return;
    }

    currentPlayUrl.value = url;
    _handleLyric(playUrl);

    try {
      await _handler.player.stop();
      await Future.delayed(const Duration(milliseconds: 100));
      await _handler.play(
        music: episode,
        url: url,
        headers: playUrl.headers,
      );
      _addToHistory();
      _handler.current = episode;
      // 应用当前倍速
      await _handler.player.audio.setSpeed(speed.value);
    } catch (e) {
      if (e.toString().contains('PlayerInterruptedException')) {
        return;
      }
      rethrow;
    }
  }

  // ===== 嗅探播放 =====
  Future<void> _handleSniff(PlayUrl playUrl, Episode episode) async {
    final site = _sourceManager.currentSite.value;
    String? sniffUrl = playUrl.defaultUrl;

    if (sniffUrl == null || sniffUrl.isEmpty) {
      ToastUtils.show('嗅探URL无效');
      return;
    }

    if (!sniffUrl.startsWith('http://') && !sniffUrl.startsWith('https://')) {
      final apiBase = site?['api']?.toString() ?? '';
      if (apiBase.isNotEmpty) {
        final uri = Uri.parse(apiBase);
        final baseWithoutQuery = uri.replace(query: '', fragment: '').toString();
        final baseUrl = baseWithoutQuery.endsWith('/') ? baseWithoutQuery : '$baseWithoutQuery/';
        final relativePath = sniffUrl.startsWith('/') ? sniffUrl.substring(1) : sniffUrl;
        sniffUrl = baseUrl + relativePath;
      } else {
        ToastUtils.show('无法获取播放地址');
        return;
      }
    }

    _showSniffLoading();

    final sniffedUrl = await ResourceSniffer.sniff(
      url: sniffUrl,
      headers: playUrl.headers,
      script: playUrl.script,
      useWebView: true,
    );

    SmartDialog.dismiss();

    if (sniffedUrl == null) {
      ToastUtils.show('嗅探失败，请尝试其他方式');
      return;
    }

    final sniffedPlayUrl = PlayUrl(
      parse: 0,
      qualities: [PlayQuality(label: '嗅探', url: sniffedUrl)],
      headers: playUrl.headers,
      lrc: playUrl.lrc,
      danmaku: playUrl.danmaku,
    );

    await _handleDirectPlay(sniffedPlayUrl, episode);
  }

  // ===== 解析播放 =====
  Future<void> _handleParser(PlayUrl playUrl, Episode episode) async {
    _loadParsers();

    if (parserSources.isEmpty) {
      ToastUtils.show('暂无可用解析源');
      return;
    }

    showParserButton.value = true;

    _showParserLoading();

    final result = await _parseWithAllParsers(
      playUrl,
      preferredParser: isManualParser.value ? currentParser.value : null,
    );

    SmartDialog.dismiss(force: true);

    if (result != null) {
      await _handleDirectPlay(result, episode);
    } else {
      if (isManualParser.value && currentParser.value != null) {
        ToastUtils.show('${currentParser.value!.name} 解析失败');
      } else {
        ToastUtils.show('所有解析源均失败，请切换线路');
      }
    }
  }

  // ===== 歌词处理 =====
  void _handleLyric(PlayUrl playUrl) {
    if (playUrl.lrc != null && playUrl.lrc!.isNotEmpty) {
      _loadLyricFromUrl(playUrl.lrc!);
    } else if (playUrl.danmaku != null && playUrl.danmaku!.isNotEmpty) {
      lyric.value = playUrl.danmaku!;
    } else {
      lyric.value = '';
    }
  }

  Future<void> _loadLyricFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        lyric.value = response.body;
      }
    } catch (e) {}
  }

  // ===== 解析相关 =====
  void _loadParsers() {
    final parseList = _sourceManager.parses;
    if (parseList.isNotEmpty) {
      final sources = parseList
          .map((e) => ParserSource.fromJson(e))
          .where((e) => e.url.isNotEmpty)
          .toList();
      parserSources.value = sources;
    }
  }

  Future<PlayUrl?> _parseWithAllParsers(
    PlayUrl playUrl, {
    ParserSource? preferredParser,
  }) async {
    final sources = parserSources;
    if (sources.isEmpty) return null;

    if (preferredParser != null) {
      return _processWithParser(playUrl, preferredParser);
    }

    for (final parser in sources) {
      final result = await _processWithParser(playUrl, parser);
      if (result != null) {
        currentParser.value = parser;
        return result;
      }
    }
    return null;
  }

  Future<PlayUrl?> _processWithParser(PlayUrl playUrl, ParserSource parser) async {
    try {
      final fullUrl = '${parser.url}${Uri.encodeComponent(playUrl.defaultUrl ?? '')}';

      if (parser.type == 1) {
        final response = await Dio().get(
          fullUrl,
          options: Options(
            headers: parser.headers ?? {},
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
        final data = response.data;
        if (data is Map) {
          final url = data['url']?.toString() ??
              data['playUrl']?.toString() ??
              data['play_url']?.toString();
          if (url != null && url.startsWith('http')) {
            return PlayUrl(
              parse: 0,
              qualities: [PlayQuality(label: '解析', url: url)],
              headers: parser.headers,
            );
          }
        }
        return null;
      }

      if (parser.type == 0) {
        final sniffedUrl = await ResourceSniffer.sniff(
          url: fullUrl,
          headers: parser.headers,
          useWebView: true,
        );
        if (sniffedUrl != null) {
          return PlayUrl(
            parse: 0,
            qualities: [PlayQuality(label: '解析', url: sniffedUrl)],
            headers: parser.headers,
          );
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ===== 加载提示 =====
  void _showSniffLoading() {
    SmartDialog.show(
      maskColor: Colors.black54,
      animationType: SmartAnimationType.scale,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text('正在嗅探播放地址...', style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  void _showParserLoading() {
    SmartDialog.show(
      maskColor: Colors.black54,
      animationType: SmartAnimationType.scale,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
            const SizedBox(height: 14),
            const Text('正在解析中...', style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ===== 播放控制 =====
  Future<void> togglePlay() async {
    if (_handler.player.isPlaying) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> pause() async {
    await _handler.pause();
  }

  Future<void> playNext() async {
    final nextIndex = _getNextIndex();
    if (nextIndex < 0) {
      ToastUtils.show('已是最后一首');
      return;
    }
    currentIndex.value = nextIndex;
    if (_currentVodId != null && _currentVodId!.isNotEmpty) {
      _saveCurrentIndex(_currentVodId!, nextIndex);
    }
    onPlayCompleted?.call();
  }

  Future<void> playPrev() async {
    final prevIndex = _getPrevIndex();
    if (prevIndex < 0) {
      ToastUtils.show('已是第一首');
      return;
    }
    currentIndex.value = prevIndex;
    if (_currentVodId != null && _currentVodId!.isNotEmpty) {
      _saveCurrentIndex(_currentVodId!, prevIndex);
    }
    onPlayCompleted?.call();
  }

  Future<void> seek(Duration position) async {
    await _handler.seek(position);
  }

  Future<void> resetPlayer() async {
    await _handler.player.stop();
    await _handler.player.seek(Duration.zero);
    lyric.value = '';
    currentPlayUrl.value = '';
    playing.value = false;
  }

  // ===== 播放模式 =====
  void togglePlayMode() {
    final modes = MusicPlayMode.values;
    final current = playMode.value;
    final index = modes.indexOf(current);
    playMode.value = modes[(index + 1) % modes.length];
    _savePlayMode(playMode.value);
    ToastUtils.show('切换到 ${playMode.value.name}');
  }

  // ===== 倍速方法 =====
  Future<void> setSpeed(double newSpeed) async {
    speed.value = newSpeed;
    await _handler.player.audio.setSpeed(newSpeed);
  }

  void toggleSpeed() {
    final current = speed.value;
    final index = speedOptions.indexOf(current);
    final nextIndex = (index + 1) % speedOptions.length;
    setSpeed(speedOptions[nextIndex]);
  }

  // ===== 跳过片头片尾 =====
  void _checkSkip(Duration position) {
    final start = skipStartDuration.value;
    final end = skipEndDuration.value;
    final duration = _handler.player.duration;
    if (duration.inSeconds == 0) return;

    if (start > 0 && position.inSeconds < start) {
      _handler.seek(Duration(seconds: start));
      return;
    }

    if (end > 0 && duration.inSeconds > end) {
      final target = duration.inSeconds - end;
      if (position.inSeconds >= target && position.inSeconds < target + 1) {
        _handler.seek(Duration(seconds: target));
      }
    }
  }

  // ===== 定时器方法 =====
  void setTimer(int minutes) {
    _cancelTimer();
    stopAfterCurrent.value = false;
    if (minutes == -1) {
      stopAfterCurrent.value = true;
      timerMinutes.value = -1;
      ToastUtils.show('将在当前曲目播放完毕后暂停');
    } else if (minutes > 0) {
      timerMinutes.value = minutes;
      _timer = Timer(Duration(minutes: minutes), () {
        _handleTimerEnd();
      });
      ToastUtils.show('已设置 ${minutes} 分钟后暂停');
    } else {
      timerMinutes.value = 0;
      ToastUtils.show('已取消定时');
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _handleTimerEnd() {
    _cancelTimer();
    timerMinutes.value = 0;
    if (isPlaying) {
      pause();
      ToastUtils.show('定时结束，已暂停播放');
    } else {
      ToastUtils.show('定时结束，但播放器已暂停');
    }
  }

  // ===== 内部方法 =====
  void _handlePlayCompleted() {
    if (stopAfterCurrent.value) {
      stopAfterCurrent.value = false;
      timerMinutes.value = 0;
      pause();
      ToastUtils.show('当前曲目已播放完毕，已暂停');
      return;
    }
    final nextIndex = _getNextIndex();
    if (nextIndex >= 0) {
      currentIndex.value = nextIndex;
      if (_currentVodId != null && _currentVodId!.isNotEmpty) {
        _saveCurrentIndex(_currentVodId!, nextIndex);
      }
      onPlayCompleted?.call();
    } else {
      _handler.pause();
      playing.value = false;
      ToastUtils.show('播放列表已结束');
    }
  }

  int _getNextIndex() {
    if (playlist.isEmpty) return -1;
    switch (playMode.value) {
      case MusicPlayMode.signalLoop:
        return currentIndex.value;
      case MusicPlayMode.random:
        return Random().nextInt(playlist.length);
      case MusicPlayMode.listLoop:
        return (currentIndex.value + 1) % playlist.length;
      case MusicPlayMode.listOrder:
        if (currentIndex.value >= playlist.length - 1) return -1;
        return currentIndex.value + 1;
    }
  }

  int _getPrevIndex() {
    if (playlist.isEmpty) return -1;
    switch (playMode.value) {
      case MusicPlayMode.signalLoop:
        return currentIndex.value;
      case MusicPlayMode.random:
        return Random().nextInt(playlist.length);
      case MusicPlayMode.listLoop:
        return (currentIndex.value - 1 + playlist.length) % playlist.length;
      case MusicPlayMode.listOrder:
        if (currentIndex.value <= 0) return -1;
        return currentIndex.value - 1;
    }
  }

  // ===== 播放索引存储 =====
  static const String _storageMusicIndex = 'music_index_';

  void _saveCurrentIndex(String vodId, int index) {
    StorageManager.setSetting('$_storageMusicIndex$vodId', index);
  }

  int? _loadCurrentIndex(String vodId) {
    return StorageManager.getSetting<int>('$_storageMusicIndex$vodId');
  }

  void _savePlayMode(MusicPlayMode mode) {
    StorageManager.setSetting(SettingBoxKey.musicPlayMode, mode.value);
  }

  void _loadPlayMode() {
    final value = StorageManager.getSetting<int>(SettingBoxKey.musicPlayMode);
    if (value != null) {
      playMode.value = MusicPlayMode.getByValue(value);
    }
  }

  // ===== 对外属性 =====
  bool get isPlaying => _handler.player.isPlaying;
  Duration get position => _handler.player.position;
  Duration get duration => _handler.player.duration;
  Stream<Duration> get positionStream => _handler.player.positionStream;
  String get currentSongName => currentEpisode?.name ?? '未选择歌曲';
}
// lib/modules/live/controllers/live_controller.dart
import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:window_manager/window_manager.dart' hide WindowCaption;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/live/models/live_channel.dart';
import 'package:yuanying/modules/live/models/epg_channel.dart';
import 'package:yuanying/modules/live/models/epg_programme.dart';
import 'package:yuanying/modules/live/services/live_parser_service.dart';
import 'package:yuanying/modules/live/services/live_epg_service.dart';
import 'package:yuanying/modules/live/services/channel_logo_service.dart';
import 'package:yuanying/modules/live/widgets/live_player_view.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';

import 'package:yuanying/plugin/pl_player/models/video_fit_type.dart';
import 'package:yuanying/plugin/pl_player/utils/fullscreen.dart';

class LiveController extends GetxController {
  static LiveController get to => Get.find<LiveController>(tag: 'live');

  // ===== 独立播放器实例 =====
  Player? _player;
  VideoController? _videoController;
  bool _isPlayerInitialized = false;

  // ===== 状态 =====
  final Rx<LiveConfig?> currentConfig = Rx(null);
  final RxList<LiveChannel> channels = <LiveChannel>[].obs;
  final RxList<String> groups = <String>[].obs;
  final RxString selectedGroup = ''.obs;
  final Rx<LiveChannel?> currentChannel = Rx(null);
  final RxBool isPlaying = false.obs;
  final RxBool isLoading = false.obs;
  final RxBool isBuffering = false.obs;

  // ===== 错误信息 =====
  final RxString errorMessage = ''.obs;

  // ===== 全屏状态 =====
  final RxBool isFullScreen = false.obs;

  // ===== 播放进度 =====
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;

  // ===== 画面比例 =====
  final Rx<VideoFitType> videoFit = VideoFitType.contain.obs;

  // ===== 控制条显隐 =====
  final RxBool controlsVisible = false.obs;
  Timer? _hideControlsTimer;

  // ===== 用户主动暂停标志 =====
  final RxBool userPaused = false.obs;

  // ===== 音量 & 亮度 =====
  final RxDouble volume = 1.0.obs;
  final RxDouble brightness = (-1.0).obs;

  // ===== 全屏 Overlay =====
  OverlayEntry? _fullScreenOverlay;

  // ===== 内部标志 =====
  bool _isFirstLoad = true;
  bool _isPlayingChannel = false;

  // 静默刷新令牌
  // 每次 _silentRefreshChannels 开始时自增，playChannel / _playChannelInternal
  // 也会自增。Dio 返回后校验令牌，不一致则丢弃本次结果，
  // 避免用旧的 currentChannelUrl 覆盖用户的新选择。
  int _refreshToken = 0;

  // ===== 记录当前加载的配置 key，用于检测是否切换了配置 =====
  String? _currentConfigKey;

  // ===== 全屏 MethodChannel =====
  static const MethodChannel _mediaKitChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  // ============================================================
  // EPG 相关
  // ============================================================
  /// EPG 频道映射：channelId -> EpgChannel
  final RxMap<String, EpgChannel> epgMap = <String, EpgChannel>{}.obs;

  /// EPG 是否加载中
  final RxBool epgLoading = false.obs;

  /// EPG 错误信息
  final RxString epgError = ''.obs;

  /// 节目边界定时器（节目切换时触发刷新，其他时间不触发）
  Timer? _epgBoundaryTimer;

  /// 记录 EPG 最近一次加载成功的日期
  /// 用于跨天检测：当 currentProgramme == null 且当前日期 != _epgLoadDate 时，
  /// 说明 EPG 已过期（跨天），需要重新加载。
  DateTime? _epgLoadDate;

  /// 当前频道的 EPG
  EpgChannel? get currentEpg {
    final ch = currentChannel.value;
    if (ch == null || epgMap.isEmpty) return null;
    return EpgMatcher.match(ch, epgMap);
  }

  /// 当前节目
  EpgProgramme? get currentProgramme {
    final epg = currentEpg;
    if (epg == null) return null;
    return epg.currentProgramme();
  }

  /// 下一个节目
  EpgProgramme? get nextProgramme {
    final epg = currentEpg;
    if (epg == null) return null;
    return epg.nextProgramme();
  }

  /// 今天的节目单
  List<EpgProgramme> get todayProgrammes {
    final epg = currentEpg;
    if (epg == null) return [];
    return epg.todayProgrammes();
  }

  // ===== 缓存参数 =====
  Map<String, String> get _buffer {
    final bufSec = 120.0;
    final bufSiz = (64 * 0x100000).toStringAsFixed(0);
    return {
      'cache': 'yes',
      'cache-secs': bufSec.toStringAsFixed(3),
      'demuxer-hysteresis-secs': (bufSec / 1.5).toStringAsFixed(3),
      'demuxer-max-bytes': bufSiz,
      'demuxer-max-back-bytes': bufSiz,
      'demuxer-readahead-secs': '30',
    };
  }

  VideoController? get videoController => _videoController;

  // ============================================================
  // 初始化 & 生命周期
  // ============================================================

  @override
  void onInit() {
    super.onInit();
    if (!Get.isRegistered<LiveController>(tag: 'live')) {
      Get.put(this, tag: 'live', permanent: true);
    }
    _initPlayer();
    _loadConfigAndChannels(forceLoading: true);
    _initVolumeAndBrightness();

    // 清理 7 天前的 EPG 缓存（非阻塞）
    LiveEpgService.clearOldCache();
  }

  void ensurePlayerInitialized() {
    if (!_isPlayerInitialized) _initPlayer();
  }

  void _initPlayer() {
    if (_isPlayerInitialized) return;

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        protocolWhitelist: const [
          'file', 'http', 'https', 'tcp', 'tls',
          'crypto', 'hls', 'applehttp', 'udp', 'rtp', 'data'
        ],
        logLevel: MPVLogLevel.error,
      ),
    );
    _videoController = VideoController(_player!);
    _isPlayerInitialized = true;

    _player!.stream.playing.listen((playing) {
      isPlaying.value = playing;
      if (playing) {
        userPaused.value = false;
        _resetHideTimer();
      }
    });

    _player!.stream.buffering.listen((buffering) {
      isBuffering.value = buffering;
    });

    _player!.stream.error.listen((error) {
      SmartDialog.showToast('播放失败: $error');
    });

    _player!.stream.position.listen((pos) {
      position.value = pos;
    });

    _player!.stream.duration.listen((dur) {
      duration.value = dur;
    });
  }

  void _initVolumeAndBrightness() async {
    try {
      final sysBrightness = await ScreenBrightnessPlatform.instance.system;
      brightness.value = sysBrightness;
    } catch (_) {}
    volume.value = 1.0;
  }

  @override
  void onClose() {
    _hideControlsTimer?.cancel();
    _cancelEpgBoundaryTimer();
    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;
    if (PlatformUtils.isMobile) {
      portraitUpMode();
    }
    super.onClose();
  }

  // ============================================================
  // 控制条显隐
  // ============================================================

  void showControls() {
    controlsVisible.value = true;
    _resetHideTimer();
  }

  void hideControls() {
    controlsVisible.value = false;
    _hideControlsTimer?.cancel();
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    if (isPlaying.value) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        hideControls();
      });
    }
  }

  // ============================================================
  // 播放控制
  // ============================================================

  void togglePlayPause() {
    if (!_isPlayerInitialized) _initPlayer();
    if (isPlaying.value) {
      userPaused.value = true;
      _player!.pause();
    } else {
      userPaused.value = false;
      _player!.play();
      showControls();
    }
  }

  void pause() {
    if (_player != null && isPlaying.value) {
      userPaused.value = true;
      _player!.pause();
    }
  }

  void play() {
    if (_player != null && !isPlaying.value) {
      userPaused.value = false;
      _player!.play();
      showControls();
    }
  }

  // ============================================================
  // 系统自动暂停/恢复
  // ============================================================

  void pauseBySystem() {
    if (_player != null && isPlaying.value) {
      _player!.pause();
    }
  }

  void resumeBySystem() {
    if (_player != null && !isPlaying.value && !userPaused.value && currentChannel.value != null) {
      _player!.play();
      showControls();
    }
  }

  // ============================================================
  // 音量控制
  // ============================================================

  Future<void> setVolume(double value, {bool showIndicator = true}) async {
    final clamped = value.clamp(0.0, 2.0);
    volume.value = clamped;
    if (_player != null) {
      await _player!.setVolume(clamped * 100);
    }
  }

  // ============================================================
  // 亮度控制
  // ============================================================

  Future<void> setBrightness(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    brightness.value = clamped;
    try {
      await ScreenBrightnessPlatform.instance.setSystemScreenBrightness(clamped);
    } catch (_) {}
  }

  // ============================================================
  // 重置播放器
  // ============================================================

  void resetPlayer() {
    if (_player != null) {
      _player!.stop();
    }
    channels.clear();
    groups.clear();
    selectedGroup.value = '';
    currentChannel.value = null;
    isPlaying.value = false;
    isLoading.value = false;
    isBuffering.value = false;
    userPaused.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    _isFirstLoad = true;
  }

  // ============================================================
  // 加载配置和频道
  // ============================================================

  /// [forceLoading] 是否强制显示全局 loading
  ///   - true: 强制显示 loading（切换配置时使用）
  ///   - false: 如果有数据则静默刷新（切换 Tab 时使用）
  Future<void> _loadConfigAndChannels({bool forceLoading = false}) async {
    final configKey = StorageManager.getSetting<String>(SettingBoxKey.liveCurrentKey);
    final configs = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ?? [];

    // ===== 获取目标配置 =====
    String? targetConfigKey;
    LiveConfig? targetConfig;

    if (configKey != null && configKey.isNotEmpty) {
      for (var item in configs) {
        final config = LiveConfig.fromJson(Map<String, dynamic>.from(item));
        if (config.key == configKey) {
          targetConfigKey = config.key;
          targetConfig = config;
          break;
        }
      }
    }
    if (targetConfigKey == null && configs.isNotEmpty) {
      final first = LiveConfig.fromJson(Map<String, dynamic>.from(configs.first));
      targetConfigKey = first.key;
      targetConfig = first;
    }

    final bool configKeyChanged = _currentConfigKey != targetConfigKey;

    // ===== 检测配置内容是否变化（URL 变了也算） =====
    bool configContentChanged = false;
    if (!configKeyChanged && currentConfig.value != null && targetConfig != null) {
      configContentChanged = currentConfig.value!.url != targetConfig.url;
    }

    final bool configChanged = configKeyChanged || configContentChanged;

    // ===== 场景判断 =====
    // 1. 有数据 + 配置没变 + 无错误 + 不强制加载 → 静默刷新
    if (channels.isNotEmpty && 
        errorMessage.value.isEmpty && 
        !configChanged && 
        !forceLoading) {
      _silentRefreshChannels();
      return;
    }

    // 2. 其他情况：显示 loading
    errorMessage.value = '';
    isLoading.value = true;

    // ===== 配置变化时，清空当前频道并停止播放 =====
    if (configChanged || forceLoading) {
      _currentConfigKey = targetConfigKey;
      currentChannel.value = null;
      _player?.stop();
      isPlaying.value = false;

      // ===== 配置变化时清空 EPG（下次加载新配置的 EPG） =====
      epgMap.clear();
      epgError.value = '';
      _epgLoadDate = null;   // 同步清空加载日期
      _cancelEpgBoundaryTimer();
    }

    try {
      if (configs.isEmpty) {
        errorMessage.value = '暂无直播配置，请添加配置';
        isLoading.value = false;
        resetPlayer();
        return;
      }

      LiveConfig? found = targetConfig;
      if (found == null && configs.isNotEmpty) {
        found = LiveConfig.fromJson(Map<String, dynamic>.from(configs.first));
        _currentConfigKey = found.key;
      }

      if (found == null) {
        errorMessage.value = '暂无有效的直播配置';
        isLoading.value = false;
        resetPlayer();
        return;
      }

      currentConfig.value = found;
      await _loadChannelsFromRemote(found, showLoading: true);

    } catch (e) {
      errorMessage.value = '加载直播配置失败: $e';
      isLoading.value = false;
      resetPlayer();
    }
  }

  /// 静默刷新频道数据（不显示 loading）
  ///
  /// 关键：Dio 返回后必须重新读取 currentChannel，而不是用请求前记录的值。
  /// 因为用户在请求期间可能已经切换了频道，用旧值会覆盖用户的选择，
  /// 导致"播放的是 B，但高亮显示 A"的状态错乱。
  Future<void> _silentRefreshChannels() async {
    final config = currentConfig.value;
    if (config == null) return;

    // 生成本次刷新的令牌
    final token = ++_refreshToken;
    final bool wasPlaying = isPlaying.value;

    try {
      final response = await Dio().get(
        config.url,
        options: Options(
          headers: config.ua != null ? {'User-Agent': config.ua} : null,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      // 令牌校验：如果刷新期间用户操作过（playChannel 会 ++_refreshToken），
      //    或者又触发了新的刷新，本次结果直接丢弃
      if (token != _refreshToken) return;

      final content = response.data is String
          ? response.data as String
          : response.data.toString();
      final parsed = LiveParserService.parse(content);

      if (parsed.isEmpty) {
        // 静默刷新失败，但保留旧数据
        return;
      }

      // 更新频道列表
      channels.assignAll(parsed);
      _updateGroups();

      // 关键：Dio 返回后重新读取当前频道 URL，而不是用请求前记录的值
      final currentUrl = currentChannel.value?.url;
      if (currentUrl == null) return;

      final found = parsed.where((ch) => ch.url == currentUrl).toList();
      if (found.isNotEmpty) {
        // 用新列表里的同 URL 对象替换，保持引用一致
        currentChannel.value = found.first;

        // 如果之前在播放且现在没在播，恢复播放
        if (wasPlaying && !isPlaying.value && !userPaused.value) {
          _player?.play();
        }
      }
      // 如果 found 为空：当前频道不在新列表中。
      //    不要自动切换到第一个！用户可能刚点了别的频道，
      //    或者当前频道确实失效了。静默保留现状比乱切更安全。
    } catch (_) {
      // 静默刷新失败，不处理
    }
  }

  Future<void> _loadChannelsFromRemote(LiveConfig config, {bool showLoading = true}) async {
    if (config.url.isEmpty) {
      errorMessage.value = '直播源地址为空，请检查配置';
      if (showLoading) isLoading.value = false;
      resetPlayer();
      return;
    }

    try {
      final response = await Dio().get(
        config.url,
        options: Options(
          headers: config.ua != null ? {'User-Agent': config.ua} : null,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final content = response.data is String ? response.data as String : response.data.toString();
      final parsed = LiveParserService.parse(content);

      if (parsed.isEmpty) {
        errorMessage.value = '未解析到任何频道，请检查直播源';
        if (showLoading) isLoading.value = false;
        resetPlayer();
        return;
      }

      errorMessage.value = '';
      channels.assignAll(parsed);
      _updateGroups();

      if (channels.isNotEmpty && currentChannel.value == null) {
        _playChannelInternal(channels.first);
      }

      // ===== 追加：异步加载 EPG =====
      // 仅在 EPG 尚未加载（epgMap 为空）时才加载，避免重复下载
      if (epgMap.isEmpty && config.epg != null && config.epg!.isNotEmpty) {
        _loadEpg(config);
      } else if (epgMap.isNotEmpty) {
        // EPG 已缓存，重新调度定时器（切换配置后可能当前节目变了）
        _scheduleEpgBoundaryTimer();
      }

    } catch (e) {
      errorMessage.value = '加载直播源失败: $e';
      resetPlayer();
    } finally {
      if (showLoading) isLoading.value = false;
    }
  }

  void _updateGroups() {
    final groupSet = <String>{};
    for (var ch in channels) {
      groupSet.add(ch.group);
    }
    final groupList = groupSet.toList();
    groups.assignAll(groupList);

    final currentSelected = selectedGroup.value;

    if (groups.isEmpty) {
      selectedGroup.value = '';
      _isFirstLoad = true;
      return;
    }

    if (groups.contains(currentSelected) && currentSelected.isNotEmpty) {
      return;
    }

    selectedGroup.value = groups.first;
    _isFirstLoad = false;
  }

  List<LiveChannel> get currentGroupChannels {
    if (selectedGroup.value.isEmpty) return [];
    return channels.where((ch) => ch.group == selectedGroup.value).toList();
  }

  /// 刷新频道（用户手动触发，或切换配置时调用）
  /// [showLoading] 是否显示 loading，默认 true
  Future<void> refreshChannels({bool showLoading = true}) async {
    // ===== 配置切换或手动刷新时，立即清除播放状态 =====
    if (showLoading) {
      _player?.stop();
      currentChannel.value = null;
      isPlaying.value = false;
      userPaused.value = false;
    }
    await _loadConfigAndChannels(forceLoading: showLoading);
  }

  // ============================================================
  // 频道播放
  // ============================================================

  void playChannel(LiveChannel channel) {
    if (!_isPlayerInitialized) _initPlayer();
    if (_isPlayingChannel) return;
    if (currentChannel.value?.url == channel.url && isPlaying.value) return;

    // 作废进行中的静默刷新，避免它返回后覆盖用户的新选择
    _refreshToken++;

    userPaused.value = false;
    _playChannelInternal(channel);
    showControls();
  }

  Future<void> _playChannelInternal(LiveChannel channel) async {
    if (!_isPlayerInitialized) _initPlayer();
    if (_isPlayingChannel) return;

    // 作废进行中的静默刷新
    _refreshToken++;

    _isPlayingChannel = true;
    currentChannel.value = channel;

    // ===== 切换频道时重新调度 EPG 边界定时器（不重新加载 EPG） =====
    _scheduleEpgBoundaryTimer();

    try {
      await _player!.stop();

      final config = currentConfig.value;
      final httpHeaders = <String, String>{};
      if (config?.ua != null && config!.ua!.isNotEmpty) {
        httpHeaders['User-Agent'] = config.ua!;
      }

      final Map<String, String> extras = {};
      extras.addAll(_buffer);
      extras['video-sync'] = PlayerPref.videoSync;
      extras['hwdec'] = PlayerPref.hardwareDecoding;
      if (Platform.isAndroid) {
        extras['ao'] = PlayerPref.audioOutput;
      }
      final autosync = PlayerPref.autosync;
      if (autosync != '0') {
        extras['autosync'] = autosync;
      }

      await _player!.open(
        Media(
          channel.url,
          httpHeaders: httpHeaders,
          extras: extras,
        ),
        play: false,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      _player!.play();
      userPaused.value = false;

    } catch (e) {
      SmartDialog.showToast('播放失败: $e');
    } finally {
      _isPlayingChannel = false;
    }
  }

  // ============================================================
  // EPG 相关方法
  // ============================================================

  /// 加载 EPG（异步，失败不影响直播）
  /// 只在首次进入 + 切换配置 + 跨天时调用
  Future<void> _loadEpg(LiveConfig config) async {
    if (config.epg == null || config.epg!.isEmpty) {
      epgMap.clear();
      epgError.value = '';
      _epgLoadDate = null;
      return;
    }

    epgLoading.value = true;
    epgError.value = '';

    try {
      final map = await LiveEpgService.load(
        configKey: config.key,
        url: config.epg!,
      );
      epgMap.assignAll(map);
      epgError.value = '';

      // 记录本次加载成功的日期，用于跨天检测
      _epgLoadDate = DateTime.now();

      // EPG 加载完成后，调度边界定时器
      _scheduleEpgBoundaryTimer();
    } catch (e) {
      epgError.value = '节目单加载失败';
    } finally {
      epgLoading.value = false;
    }
  }

  /// 调度节目边界定时器
  ///
  /// 策略：只在"当前节目结束 + 1 秒"时触发一次刷新，
  /// 触发后递归调度下一个节目的边界。
  /// 这样节目切换时立即更新，其他时间零刷新。
  ///
  /// 跨天处理：
  ///   当 currentProgramme == null 时，检查 _epgLoadDate 是否是今天。
  ///   如果不是今天，说明 EPG 数据已过期（跨天了），自动重新加载。
  ///   否则直接 return（比如 EPG 本身就没有当前节目，无需重新加载）。
  ///
  /// 注意：此方法只做内存操作，不下载、不解析 EPG（除非跨天触发 _loadEpg）
  void _scheduleEpgBoundaryTimer() {
    _cancelEpgBoundaryTimer();

    final programme = currentProgramme;
    if (programme == null) {
      // 跨天检测
      // 当前无节目 → 可能是 EPG 过期（跨天），尝试重新加载
      _tryReloadEpgIfCrossDay();
      return;
    }

    final now = DateTime.now();
    final stop = programme.stop;
    if (stop.isBefore(now)) return;

    // 距离节目结束的时长 + 1 秒缓冲
    final delay = stop.difference(now) + const Duration(seconds: 1);

    _epgBoundaryTimer = Timer(delay, () {
      if (epgMap.isNotEmpty) {
        // 触发监听者重算 currentProgramme
        epgMap.refresh();
      }
      // 递归调度下一个节目的边界
      _scheduleEpgBoundaryTimer();
    });
  }

  /// 跨天时重新加载 EPG
  ///
  /// 触发条件（全部满足）：
  ///   1. 当前没有正在播放的节目（currentProgramme == null）
  ///   2. _epgLoadDate 不为 null（说明之前成功加载过 EPG）
  ///   3. _epgLoadDate 的日期 != 今天（说明跨天了）
  ///   4. 当前配置有 EPG 地址
  ///
  /// 满足时调用 _loadEpg 重新加载，加载完成后会重新调度定时器。
  void _tryReloadEpgIfCrossDay() {
    final loaded = _epgLoadDate;
    if (loaded == null) return;

    final now = DateTime.now();
    final isCrossDay = loaded.year != now.year ||
                       loaded.month != now.month ||
                       loaded.day != now.day;
    if (!isCrossDay) return;

    final config = currentConfig.value;
    if (config == null || config.epg == null || config.epg!.isEmpty) return;

    // 防止并发重复加载
    if (epgLoading.value) return;

    _loadEpg(config);
  }

  void _cancelEpgBoundaryTimer() {
    _epgBoundaryTimer?.cancel();
    _epgBoundaryTimer = null;
  }

  // ============================================================
  // 全屏控制
  // ============================================================

  Future<void> enterFullScreen(BuildContext context) async {
    if (isFullScreen.value) return;

    if (PlatformUtils.isDesktop) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setFullScreen(true);
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        await _mediaKitChannel.invokeMethod('Utils.EnterNativeFullscreen');
      } catch (_) {}
    } else {
      try {
        await _mediaKitChannel.invokeMethod('Utils.EnterNativeFullscreen');
      } catch (_) {}
      await landscapeLeftMode();
    }

    _fullScreenOverlay = OverlayEntry(
      builder: (context) => _FullScreenOverlay(
        onExit: () => exitFullScreen(),
      ),
    );
    Overlay.of(context).insert(_fullScreenOverlay!);

    isFullScreen.value = true;
    showControls();
  }

  Future<void> exitFullScreen() async {
    if (!isFullScreen.value) return;

    _fullScreenOverlay?.remove();
    _fullScreenOverlay = null;

    if (PlatformUtils.isDesktop) {
      try {
        await _mediaKitChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      await windowManager.setFullScreen(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    } else {
      try {
        await _mediaKitChannel.invokeMethod('Utils.ExitNativeFullscreen');
      } catch (_) {}
      await portraitUpMode();
    }

    isFullScreen.value = false;
    showControls();
  }

  Future<void> toggleFullScreen(BuildContext context) async {
    if (isFullScreen.value) {
      await exitFullScreen();
    } else {
      await enterFullScreen(context);
    }
  }

  // ============================================================
  // 画面比例切换
  // ============================================================

  void setVideoFit(VideoFitType fit) {
    videoFit.value = fit;
  }

  // ============================================================
  // 频道 Logo
  // ============================================================

  /// 解析指定频道的 Logo URL
  ///
  /// - 未配置 logo 模板 → null
  /// - 模板无占位符 → 原样返回模板
  /// - 模板含 {频道名} / {name} → 替换为归一化 + URL 编码后的频道名
  String? logoUrlFor(LiveChannel channel) {
    final template = currentConfig.value?.logo;
    return ChannelLogoService.resolve(
      template: template,
      channelName: channel.name,
    );
  }

  /// 当前频道的 Logo URL
  String? get currentLogoUrl {
    final ch = currentChannel.value;
    if (ch == null) return null;
    return logoUrlFor(ch);
  }

  // ============================================================
  // 工具
  // ============================================================

  String formatDuration(Duration duration) {
    if (duration.inMilliseconds <= 0) return '00:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// ============================================================
// 全屏 Overlay 组件
// ============================================================

class _FullScreenOverlay extends StatelessWidget {
  final VoidCallback onExit;

  const _FullScreenOverlay({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          onExit();
        }
      },
      child: Material(
        color: Colors.black,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const LivePlayerView(isFullScreen: true),
            ],
          ),
        ),
      ),
    );
  }
}
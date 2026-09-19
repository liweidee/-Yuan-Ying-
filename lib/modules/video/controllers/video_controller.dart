import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import 'package:yuanying/modules/video/controllers/intro_controller.dart';
import 'package:yuanying/modules/video/widgets/episode_panel_dialog.dart';
import 'package:yuanying/modules/video/widgets/parser_menu.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/models/data_source.dart';
import 'package:yuanying/plugin/pl_player/models/data_status.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/services/resource_sniffer.dart';
import 'package:yuanying/services/parser_service.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/t4_api_service.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/modules/audio/controllers/audio_controller.dart';
import 'package:yuanying/modules/audio/views/audio_page.dart';
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/modules/danmaku/services/danmaku_parser.dart';
import 'package:yuanying/plugin/pl_player/models/play_status.dart';
import 'package:yuanying/utils/toast_utils.dart';
import 'package:yuanying/models_new/video/video_play_info/subtitle.dart';
import 'package:media_kit/media_kit.dart' hide Subtitle;
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/drpy2_api_service.dart';
import 'package:yuanying/modules/video/widgets/introduction/intro_detail_panel.dart';
import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'playback_event_listener.dart';

import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/services/external_player_service.dart';
import 'package:yuanying/plugin/pl_player/models/external_player_type.dart';
import 'package:yuanying/modules/setting/views/play_setting_page.dart';
import 'package:yuanying/services/ad_block_proxy_service.dart';

class DetailController extends GetxController with GetTickerProviderStateMixin {
  // ===== tag 用于隔离控制器 =====
  final String? _tag;

  // ===== 构造函数接收 tag =====
  DetailController({String? tag}) : _tag = tag;

  // ===== IntroController 使用 tag 创建 =====
  late final IntroController introController;

  late final ISpiderService _apiService;
  final SourceManager _sourceManager = Get.find<SourceManager>();

  late final PlPlayerController playerController;
  // 引擎切换通知：用于让详情页 Obx 在切换内核后重新收集 isFullScreen 依赖
  final engineSwitchNotifier = 0.obs;

  final RxString currentPlayUrl = ''.obs;
  final RxList<PlayQuality> currentQualities = <PlayQuality>[].obs;
  final RxBool isPlaying = false.obs;
  bool _isDirectPushMode = false;

  // 外部播放事件监听器（仅 Jellyfin 等需要主动上报的服务器会注入）
  //   未注入时为 null，所有相关调用都会短路返回，行为与原版一致。
  PlaybackEventListener? _playbackEventListener;

  // push 模式下当前播放的标题（用于外部上报反查 itemId）
  //   因为 push 模式下 introController.currentPlayEpisode 可能是错的，
  //   只有 directTitle 才代表用户实际点击的那一集
  String? _currentDirectTitle;

  // 外部上报的进度 Timer（仅在注入了 listener 时启动）
  Timer? _externalProgressTimer;

  /// 推送模式下的请求头（如 WebDAV Basic Auth、自建服务器 token）
  /// 仅在 isPush 模式下有效；非推送模式保持 null，不影响原逻辑。
  Map<String, String>? _initHeaders;

  // 播放完成监听器（保存函数引用，用于移除）
  void Function(PlayerStatus)? _playCompletedListener;
  // 防止重复处理完成事件的标志
  bool _isHandlingCompletion = false;

  final RxBool isLoadingDetail = true.obs;
  final RxString detailError = ''.obs;

  /// 当前详情页使用的站点配置（独立或全局）
  Map<String, dynamic>? _currentSiteConfig;

  // ===== 轨道数据（代理播放器） =====
  List<AudioTrack> get audioTracks => playerController.availableAudioTracks;
  List<VideoTrack> get videoTracks => playerController.availableVideoTracks;
  List<SubtitleTrack> get subtitleTracks => playerController.availableSubtitleTracks;

  int get currentAudioIndex {
    final current = playerController.currentAudioTrack.value;
    if (current == null) return -1;
    // 检查是否为 AudioTrack.auto() 或 AudioTrack.no()
    if (current.id == 'auto') return -2;
    if (current.id == 'no') return -3;
    return playerController.availableAudioTracks.indexOf(current);
  }

  int get currentVideoIndex {
    final current = playerController.currentVideoTrack.value;
    if (current == null) return -1;
    if (current.id == 'auto') return -2;
    if (current.id == 'no') return -3;
    return playerController.availableVideoTracks.indexOf(current);
  }

  int get currentSubtitleTrackIndex {
    final current = playerController.currentSubtitleTrack.value;
    if (current == null) return -1;
    if (current.id == 'auto') return -2;
    if (current.id == 'no') return -3;
    return playerController.availableSubtitleTracks.indexOf(current);
  }

  String get currentAudioName {
    final current = playerController.currentAudioTrack.value;
    return current?.title ?? '默认';
  }

  String get currentVideoName {
    final current = playerController.currentVideoTrack.value;
    return current?.title ?? '默认';
  }

  String get currentSubtitleName {
    final current = playerController.currentSubtitleTrack.value;
    return current?.title ?? '关闭';
  }

  // ===== 推送相关 =====
  final RxBool showPushButton = false.obs;
  final RxString pushVodId = ''.obs;

  // ===== 解析相关 =====
  final RxList<ParserSource> parserSources = <ParserSource>[].obs;
  final Rxn<ParserSource> currentParser = Rxn<ParserSource>();
  final RxBool showParserButton = false.obs;

  /// 自动播放状态（用于控制封面显示）
  final RxBool autoPlay = false.obs;

  /// 保存离开页面时的播放进度
  Duration? savedPosition;

  /// 标记是否正在打开图片查看器
  bool isImageViewerOpen = false;

  /// 当前播放的请求头
  final RxMap<String, String> currentHeaders = <String, String>{}.obs;

  /// 字幕列表
  final RxList<Subtitle> subtitles = <Subtitle>[].obs;

  /// VTT 字幕缓存（key: 索引, value: {是否内联数据, 数据内容/路径}）
  final Map<int, ({bool isData, String id})> vttSubtitles = {};

  /// 临时字幕文件列表（用于 FVP 引擎的内存字幕缓存）
  final List<String> _tempSubtitleFiles = [];

  /// 当前选中的字幕索引（-1 表示关闭）
  late final RxInt vttSubtitlesIndex = (-1).obs;

  // ===== 临时站点（用于推送跳转等场景） =====
  Map<String, dynamic>? _tempSite;

  // 跳过片头片尾（仅当次有效，详情页级别）
  final RxInt skipStartDuration = 0.obs; // 片头跳过秒数
  final RxInt skipEndDuration = 0.obs;   // 片尾跳过秒数

  // ===== 设定字幕轨道（外部加载） =====
  Future<void> setSubtitle(int index) async {
    if (index <= 0) {
      await playerController.setSubtitleTrack(SubtitleTrack.no());
      vttSubtitlesIndex.value = 0;
      playerController.currentSubtitleTrack.value = null;
      return;
    }

    if (index > subtitles.length) return;

    // ===== 1. 优先检查缓存 =====
    final entry = vttSubtitles[index - 1];
    if (entry != null) {
      final subtitle = subtitles[index - 1];
      final currentEngine = PlayerPref.playerEngine;
      SubtitleTrack track;

      if (currentEngine == PlayerEngineType.fvp) {
        String filePath;
        if (entry.isData) {
          // 内存数据 → 写入临时文件
          filePath = await _writeSubtitleToTempFile(entry.id, 'vtt');
        } else {
          // 已有文件路径（已是 file:// URI）
          filePath = entry.id;
        }
        // 标记为 URI，FVP 会识别并加载
        track = SubtitleTrack(filePath, subtitle.lanDoc, subtitle.lan, uri: true);
      } else {
        // media_kit 引擎
        if (entry.isData) {
          track = SubtitleTrack.data(entry.id, title: subtitle.lanDoc, language: subtitle.lan);
        } else {
          track = SubtitleTrack(entry.id, subtitle.lanDoc, subtitle.lan, uri: true);
        }
      }

      await playerController.setSubtitleTrack(track);
      vttSubtitlesIndex.value = index;
      playerController.currentSubtitleTrack.value = track;
      return;
    }

    // ===== 2. 无缓存 → 检查 subtitleUrl（网络字幕） =====
    final subtitle = subtitles[index - 1];
    if (subtitle.subtitleUrl == null) {
      SmartDialog.showToast('字幕 URL 无效');
      return;
    }

    try {
      final response = await Dio().get(
        subtitle.subtitleUrl!,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200) {
        final content = utf8.decode(response.data as List<int>);
        final currentEngine = PlayerPref.playerEngine;
        SubtitleTrack track;

        if (currentEngine == PlayerEngineType.fvp) {
          final filePath = await _writeSubtitleToTempFile(content, 'vtt');
          track = SubtitleTrack(filePath, subtitle.lanDoc, subtitle.lan, uri: true);
        } else {
          track = SubtitleTrack.data(content, title: subtitle.lanDoc, language: subtitle.lan);
        }

        // 缓存到 vttSubtitles（便于下次直接使用）
        vttSubtitles[index - 1] = (isData: true, id: content);
        await playerController.setSubtitleTrack(track);
        vttSubtitlesIndex.value = index;
        playerController.currentSubtitleTrack.value = track;
      } else {
        SmartDialog.showToast('加载字幕失败');
      }
    } catch (e) {
      SmartDialog.showToast('加载字幕异常: $e');
    }
  }

  /// 将字幕内容写入临时文件，返回文件路径
  Future<String> _writeSubtitleToTempFile(String content, String extension) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'subtitle_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.$extension';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, encoding: utf8);
    _tempSubtitleFiles.add(file.path);
    return file.path;
  }

  /// 清理临时文件（可在 onClose 或 dispose 中添加清理逻辑）
  void _cleanTempSubtitleFiles() {
    for (final path in _tempSubtitleFiles) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    _tempSubtitleFiles.clear();
  }

  /// 切换字幕轨道（内置轨道）
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    // 先关闭当前字幕（无论内置还是外部）
    await playerController.setSubtitleTrack(SubtitleTrack.no());
    // 再设置新轨道
    await playerController.setSubtitleTrack(track);
    // 同步状态：清除外部字幕选择
    vttSubtitlesIndex.value = -1;
  }

  /// 关闭字幕（统一入口）
  Future<void> disableSubtitleTrack() async {
    await playerController.setSubtitleTrack(SubtitleTrack.no());
    vttSubtitlesIndex.value = 0;
    playerController.currentSubtitleTrack.value = null;
  }

  // ===== 音轨切换 =====
  Future<void> setAudioTrack(AudioTrack track) async {
    await playerController.setAudioTrack(track);
  }

  // ===== 视轨切换 =====
  Future<void> setVideoTrack(VideoTrack track) async {
    await playerController.setVideoTrack(track);
  }

  // ===== 弹窗位置计算 =====
  GlobalKey? _tabBarKey;

  late final String vodId;
  late final String pwd;

  final DanmakuParser _danmakuParser = DanmakuParser();
  bool _danmakuLoaded = false;
  ValueChanged<PlayerStatus>? _danmakuListener;

  // 进度更新定时器
  Timer? _progressTimer;

  Episode? _currentEpisode;
  int _currentSourceIndex = 0;
  int _currentEpisodeIndex = 0;

  /// 统一的 tag 生成工厂方法
  static String generateTag({String? prefix}) {
    return '${prefix ?? 'detail'}_${DateTime.now().millisecondsSinceEpoch}';
  }

  final RxBool isManualParser = false.obs;

  late final TabController tabCtr;

  @override
  void onInit() {
    super.onInit();

    // ---- IntroController 初始化 ----
    if (_tag != null && _tag!.isNotEmpty) {
      introController = Get.isRegistered<IntroController>(tag: _tag)
          ? Get.find<IntroController>(tag: _tag)
          : Get.put(IntroController(), tag: _tag);
    } else {
      introController = Get.isRegistered<IntroController>()
          ? Get.find<IntroController>()
          : Get.put(IntroController());
    }

    playerController = PlPlayerController.getInstance();

    // 从全局设置读取播放顺序，确保与设置页一致
    playerController.setPlayRepeat(PlayRepeat.values[PlayerPref.playRepeat]);

    final args = Get.arguments;
    if (args is Map) {
      // ---- 推送模式（直接播放，提前返回） ----
      if (args['isPush'] == true) {
        if (args['directUrl'] != null && args['directUrl'].toString().isNotEmpty) {
          _initPushMode(args);
          return;
        }
      }

      // ---- 初始化 _apiService ----
      final independentSite = args['site'] as Map<String, dynamic>?;
      if (independentSite != null) {
        _apiService = Get.find<SourceManager>().createIndependentService(independentSite);
        _currentSiteConfig = independentSite;  // 新增
        // 传递来源名称
        final siteName = independentSite['name']?.toString() ?? '未知来源';
        introController.setSourceName(siteName);
      } else {
        // 默认使用全局当前源
        _apiService = Get.find<SourceManager>().currentApiService;
        _currentSiteConfig = Get.find<SourceManager>().currentSite.value;  // 新增
        // 传递当前源名称
        final currentSite = Get.find<SourceManager>().currentSite.value;
        if (currentSite != null) {
          introController.setSourceName(currentSite['name']?.toString() ?? '未知来源');
        }
      }

      // ---- 保存 vodId / pwd ----
      vodId = args['vodId'] ?? args['id'] ?? args['videoId'] ?? '';
      pwd = args['pwd'] ?? 'tinydust';
      introController.setOriginalVodId(vodId);
      final currentSite = Get.find<SourceManager>().currentSite.value;
      if (currentSite != null) {
        final apiUrl = currentSite['api']?.toString() ?? '';
        introController.setCurrentApiUrl(apiUrl);
      }
    } else {
      detailError.value = '参数错误';
      isLoadingDetail.value = false;
      return;
    }

    _loadParsers();

    if (vodId.isEmpty) {
      detailError.value = '视频ID缺失';
      isLoadingDetail.value = false;
      return;
    }

    tabCtr = TabController(
      length: 3,
      vsync: this,
      initialIndex: 0,
    );

    loadVideoDetail();
  }

  /// 获取当前生效的站点（优先使用临时站点）
  Map<String, dynamic>? get effectiveSite => _sourceManager.currentSite.value;

  /// 获取当前生效的站点 API 地址
  String? get effectiveApiBase => effectiveSite?['api']?.toString();

  void setTabBarKey(GlobalKey key) {
    _tabBarKey = key;
  }

  void _loadParsers() {
    final parseList = _sourceManager.parses;
    if (parseList.isNotEmpty) {
      final sources = parseList
          .map((e) => ParserSource.fromJson(e))
          .where((e) => e.url.isNotEmpty)
          .toList();
      parserSources.value = sources;
      // 不再自动设置 currentParser
    }
  }

  /// 推送模式初始化（只处理直链/解析，接口模式走 loadVideoDetail）
  void _initPushMode(Map args) {
    // 调用方显式传入 isDirectPushMode，或提供了完整的 VideoDetail
    _isDirectPushMode = args['isDirectPushMode'] == true || args['videoDetail'] is VideoDetail;

    // 解析并保存请求头（WebDAV Basic Auth 等）
    final rawHeaders = args['headers'];
    if (rawHeaders is Map && rawHeaders.isNotEmpty) {
      _initHeaders = <String, String>{};
      rawHeaders.forEach((k, v) {
        _initHeaders![k.toString()] = v.toString();
      });
    } else {
      _initHeaders = null;
    }

    // 只处理直链/解析模式
    if (args['directUrl'] == null || args['directUrl'].toString().isEmpty) {
      detailError.value = '推送参数无效';
      isLoadingDetail.value = false;
      return;
    }

    final String url = args['directUrl'].toString();
    final String title = args['directTitle'] ?? '直链播放';
    final bool isParserMode = args['isParserMode'] == true;

    // ============================================================
    // 核心增强：支持传入完整 VideoDetail（Emby 等外部来源）
    // 设计原则：如果传入则使用，否则走原逻辑，完全向后兼容
    // ============================================================
    VideoDetail detail;
    if (args['videoDetail'] is VideoDetail) {
      // 直接使用传入的完整详情数据
      detail = args['videoDetail'] as VideoDetail;

      // 设置来源名称
      if (args['sourceName'] != null) {
        introController.setSourceName(args['sourceName'].toString());
      }

      // 安全兜底：如果外部数据没有 playSources，补充一个默认源
      if (detail.playSources.isEmpty) {
        detail = VideoDetail(
          vodId: detail.vodId,
          vodName: detail.vodName,
          vodPic: detail.vodPic,
          vodContent: detail.vodContent,
          vodYear: detail.vodYear,
          vodActor: detail.vodActor,
          vodDirector: detail.vodDirector,
          // vodTag 已移除（VideoDetail 没有此字段）
          vodRemarks: detail.vodRemarks,
          typeName: detail.typeName,
          playSources: [
            PlaySource(
              name: isParserMode ? '解析' : '推送',
              episodes: [Episode(name: title, url: url)],
            ),
          ],
        );
      }
    } else {
      // ===== 原逻辑：构造简化版 VideoDetail（完全不变） =====
      detail = VideoDetail(
        vodId: 'direct_${Uri.encodeComponent(url)}',
        vodName: title,
        vodPic: args['vodPic'] ?? '',
        vodContent: args['vodContent'] ?? (isParserMode ? '来自解析播放' : '来自推送播放'),
        vodYear: args['vodYear'] ?? '',
        vodActor: args['vodActor'] ?? '',
        vodDirector: args['vodDirector'] ?? '',
        // vodTag 已移除（原逻辑中已无此字段）
        vodRemarks: args['vodRemarks'] ?? '',
        typeName: args['typeName'] ?? '',
        playSources: [
          PlaySource(
            name: isParserMode ? '解析' : '推送',
            episodes: [Episode(name: title, url: url)],
          ),
        ],
      );
    }

    introController.setVideoDetail(detail);

    // 解析外部播放事件监听器（可选，未注入时保持 null）
    final listener = args['playbackEventListener'];
    if (listener is PlaybackEventListener) {
      _playbackEventListener = listener;
    }
    // 保存 directTitle 供上报使用（用于反查 Jellyfin 的 itemId）
    _currentDirectTitle = title;

    if (isParserMode) {
      if (args['parserSources'] != null) {
        final sources = (args['parserSources'] as List)
            .map((e) => ParserSource.fromJson(e as Map<String, dynamic>))
            .toList();
        parserSources.value = sources;
      }
      if (args['currentParser'] != null) {
        currentParser.value = ParserSource.fromJson(
          args['currentParser'] as Map<String, dynamic>,
        );
      }
      showParserButton.value = true;
    }

    // 推送直链模式也需要 TabBar，所以必须初始化 tabCtr
    tabCtr = TabController(
      length: 3,
      vsync: this,
      initialIndex: 0,
    );

    // ============================================================
    // 推送模式下定位当前集/曲目，同步播放列表状态
    // - 兼容性保证：只在匹配成功时更新状态
    // - 匹配失败 / playSources 为空 / 单集场景 保持原行为（从第 0 集开始）
    // - 不抛异常、不阻塞播放
    // ============================================================
    _locateCurrentEpisodeInPushMode(detail, url, title);

    _playDirect(url);
  }

  /// 在推送模式下定位当前集/曲目，同步到 [IntroController] 与本类状态
  ///
  /// 作用：
  /// - 让播放列表 UI 高亮正确的集/曲目
  /// - 让"上一集 / 下一集 / 自动连播"从正确的索引开始计算
  /// - 让 `_startPlay` 里的 `vodId: _currentEpisode?.name` 显示正确标题
  ///
  /// 匹配策略（按优先级）：
  /// 1. URL 精确匹配（最优先，URL 在播放列表内唯一）
  /// 2. 标题匹配（URL 未命中时的兜底；同标题时命中第一个）
  ///
  /// 匹配失败时**不做任何状态修改**，保持原有从第 0 集开始的行为。
  void _locateCurrentEpisodeInPushMode(
    VideoDetail detail,
    String url,
    String title,
  ) {
    if (detail.playSources.isEmpty) return;

    int foundSourceIdx = -1;
    int foundEpisodeIdx = -1;

    // ---- 策略 1：URL 精确匹配 ----
    for (int si = 0; si < detail.playSources.length; si++) {
      final source = detail.playSources[si];
      for (int ei = 0; ei < source.episodes.length; ei++) {
        if (source.episodes[ei].url == url) {
          foundSourceIdx = si;
          foundEpisodeIdx = ei;
          break;
        }
      }
      if (foundEpisodeIdx >= 0) break;
    }

    // ---- 策略 2：标题匹配（兜底） ----
    if (foundEpisodeIdx < 0 && title.isNotEmpty) {
      for (int si = 0; si < detail.playSources.length; si++) {
        final source = detail.playSources[si];
        for (int ei = 0; ei < source.episodes.length; ei++) {
          if (source.episodes[ei].name == title) {
            foundSourceIdx = si;
            foundEpisodeIdx = ei;
            break;
          }
        }
        if (foundEpisodeIdx >= 0) break;
      }
    }

    // ---- 未匹配到：保持原行为，不修改任何状态 ----
    if (foundEpisodeIdx < 0) {
      debugPrint(
          '[PushMode] 未匹配到 url=$url / title=$title，使用默认从第 0 集开始');
      return;
    }

    debugPrint(
        '[PushMode] 定位成功: source=$foundSourceIdx, episode=$foundEpisodeIdx');

    // ---- 同步到 IntroController（驱动 UI 高亮 / 上下集计算） ----
    introController.switchPlaySource(foundSourceIdx);
    introController.switchEpisode(foundEpisodeIdx);

    // ---- 同步到 DetailController 私有字段（供 _startPlay / 完成处理使用） ----
    _currentSourceIndex = foundSourceIdx;
    _currentEpisodeIndex = foundEpisodeIdx;
    _currentEpisode =
        detail.playSources[foundSourceIdx].episodes[foundEpisodeIdx];
  }

  Future<void> loadVideoDetail() async {
    // _apiService = Get.find<SourceManager>().currentApiService;
    try {
      final detail = await _apiService.getDetail(vodId: vodId, pwd: pwd);

      if (detail != null) {
        introController.setVideoDetail(detail);
        if (detail.playSources.isNotEmpty) {
          final firstSource = detail.playSources.first;
          if (firstSource.episodes.isNotEmpty) {
            isLoadingDetail.value = false;

            // ===== 检测第一集是否为推送链接 =====
            final firstEpisode = firstSource.episodes.first;
            if (firstEpisode.url.startsWith('push://')) {
              // 推送链接：显示按钮和 toast，不自动播放
              checkAndHandlePushEpisode(firstEpisode);
              return;
            }

            // 非推送链接：根据自动播放开关决定是否自动播放
            final bool autoPlay = PlayerPref.autoPlayEnable;
            if (autoPlay) {
              _showPlayLoading();
            }
            await _playEpisode(
              firstEpisode,
              sourceIndex: 0,
              episodeIndex: 0,
              autoPlay: autoPlay,
            );
            // 如果关闭自动播放，确保加载状态结束
            if (!autoPlay) {
              isLoadingDetail.value = false;
            }
          } else {
            isLoadingDetail.value = false;
          }
        } else {
          isLoadingDetail.value = false;
        }
      } else {
        detailError.value = '获取详情失败，请检查网络';
        isLoadingDetail.value = false;
      }
    } catch (e) {
      detailError.value = '请求异常: ${e.toString()}';
      isLoadingDetail.value = false;
    }
  }

  void _showPlayLoading() {
    // 先关闭可能残留的相同 tag 的加载对话框
    SmartDialog.dismiss(tag: 'play_loading', force: true);
    
    SmartDialog.show(
      tag: 'play_loading', // 唯一标识
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
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '正在获取播放信息...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
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
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '正在解析中...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showParserToast(String parserName) {
    ToastUtils.show('来自解析 $parserName');
  }

  /// 检测是否为推送链接
  void checkAndHandlePushEpisode(Episode episode) {
    final url = episode.url;
    if (url.startsWith('push://')) {
       // 先暂停当前播放
        if (playerController.playerStatus.value.isPlaying) {
          playerController.pause();
        }
    
      String rawVodId = url.substring(7);
      try {
        final decoded = Uri.decodeComponent(rawVodId);
        final encoded = Uri.encodeComponent(decoded);
        pushVodId.value = encoded;
      } catch (_) {
        pushVodId.value = Uri.encodeComponent(rawVodId);
      }

      if (PlayerPref.pushMode == 1) {
        // 自动模式：直接调用 pushToDetail，不显示按钮，不显示 toast
        // 使用 WidgetsBinding 确保 pushVodId 已稳定更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          pushToDetail(showToast: false);
        });
        return;
      }

      // 手动模式（原有逻辑保持不变）
      showPushButton.value = true;
      SmartDialog.showToast('检测到推送链接，点击推送按钮进行播放');
    } else {
      showPushButton.value = false;
      pushVodId.value = '';
    }
  }

  /// 执行推送跳转
  Future<void> pushToDetail({bool showToast = true}) async {
    if (pushVodId.value.isEmpty) {
      if (showToast) SmartDialog.showToast('推送链接无效');
      return;
    }

    final pushAgentSite = _sourceManager.pushAgentSite;
    if (pushAgentSite == null) {
      if (showToast) SmartDialog.showToast('需要先配置 push_agent 线路');
      return;
    }

    final api = pushAgentSite['api']?.toString() ?? '';
    if (api.isEmpty) {
      if (showToast) SmartDialog.showToast('push_agent 线路配置无效');
      return;
    }

    try {
      final uri = Uri.parse(api);
      final pwd = uri.queryParameters['pwd'] ?? 'tinydust';

      if (playerController.playerStatus.value.isPlaying) {
        await playerController.pause();
      }

      final tag = 'push_${DateTime.now().millisecondsSinceEpoch}';

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'vodId': pushVodId.value,
          'site': pushAgentSite,
          'pwd': pwd,
          '_controllerTag': tag,
        },
        preventDuplicates: false,
      );
      if (showToast) SmartDialog.showToast('正在跳转到推送详情...');
    } catch (e) {
      if (showToast) SmartDialog.showToast('跳转失败: $e');
    }
  }

  /// 播放核心逻辑
  Future<void> _playEpisode(
    Episode episode, {
    required int sourceIndex,
    required int episodeIndex,
    bool autoPlay = true,
    Duration? seekTo,
  }) async {
    _danmakuLoaded = false;
    _currentEpisode = episode;
    _currentSourceIndex = sourceIndex;
    _currentEpisodeIndex = episodeIndex;

    isPlaying.value = false;
    showParserButton.value = false;

    // 直链推送模式：直接用 episode.url 播放，不走 _apiService
    // 适用于 Emby / AList 等外部来源，其 Episode.url 已是完整 HTTP 直链
    if (_isDirectPushMode) {
      final directPlayUrl = PlayUrl(
        parse: 0,
        qualities: [PlayQuality(label: '直链', url: episode.url)],
        headers: _initHeaders, // ← 新增：透传 headers（null 时与原逻辑一致）
      );
      await _startPlay(directPlayUrl, autoPlay, seekTo: seekTo);
      return;
    }

    try {
      final source = introController.getSource(sourceIndex);
      if (source == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('获取播放地址失败');
        return;
      }

      final playUrl = await _apiService.getPlayUrl(
        playParams: episode.url,
        flag: source.name,
        pwd: pwd,
      );

      if (playUrl == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('获取播放地址失败');
        return;
      }

      if (playUrl.needParser) {
        showParserButton.value = true;

        // 关闭残留弹窗
        SmartDialog.dismiss(force: true);

        // 显示解析弹窗
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
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isManualParser.value && currentParser.value != null
                      ? '正在使用 ${currentParser.value!.name} 解析...'
                      : '解析播放中...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );

        final result = await _parseWithAllParsers(
          playUrl,
          preferredParser: isManualParser.value ? currentParser.value : null,
        );

        SmartDialog.dismiss(force: true);

        if (result != null) {
          await _startPlay(result, autoPlay, seekTo: seekTo);
        } else {
          if (isManualParser.value && currentParser.value != null) {
            SmartDialog.showToast('${currentParser.value!.name} 解析失败');
          } else {
            SmartDialog.showToast('所有解析源均失败，请切换线路');
          }
        }
        return;
      }

      if (playUrl.isDirect) {
        SmartDialog.dismiss();
        await _startPlay(playUrl, autoPlay, seekTo: seekTo);
        return;
      }

      if (playUrl.needSniff) {
        SmartDialog.dismiss();

        final site = effectiveSite;
        String? sniffUrl = playUrl.defaultUrl;

        if (sniffUrl != null && sniffUrl.isNotEmpty) {
          if (!sniffUrl.startsWith('http://') && !sniffUrl.startsWith('https://')) {
            final apiBase = site?['api']?.toString() ?? '';
            if (apiBase.isNotEmpty) {
              final uri = Uri.parse(apiBase);
              final baseWithoutQuery = uri.replace(query: '', fragment: '').toString();
              final baseUrl = baseWithoutQuery.endsWith('/') ? baseWithoutQuery : '$baseWithoutQuery/';
              final relativePath = sniffUrl.startsWith('/') ? sniffUrl.substring(1) : sniffUrl;
              sniffUrl = baseUrl + relativePath;
            } else {
              SmartDialog.showToast('无法获取播放地址');
              return;
            }
          }
        }

        if (sniffUrl == null || sniffUrl.isEmpty) {
          SmartDialog.showToast('嗅探URL无效');
          return;
        }

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

        final sniffedUrl = await ResourceSniffer.sniff(
          url: sniffUrl,
          headers: playUrl.headers,
          script: playUrl.script,
          useWebView: true,
        );

        SmartDialog.dismiss();

        if (sniffedUrl != null) {
          final sniffedPlayUrl = PlayUrl(
            parse: 0,
            qualities: [PlayQuality(label: '嗅探', url: sniffedUrl)],
            headers: playUrl.headers,
          );
          await _startPlay(sniffedPlayUrl, autoPlay, seekTo: seekTo);
        } else {
          SmartDialog.showToast('嗅探失败，请尝试其他方式');
        }
        return;
      }

      SmartDialog.dismiss();
      SmartDialog.showToast('未知的播放类型');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('获取播放地址失败');
    }
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

  Future<void> _startPlay(
    PlayUrl playUrl,
    bool autoPlay, {
    Duration? seekTo,
  }) async {
    _isHandlingCompletion = false;

    // 确保所有残留弹窗被关闭
    SmartDialog.dismiss(force: true);

    this.autoPlay.value = autoPlay;

    final defaultUrl = playUrl.defaultUrl;
    if (defaultUrl == null) {
      SmartDialog.showToast('获取播放地址失败');
      return;
    }

    // ===== 根据策略处理请求头 =====
    Map<String, String>? headers = playUrl.headers != null
        ? Map<String, String>.from(playUrl.headers!)
        : <String, String>{};

    final strategy = PlayerPref.requestHeaderStrategy;

    switch (strategy) {
      case 0: // 智能模式
        // 只有服务器没有返回 headers 时，才自动判断添加 UA
        if (playUrl.headers == null || playUrl.headers!.isEmpty) {
          final url = defaultUrl;
          if (url != null && url.isNotEmpty) {
            final domain = _extractDomain(url);
            if (_isCloudStorage(domain)) {
              headers['User-Agent'] = BrowserUa.mob;
            } else {
              headers['User-Agent'] = BrowserUa.pc;
            }
          } else {
            headers['User-Agent'] = BrowserUa.pc;
          }
        }
        // 如果服务器已返回 headers，直接使用，不做任何处理
        break;

      case 1: // 完整模式：强制使用 PC UA
        headers['User-Agent'] = BrowserUa.pc;
        break;

      case 2: // 最小模式：只保留 Accept 头，移除所有其他字段
        final acceptValue = headers['Accept'] ?? '*/*';
        headers.clear();
        headers['Accept'] = acceptValue;
        break;
    }

    // currentPlayUrl.value = defaultUrl;
    // currentQualities.value = playUrl.qualities;
    // currentHeaders.value = headers;

    // final dataSource = NetworkSource(
    //   videoSource: defaultUrl,
    //   audioSource: null,
    //   headers: headers,
    // );

    // UI / 投屏 / 第三方播放器用原始 URL
    currentPlayUrl.value = defaultUrl;
    currentQualities.value = playUrl.qualities;
    currentHeaders.value = headers;

    // 只有播放器数据源走代理（M3U8 + 开关开启时）
    final proxyUrl = _wrapUrlIfNeeded(defaultUrl, headers: headers);

    final dataSource = NetworkSource(
      videoSource: proxyUrl,
      audioSource: null,
      headers: headers,
    );

    final effectiveSeek = seekTo ?? Duration.zero;
    await playerController.setDataSource(
      dataSource,
      autoplay: autoPlay,
      seekTo: effectiveSeek,
      vodId: _currentEpisode?.name ?? '',
      autoFullScreenFlag: PlayerPref.autoEnterFullScreen,
    );

    // 应用片头跳过
    await playerController.applySkipStart();

    if (autoPlay) {
      await playerController.play();
      isPlaying.value = true;

      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!isPlaying.value) {
          await playerController.play();
          isPlaying.value = true;
        }
      });
    }

    // 清空旧弹幕数据和状态
    if (Get.isRegistered<DanmakuController>()) {
      Get.find<DanmakuController>().clear();
    }
    // 重置弹幕加载标志，允许加载新弹幕
    _danmakuLoaded = false;

    final danmakuUrl = playUrl.danmaku;
    if (danmakuUrl != null && danmakuUrl.isNotEmpty) {
      // 播放接口自带弹幕，直接加载，不显示任何 Toast
      _loadDanmaku(danmakuUrl, playUrl.headers);
    } else {
      // 播放接口无弹幕，尝试自定义 API，并显示匹配结果 Toast
      _loadDanmakuOnPlay(null, playUrl.headers);
    }

    _addToHistory();

    // ---- 播放完成监听（自动切换） ----
    if (_playCompletedListener != null) {
      playerController.removeStatusLister(_playCompletedListener!);
    }
    _playCompletedListener = (status) {
      if (status == PlayerStatus.completed && !_isHandlingCompletion) {
        _handlePlayCompleted();
      }
    };
    playerController.addStatusLister(_playCompletedListener!);
  }

  /// 播放完成处理（根据播放顺序自动切换）
  Future<void> _handlePlayCompleted() async {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;
    try {
      final repeat = playerController.playRepeat;  // 不是 Rx，直接取值
      switch (repeat) {
        case PlayRepeat.singleCycle:
          // 单集循环：从头开始重播
          await playerController.seekTo(Duration.zero);
          await playerController.play();
          break;
        case PlayRepeat.listOrder:
          // 顺序播放：尝试下一集，若无则暂停并提示
          final success = await playNext();
          if (!success) {
            await playerController.pause();
            SmartDialog.showToast('已经是最后一集');
          }
          break;
        case PlayRepeat.listCycle:
          // 列表循环：尝试下一集，若无则回到第一集
          final success = await playNext();
          if (!success) {
            final episodes = introController.displayEpisodes;
            if (episodes.isNotEmpty) {
              switchEpisode(0);
            } else {
              await playerController.pause();
            }
          }
          break;
        case PlayRepeat.pause:
          // 播完暂停：不进行任何自动切换，仅暂停（但已经是完成状态，暂停即可）
          await playerController.pause();
          SmartDialog.showToast('播放已结束');
          break;
        default:
          break;
      }
    } finally {
      _isHandlingCompletion = false;
    }
  }

  /// 随机播放一集（排除当前集）
  Future<void> _playRandomEpisode() async {
    final episodes = introController.displayEpisodes;
    if (episodes.isEmpty) return;

    final currentIndex = introController.currentEpisodeIndex.value;
    if (episodes.length == 1) {
      await reloadCurrentEpisode(seekTo: Duration.zero);
      return;
    }

    int randomIndex;
    do {
      randomIndex = Random().nextInt(episodes.length);
    } while (randomIndex == currentIndex);

    switchEpisode(randomIndex);
  }

  // ===== UA 智能判断辅助方法 =====
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  /// 从 headers 里找 Referer（大小写不敏感）
  String? _findReferer(Map<String, String> headers) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'referer') return e.value;
    }
    return null;
  }

  /// 包装 URL：只有 M3U8 且开关开启时才走代理
  String _wrapUrlIfNeeded(String url, {Map<String, String>? headers}) {
    return AdBlockProxyService.instance.wrapIfNeeded(
      url,
      referer: headers != null ? _findReferer(headers) : null,
    );
  }

  bool _isCloudStorage(String domain) {
    const cloudDomains = [
      'pikpak', 'pan.quark', 'aliyundrive', 'yunpan', 'xunlei',
      'weiyun', 'baidu', '115.com', '123pan'
    ];
    return cloudDomains.any((d) => domain.contains(d));
  }

  // ===== 添加历史记录 =====
  void _addToHistory() {
    try {
      final detail = introController.videoDetail.value;
      if (detail == null) return;

      final episode = _currentEpisode;
      if (episode == null) return;

      // 使用 _currentSiteConfig 而不是全局 currentSite
      final site = _currentSiteConfig;
      final sourceName = site?['name']?.toString() ?? (detail.typeName ?? '');
      final currentApiUrl = site?['api']?.toString() ?? '';
      final siteKey = site?['key']?.toString() ?? '';
      final detailType = SourceManager.getDetailTypeFromSite(site);

      if (currentApiUrl.isEmpty) {
        print('添加历史记录失败: api_url 为空');
        return;
      }

      // 读取现有历史数据
      final existingHistory = GStorage.getHistory();

      // 查找是否存在相同 vod_id 且相同 api_url 的记录
      final existingIndex = existingHistory.indexWhere(
        (item) => item['vod_id'] == vodId && item['api_url'] == currentApiUrl,
      );

      if (existingIndex != -1) {
        // 同一源同一视频：更新进度和时间
        existingHistory[existingIndex]['progress'] = '00:00 / 00:00';
        existingHistory[existingIndex]['watchTime'] = DateTime.now().millisecondsSinceEpoch;
        GStorage.saveHistory(existingHistory);
      } else {
        // 不同源：新增一条独立记录
        final historyItem = {
          'vod_id': vodId,
          'vod_name': detail.vodName,
          'vod_pic': detail.vodPic,
          'vod_remarks': episode.name,
          'vod_tag': detail.vodTag ?? '',
          'type_name': sourceName,
          'api_url': currentApiUrl,
          'site_key': siteKey,
          'config_key': Get.find<SourceManager>().currentConfigKey.value,
          'progress': '00:00 / 00:00',
          'watchTime': DateTime.now().millisecondsSinceEpoch,
          'detail_type': detailType,
        };
        existingHistory.insert(0, historyItem);
        if (existingHistory.length > 500) {
          existingHistory.removeRange(500, existingHistory.length);
        }
        GStorage.saveHistory(existingHistory);
      }

      _startProgressUpdater();
    } catch (e) {
      print('添加历史记录失败: $e');
    }
  }

  void _startProgressUpdater() {
    _stopProgressUpdater();  // 先停止之前的
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateHistoryProgress();
    });
  }

  void _stopProgressUpdater() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 通知外部监听器：播放事件
  ///
  /// 未注入监听器时直接返回，不产生任何副作用。
  /// 只在 push 模式（_playDirect）下被调用。
  void _notifyExternalPlayback(String event) {
    final listener = _playbackEventListener;
    if (listener == null) return;

    try {
      // push 模式下 introController.currentPlayEpisode 的索引恒为 0，
      // 会指向播放列表第一集；只有 _currentDirectTitle 才是用户实际点击的
      final episodeName = _currentDirectTitle?.isNotEmpty == true
          ? _currentDirectTitle!
          : (introController.currentPlayEpisode?.name ?? '');
      if (episodeName.isEmpty) return;

      final position = playerController.position;
      final duration = playerController.duration.value;

      switch (event) {
        case 'start':
          listener.onPlaybackStart(
            episodeName: episodeName,
            position: position,
            duration: duration,
          );
          break;
        case 'progress':
          listener.onPlaybackProgress(
            episodeName: episodeName,
            position: position,
            duration: duration,
            isPlaying: playerController.playerStatus.value.isPlaying,
          );
          break;
        case 'stop':
          listener.onPlaybackStop(
            episodeName: episodeName,
            position: position,
            duration: duration,
          );
          break;
      }
    } catch (_) {
      // 外部监听器出错不影响播放
    }
  }

  void _updateHistoryProgress() {
    try {
      final detail = introController.videoDetail.value;
      if (detail == null) return;

      // position 直接使用（是 Duration）
      // duration 使用 .value（是 Rx<Duration>）
      final position = playerController.position;
      final duration = playerController.duration.value;
      if (duration.inSeconds == 0) return;

      final posStr = _formatDuration(position);
      final durStr = _formatDuration(duration);
      final progress = '$posStr / $durStr';

      final historyList = GStorage.getHistory();
      final index = historyList.indexWhere((item) => item['vod_id'] == detail.vodId);
      if (index != -1) {
        historyList[index]['progress'] = progress;
        GStorage.saveHistory(historyList);
      }
    } catch (e) {
      // 忽略更新失败
    }
  }

  Future<void> playEpisode(
    Episode episode, {
    required int sourceIndex,
    required int episodeIndex,
    bool autoPlay = true,
  }) async {
    await _playEpisode(episode, sourceIndex: sourceIndex, episodeIndex: episodeIndex, autoPlay: autoPlay);
  }

  Future<void> switchQuality(PlayQuality quality) async {
    print('=== switchQuality called, url: ${quality.url} ===');
    print('=== currentPlayUrl: ${currentPlayUrl.value} ===');
    if (currentPlayUrl.value == quality.url) return;
    final position = playerController.position;
    currentPlayUrl.value = quality.url;
    // _showPlayLoading();
    try {
      playerController.skipStartDuration.value = skipStartDuration.value;
      playerController.skipEndDuration.value = skipEndDuration.value;
      // await playerController.setDataSource(
      //   NetworkSource(
      //     videoSource: quality.url,
      //     audioSource: null,
      //   ),
      //   autoplay: true,
      //   seekTo: position,
      // );

      // M3U8 走代理
      final proxyUrl = _wrapUrlIfNeeded(quality.url);
      await playerController.setDataSource(
        NetworkSource(
          videoSource: proxyUrl,   // ← 改为 proxyUrl
          audioSource: null,
        ),
        autoplay: true,
        seekTo: position,
      );

      // 应用片头跳过
      await playerController.applySkipStart();

      await playerController.play();
      isPlaying.value = true;
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('切换画质失败');
    }
  }

  Future<void> switchSource(int index) async {
    introController.switchDisplaySource(index);
    
    // 切换线路时重置为自动模式
    isManualParser.value = false;
  }

  // ===== 点击剧集 =====
  Future<void> switchEpisode(int index) async {
    final episodes = introController.displayEpisodes;
    if (index < 0 || index >= episodes.length) return;

    final displayIdx = introController.displaySourceIndex.value;
    introController.switchPlaySource(displayIdx);
    introController.switchEpisode(index);

    final episode = episodes[index];

    checkAndHandlePushEpisode(episode);

    if (episode.url.startsWith('push://')) {
      return;
    }

    // 切换剧集时重置为自动模式
    isManualParser.value = false;

    await playEpisode(
      episode,
      sourceIndex: displayIdx,
      episodeIndex: index,
    );
  }

  Future<bool> playPrev() async {
    final source = introController.getCurrentPlaySource();
    if (source == null) return false;
    final episodes = source.episodes;
    if (episodes.isEmpty) return false;

    int newIndex = introController.currentEpisodeIndex.value - 1;
    if (newIndex < 0) return false;

    final episode = episodes[newIndex];
    introController.switchEpisode(newIndex);

    // 上一集时重置为自动模式
    isManualParser.value = false;

    await playEpisode(
      episode,
      sourceIndex: introController.currentSourceIndex.value,
      episodeIndex: newIndex,
    );
    return true;
  }

  Future<bool> playNext() async {
    final source = introController.getCurrentPlaySource();
    if (source == null) return false;
    final episodes = source.episodes;
    if (episodes.isEmpty) return false;

    int newIndex = introController.currentEpisodeIndex.value + 1;
    if (newIndex >= episodes.length) return false;

    final episode = episodes[newIndex];
    introController.switchEpisode(newIndex);

    // 下一集时重置为自动模式
    isManualParser.value = false;

    await playEpisode(
      episode,
      sourceIndex: introController.currentSourceIndex.value,
      episodeIndex: newIndex,
    );
    return true;
  }

  void toggleDanmaku() {
    playerController.toggleDanmaku();
  }

  void onCast() {
    // ===== 1. 显示 Loading =====
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
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '正在获取投屏信息...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );

    // ===== 2. 获取播放地址 =====
    final playUrl = currentPlayUrl.value;
    if (playUrl.isEmpty) {
      SmartDialog.dismiss();
      SmartDialog.showToast('当前没有可投屏的视频');
      return;
    }

    final title = introController.videoDetail.value?.vodName ?? '';
    final source = introController.getCurrentPlaySource();
    final flag = source?.name ?? '';

    SmartDialog.dismiss();

    // ===== 3. 跳转到 DLNA 页面 =====
    Get.toNamed(
      '/dlna',
      parameters: {
        'url': playUrl,
        'title': title,
        'flag': flag,
      },
    );
  }

  /// 用第三方播放器（MPV / VLC / PotPlayer）打开当前视频
  ///
  /// 流程：
  ///   1. 校验当前播放地址是否有效
  ///   2. 检查用户是否已配置第三方播放器，未配置则引导跳转设置
  ///   3. 暂停内置播放器，记录当前位置
  ///   4. 调用 ExternalPlayerService 启动
  ///   5. 通过 toast 反馈结果
  Future<void> openWithExternalPlayer() async {
    // ---- 1. 校验播放地址 ----
    final url = currentPlayUrl.value;
    if (url.isEmpty) {
      SmartDialog.showToast('当前没有可播放的地址');
      return;
    }

    // ---- 2. 检查是否已配置第三方播放器 ----
    if (!ExternalPlayerService().isConfigured) {
      final goSettings = await SmartDialog.show<bool>(
        builder: (_) => AlertDialog(
          title: const Text('未配置第三方播放器'),
          content: const Text(
            '请先在「设置 → 播放设置 → 第三方播放器」中配置播放器路径',
          ),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => SmartDialog.dismiss(result: true),
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
      if (goSettings == true) {
        Get.to(() => const PlaySettingPage());
      }
      return;
    }

    // ---- 3. 暂停内置播放器，记录当前位置 ----
    final position = playerController.position;
    if (playerController.playerStatus.value.isPlaying) {
      await playerController.pause();
    }

    // ---- 4. 启动第三方播放器 ----
    final headers =
        currentHeaders.value.isNotEmpty ? currentHeaders.value : null;

    final error = await ExternalPlayerService().launch(
      url: url,
      startPosition: position,
      headers: headers,
    );

    // ---- 5. 反馈 ----
    if (error != null) {
      SmartDialog.showToast(error);
    } else {
      final typeLabel = ExternalPlayerService().currentType.label;
      SmartDialog.showToast('已用 $typeLabel 打开');
    }
  }

  /// 用指定的第三方播放器打开当前视频
  ///
  /// 与 [openWithExternalPlayer] 的区别：
  ///   - [openWithExternalPlayer] 走"当前配置的播放器"
  ///   - 本方法由 UI 下拉菜单直接指定类型
  Future<void> openWithPlayer(ExternalPlayerType type) async {
    // ---- 1. 校验播放地址 ----
    final url = currentPlayUrl.value;
    if (url.isEmpty) {
      SmartDialog.showToast('当前没有可播放的地址');
      return;
    }

    // ---- 2. 暂停内置播放器，记录当前位置 ----
    final position = playerController.position;
    if (playerController.playerStatus.value.isPlaying) {
      await playerController.pause();
    }

    // ---- 3. 启动指定类型的播放器 ----
    final headers =
        currentHeaders.value.isNotEmpty ? currentHeaders.value : null;

    final error = await ExternalPlayerService().launchWithType(
      type: type,
      url: url,
      startPosition: position,
      headers: headers,
    );

    // ---- 4. 反馈 ----
    if (error != null) {
      SmartDialog.showToast(error);
    } else {
      SmartDialog.showToast('已用 ${type.label} 打开');
    }
  }

  Future<void> playerInit({bool showLoading = true}) async {
    if (currentPlayUrl.value.isNotEmpty) {
      final position = playerController.position;
      if (showLoading) _showPlayLoading();
      try {
        // await playerController.setDataSource(
        //   NetworkSource(
        //     videoSource: currentPlayUrl.value,
        //     audioSource: null,
        //     headers: currentHeaders.value.isNotEmpty ? currentHeaders.value : null,
        //   ),
        //   autoplay: true,
        //   seekTo: position,
        //   vodId: introController.currentPlayEpisode?.name ?? '',
        //   autoFullScreenFlag: PlayerPref.autoEnterFullScreen,
        // );

        // M3U8 走代理
        final proxyUrl = _wrapUrlIfNeeded(
          currentPlayUrl.value,
          headers: currentHeaders.value.isNotEmpty ? currentHeaders.value : null,
        );
        await playerController.setDataSource(
          NetworkSource(
            videoSource: proxyUrl,
            audioSource: null,
            headers: currentHeaders.value.isNotEmpty ? currentHeaders.value : null,
          ),
          autoplay: true,
          seekTo: position,
          vodId: introController.currentPlayEpisode?.name ?? '',
          autoFullScreenFlag: PlayerPref.autoEnterFullScreen,
        );

        await playerController.applySkipStart();
        await playerController.play();
        isPlaying.value = true;
        if (showLoading) SmartDialog.dismiss(tag: 'play_loading', force: true);
      } catch (e) {
        if (showLoading) SmartDialog.dismiss(tag: 'play_loading', force: true);
        SmartDialog.showToast('重载失败');
      }
    }
  }

  /// 重新加载当前剧集（重新请求播放地址）
  /// [seekTo] 指定起始位置，若不传则从头开始
  Future<void> reloadCurrentEpisode({Duration? seekTo}) async {
    final episode = introController.currentPlayEpisode;
    if (episode == null) {
      SmartDialog.showToast('当前没有播放的剧集');
      return;
    }
    final sourceIndex = introController.currentSourceIndex.value;
    final episodeIndex = introController.currentEpisodeIndex.value;
    await _playEpisode(
      episode,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
      autoPlay: true,
      seekTo: seekTo ?? Duration.zero,
    );
  }

  void showEpisodePanel() {
    final context = Get.context;
    if (context == null) return;
    final episodes = introController.displayEpisodes;
    if (episodes.isEmpty) return;

    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 800;

    if (isWide) {
      // 固定右侧宽度 400px（与内容区一致）
      const double rightWidth = 400.0;
      final padding = MediaQuery.viewPaddingOf(context);
      final availableHeight = size.height - padding.top - padding.bottom;

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭剧集列表',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: rightWidth,
                height: availableHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: EpisodePanelDialog(
                  isWide: true,
                  controllerTag: _tag ?? '',
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      );
    } else {
      final videoHeight = size.width * 9 / 16;
      // 获取顶部安全区域（刘海/状态栏高度）
      final double topPadding = MediaQuery.viewPaddingOf(context).top;
      // 视频实际底部位置 = 视频高度 + 顶部安全区域偏移
      final double topOffset = videoHeight + topPadding;

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭剧集列表',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  top: topOffset,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    // ===== 修改：传递 controllerTag =====
                    child: EpisodePanelDialog(
                      isWide: false,
                      controllerTag: _tag ?? '',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            )),
            child: child,
          );
        },
      );
    }
  }

  void showParserMenu() {
    if (parserSources.isEmpty) {
      SmartDialog.showToast('暂无可用解析源');
      return;
    }
    ParserMenu.show(_tag ?? '');
  }

  Future<void> switchParser(ParserSource parser) async {
    if (currentParser.value?.name == parser.name) return;

    currentParser.value = parser;
    isManualParser.value = true;  // 标记为手动模式

    if (_currentEpisode != null) {
      await _playEpisode(
        _currentEpisode!,
        sourceIndex: _currentSourceIndex,
        episodeIndex: _currentEpisodeIndex,
        autoPlay: true,
      );
    }
  }

  void _loadDanmakuOnPlay(String? originalDanmakuUrl, Map<String, String>? headers) {
    if (_danmakuLoaded) return;   // 避免重复请求

    // 记录当前剧集，防止异步回调覆盖新剧集
    final currentEpisode = _currentEpisode;

    // 尝试用户配置的外部 API
    _loadDanmakuFromUserApi().then((success) {
      // 如果剧集已切换，忽略结果
      if (currentEpisode != _currentEpisode) return;

      if (success) {
        _danmakuLoaded = true;
        return;
      }

      // 降级：仅当原始弹幕 URL 存在且非空时才加载
      if (originalDanmakuUrl != null && originalDanmakuUrl.isNotEmpty) {
        _loadDanmaku(originalDanmakuUrl, headers);
      }
      _danmakuLoaded = true;
    });
  }

  Future<void> _loadDanmaku(String url, Map<String, String>? headers) async {
    try {
      final items = await _danmakuParser.loadFromUrl(url, headers: headers);
      if (items.isNotEmpty && Get.isRegistered<DanmakuController>()) {
        final danmakuController = Get.find<DanmakuController>();
        danmakuController.loadDanmaku(items);
      }
    } catch (e) {}
  }

  @override
  void onClose() {
    _updateHistoryProgress();
    _stopProgressUpdater();

    // 通知外部监听器：先补发一次 progress，再上报 stop
    //   保证即使播放时间很短（<2s），服务器也能拿到有效的 PlaybackPositionTicks
    _externalProgressTimer?.cancel();
    _externalProgressTimer = null;
    _notifyExternalPlayback('progress');
    _notifyExternalPlayback('stop');

    // 重置当前详情页的跳过设置（仅当次有效）
    skipStartDuration.value = 0;
    skipEndDuration.value = 0;

    // 重置播放器引擎中的全局跳过值，避免残留影响后续详情页
    playerController.skipStartDuration.value = 0;
    playerController.skipEndDuration.value = 0;

    autoPlay.value = false;

    playerController.dispose();
    // _cleanTempSubtitleFiles();
    tabCtr.dispose();

    // 移除播放完成监听，防止内存泄漏
    if (_playCompletedListener != null) {
      playerController.removeStatusLister(_playCompletedListener!);
      _playCompletedListener = null;
    }

    super.onClose();
  }

  void toAudioPage() {
    final detail = introController.videoDetail.value;
    if (detail == null) return;

    final playlist = <AudioItem>[];
    for (final source in detail.playSources) {
      for (final episode in source.episodes) {
        playlist.add(AudioItem(
          title: episode.name,
          url: episode.url,
          artist: detail.vodName,
          cover: detail.vodPic,
        ));
      }
    }

    if (playlist.isEmpty) return;

    int index = 0;
    final currentEpisode = introController.currentPlayEpisode;
    if (currentEpisode != null) {
      for (int i = 0; i < playlist.length; i++) {
        if (playlist[i].title == currentEpisode.name) {
          index = i;
          break;
        }
      }
    }

    AudioPage.toAudioPage(
      playlist: playlist,
      index: index,
    );
  }

  Future<void> switchDecodeFormat(String format) async {
    PlayerPref.hardwareDecoding = format;
    await playerInit(showLoading: false);
    SmartDialog.showToast('已切换到 ${format.toUpperCase()} 解码');
  }

  /// 直链播放（跳过详情 API 请求）
  Future<void> _playDirect(String url) async {
    currentPlayUrl.value = url;
    currentQualities.value = [PlayQuality(label: '直链', url: url)];

    // 应用请求头
    final headers = _initHeaders ?? <String, String>{};
    currentHeaders.value = headers;

    final isLocalFile = url.startsWith('file://') ||
        (Uri.tryParse(url)?.scheme == 'file') ||
        (File(url).existsSync());

    DataSource dataSource;
    if (isLocalFile) {
      final filePath = url.startsWith('file://') ? url : 'file://$url';
      dataSource = NetworkSource(
        videoSource: filePath,
        audioSource: null,
        // 本地文件通常不需要 headers，但保留一致性
        headers: headers.isEmpty ? null : headers,
      );
    } else {
      // dataSource = NetworkSource(
      //   videoSource: url,
      //   audioSource: null,
      //   headers: headers.isEmpty ? null : headers,
      // );

      // M3U8 走代理
      final proxyUrl = _wrapUrlIfNeeded(
        url,
        headers: headers.isEmpty ? null : headers,
      );
      dataSource = NetworkSource(
        videoSource: proxyUrl,
        audioSource: null,
        headers: headers.isEmpty ? null : headers,
      );
    }

    try {
      autoPlay.value = true;
      await playerController.setDataSource(
        dataSource,
        autoplay: true,
        seekTo: null,
        vodId: '直链播放',
      );
      // ===== 播放器初始化完成后，关闭加载状态 =====
      isLoadingDetail.value = false;
      await playerController.play();
      isPlaying.value = true;

      // 通知外部监听器：播放开始 + 启动进度上报 Timer
      //   仅在注入了 listener 时生效；否则完全无副作用
      if (_playbackEventListener != null) {
        // 上报 start
        Future.microtask(() => _notifyExternalPlayback('start'));
        // 2 秒后立即上报一次 progress（等播放器有 position 值）
        Future.delayed(const Duration(seconds: 2), () {
          if (_playbackEventListener != null) {
            _notifyExternalPlayback('progress');
          }
        });
        // 每 5 秒上报一次
        _externalProgressTimer?.cancel();
        _externalProgressTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _notifyExternalPlayback('progress'),
        );
      }
    } catch (e) {
      autoPlay.value = false;
      detailError.value = '播放失败: ${e.toString()}';
      isLoadingDetail.value = false;
    }
  }

  /// 重置播放器状态（不销毁播放器）
  void resetPlayer() {
    // 暂停播放
    if (playerController.playerStatus.value.isPlaying) {
      playerController.pause();
    }
    // 清空播放地址
    currentPlayUrl.value = '';
    currentQualities.clear();
    // 重置数据状态
    playerController.dataStatus.value = DataStatus.none;
  }

  // ===== 统一的解析入口（区分手动/自动路径） =====
  /// 返回: 成功返回 PlayUrl，失败返回 null
  Future<PlayUrl?> _parseWithAllParsers(
    PlayUrl playUrl, {
    ParserSource? preferredParser,
  }) async {
    final sources = parserSources;
    if (sources.isEmpty) {
      return null;
    }

    // ===== 手动切换路径：只尝试用户选择的源 =====
    if (preferredParser != null) {
      final result = await _processWithParser(playUrl, preferredParser);
      if (result != null) {
        return result;
      }
      return null;
    }

    // ===== 自动解析路径：按全局模式尝试所有源 =====
    final mode = PlayerPref.parseMode;

    if (mode == 0) {
      // 顺序解析
      for (final parser in sources) {
        final result = await _processWithParser(playUrl, parser);
        if (result != null) {
          currentParser.value = parser;  // 标记解析成功的源
          return result;
        }
      }
      return null;
    } else {
      // 并发解析
      final futures = sources.map((parser) async {
        final result = await _processWithParser(playUrl, parser);
        return (parser: parser, result: result);
      }).toList();

      while (futures.isNotEmpty) {
        final completed = await Future.any(futures);
        if (completed.result != null) {
          currentParser.value = completed.parser;  // 标记解析成功的源
          return completed.result;
        }
        futures.removeWhere((f) => f == completed);
      }
      return null;
    }
  }

  /// 显示简介详情弹窗
  void showIntroDetailPanel(BuildContext context) {
    final detail = introController.videoDetail.value;
    if (detail == null) return;

    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 800;
    final videoHeight = size.width * 9 / 16;
    final double topPadding = MediaQuery.viewPaddingOf(context).top;

    if (isWide) {
      // 固定右侧宽度 400px（与内容区一致）
      const double rightWidth = 400.0;
      final padding = MediaQuery.viewPaddingOf(context);
      final availableHeight = size.height - padding.top - padding.bottom;

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭详情',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: rightWidth,
                height: availableHeight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: IntroDetailPanel(
                  detail: detail,
                  sourceName: introController.sourceName.value,
                  controllerTag: _tag ?? '',
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      );
    } else {
      // 移动端：从底部上滑，顶部对齐视频底部
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭详情',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  top: videoHeight + topPadding,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IntroDetailPanel(
                    detail: detail,
                    sourceName: introController.sourceName.value,
                    controllerTag: _tag ?? '',
                  ),
                ),
              ],
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            )),
            child: child,
          );
        },
      );
    }
  }

  /// 保存当前视频封面图
  Future<void> saveCover() async {
    try {
      final coverUrl = introController.videoDetail.value?.vodPic;
      if (coverUrl == null || coverUrl.isEmpty) {
        SmartDialog.showToast('当前没有封面图');
        return;
      }

      SmartDialog.showToast('正在下载封面...');

      final dio = Dio();
      final response = await dio.get(
        coverUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 && response.data != null) {
        final bytes = response.data as Uint8List;
        final dir = await getTemporaryDirectory();
        final fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);

        SmartDialog.showToast('封面已保存到: $fileName');
      } else {
        SmartDialog.showToast('下载封面失败');
      }
    } catch (e) {
      SmartDialog.showToast('保存封面失败: $e');
    }
  }

  /// 根据用户配置的 API 基础地址、标题和集数，构造 FongMi 弹幕 URL
  String _buildFongmiUrl(String base, String title, int episode) {
    String normalized = base.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    if (!normalized.contains('/fongmi/danmaku')) {
      if (normalized.contains('/api/v2')) {
        final idx = normalized.indexOf('/api/v2');
        if (idx != -1) {
          normalized = normalized.substring(0, idx + 7);
        }
        normalized += '/fongmi/danmaku';
      } else {
        normalized += '/api/v2/fongmi/danmaku';
      }
    }

    final uri = Uri.parse(normalized).replace(queryParameters: {
      'name': title,
      'episode': episode.toString(),
    });
    return uri.toString();
  }

  /// 尝试从设置中配置的弹幕 API 加载弹幕，成功返回 true
  Future<bool> _loadDanmakuFromUserApi() async {
    // 1. 检查自动匹配开关
    final autoMatch = StorageManager.getSetting<bool>(SettingBoxKey.danmakuAutoMatch) ?? false;
    if (!autoMatch) return false;

    // 2. 读取 API 列表和当前选中的 key
    final apisJson = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.danmakuApis) ?? [];
    if (apisJson.isEmpty) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }
    final currentKey = StorageManager.getSetting<String>(SettingBoxKey.danmakuCurrentKey) ?? '';
    if (currentKey.isEmpty) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }

    // 3. 查找匹配的 API 对象
    Map<String, dynamic>? apiMap;
    for (var item in apisJson) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        if (map['key'] == currentKey) {
          apiMap = map;
          break;
        }
      }
    }
    if (apiMap == null) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }
    final apiBase = apiMap['api'] as String?;
    if (apiBase == null || apiBase.isEmpty) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }

    // 4. 获取当前视频标题和集数
    final detail = introController.videoDetail.value;
    if (detail == null) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }
    final title = detail.vodName.trim();
    if (title.isEmpty) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }
    final episodeNumber = introController.currentEpisodeIndex.value + 1;

    // 5. 构造 FongMi URL
    final fongmiUrl = _buildFongmiUrl(apiBase, title, episodeNumber);
    if (fongmiUrl.isEmpty) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }

    // 6. 使用 Dio 请求 FongMi 接口
    try {
      final dio = Dio();
      final response = await dio.get(
        fongmiUrl,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );
      if (response.statusCode != 200) {
        SmartDialog.showToast('未匹配到弹幕');
        return false;
      }

      final data = response.data;

      // 6.1 检查是否为候选列表格式
      if (data is List && data.isNotEmpty && data[0] is Map && (data[0] as Map).containsKey('url')) {
        final firstUrl = data[0]['url'] as String?;
        if (firstUrl == null || firstUrl.isEmpty) {
          SmartDialog.showToast('未匹配到弹幕');
          return false;
        }
        final parser = DanmakuParser();
        final items = await parser.loadFromUrl(firstUrl);
        if (items.isNotEmpty) {
          if (Get.isRegistered<DanmakuController>()) {
            Get.find<DanmakuController>().loadDanmaku(items);
          }
          SmartDialog.showToast('已匹配到弹幕');
          return true;
        } else {
          SmartDialog.showToast('未匹配到弹幕');
          return false;
        }
      }

      // 6.2 否则直接尝试解析（可能标准弹幕格式）
      final parser = DanmakuParser();
      final items = await parser.loadFromUrl(fongmiUrl);
      if (items.isNotEmpty) {
        if (Get.isRegistered<DanmakuController>()) {
          Get.find<DanmakuController>().loadDanmaku(items);
        }
        SmartDialog.showToast('已匹配到弹幕');
        return true;
      } else {
        SmartDialog.showToast('未匹配到弹幕');
        return false;
      }
    } catch (e) {
      print('加载弹幕异常: $e');
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }
  }
}
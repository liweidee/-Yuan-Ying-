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
    // 只处理直链/解析模式
    if (args['directUrl'] == null || args['directUrl'].toString().isEmpty) {
      detailError.value = '推送参数无效';
      isLoadingDetail.value = false;
      return;
    }

    final String url = args['directUrl'].toString();
    final String title = args['directTitle'] ?? '直链播放';
    final bool isParserMode = args['isParserMode'] == true;

    final detail = VideoDetail(
      vodId: 'direct_${Uri.encodeComponent(url)}',
      vodName: title,
      vodPic: '',
      vodContent: isParserMode ? '来自解析播放' : '来自推送播放',
      playSources: [
        PlaySource(
          name: isParserMode ? '解析' : '推送',
          episodes: [
            Episode(
              name: title,
              url: url,
            ),
          ],
        ),
      ],
    );

    introController.setVideoDetail(detail);

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

    _playDirect(url);
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
    _currentEpisode = episode;
    _currentSourceIndex = sourceIndex;
    _currentEpisodeIndex = episodeIndex;

    isPlaying.value = false;
    showParserButton.value = false;

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

    currentPlayUrl.value = defaultUrl;
    currentQualities.value = playUrl.qualities;
    currentHeaders.value = headers;

    final dataSource = NetworkSource(
      videoSource: defaultUrl,
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
      _loadDanmakuOnPlay(danmakuUrl, playUrl.headers);
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
      await playerController.setDataSource(
        NetworkSource(
          videoSource: quality.url,
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

  Future<void> playerInit({bool showLoading = true}) async {
    if (currentPlayUrl.value.isNotEmpty) {
      final position = playerController.position;
      if (showLoading) _showPlayLoading();
      try {
        await playerController.setDataSource(
          NetworkSource(
            videoSource: currentPlayUrl.value,
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

  void _loadDanmakuOnPlay(String danmakuUrl, Map<String, String>? headers) {
    if (_danmakuLoaded) return;

    void listener(PlayerStatus status) {
      if (status.isPlaying && !_danmakuLoaded) {
        _danmakuLoaded = true;
        _loadDanmaku(danmakuUrl, headers);
        if (_danmakuListener != null) {
          playerController.removeStatusLister(_danmakuListener!);
          _danmakuListener = null;
        }
      }
    }

    _danmakuListener = listener;
    playerController.addStatusLister(listener);

    if (playerController.playerStatus.value.isPlaying) {
      _danmakuLoaded = true;
      _loadDanmaku(danmakuUrl, headers);
      if (_danmakuListener != null) {
        playerController.removeStatusLister(_danmakuListener!);
        _danmakuListener = null;
      }
    }
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
    currentHeaders.value = {};

    final isLocalFile = url.startsWith('file://') ||
        (Uri.tryParse(url)?.scheme == 'file') ||
        (File(url).existsSync());

    DataSource dataSource;
    if (isLocalFile) {
      final filePath = url.startsWith('file://') ? url : 'file://$url';
      dataSource = NetworkSource(
        videoSource: filePath,
        audioSource: null,
      );
    } else {
      dataSource = NetworkSource(
        videoSource: url,
        audioSource: null,
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
}
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
// import 'package:yuanying/modules/audio/controllers/audio_controller.dart';
// import 'package:yuanying/modules/audio/views/audio_page.dart';
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
import 'package:yuanying/modules/video/widgets/magnet_file_picker_sheet.dart';
import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'playback_event_listener.dart';
import 'package:yuanying/utils/platform_utils.dart';

import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/services/external_player_service.dart';
import 'package:yuanying/plugin/pl_player/models/external_player_type.dart';
import 'package:yuanying/modules/setting/views/play_setting_page.dart';
import 'package:yuanying/services/ad_block_proxy_service.dart';
import 'package:yuanying/utils/ios_pip_helper.dart';

import 'package:yuanying/modules/download/models/cache_entry.dart';
import 'package:yuanying/modules/download/services/cache_service.dart';
import 'package:yuanying/modules/video/services/android_recording_storage.dart';

import 'package:yuanying/modules/subtitle_translation/models/subtitle_entry.dart';
import 'package:yuanying/modules/subtitle_translation/services/subtitle_srt_parser.dart';
import 'package:yuanying/modules/subtitle_translation/services/subtitle_translation_service.dart';
import 'package:yuanying/modules/subtitle_translation/services/translation_engine.dart';
import 'package:yuanying/modules/agent_llm/models/playback_context.dart';
import 'package:yuanying/services/mpd_parser.dart';
import 'package:yuanying/services/magnet/magnet_episode_adapter.dart';
import 'package:yuanying/services/magnet/magnet_models.dart';
import 'package:yuanying/services/magnet/magnet_plugin_gate.dart';
import 'package:yuanying/services/magnet/magnet_plugin_service.dart';

/// 从历史恢复播放的位置信息
class _ResumeInfo {
  final int? episodeIndex;
  final int? sourceIndex;
  final String? sourceName;
  final String? episodeName;
  final int? positionSeconds;

  _ResumeInfo({
    this.episodeIndex,
    this.sourceIndex,
    this.sourceName,
    this.episodeName,
    this.positionSeconds,
  });

  bool get hasData =>
      episodeIndex != null ||
      sourceIndex != null ||
      (sourceName != null && sourceName!.isNotEmpty) ||
      (episodeName != null && episodeName!.isNotEmpty) ||
      positionSeconds != null;
}

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

  /// 用户当前选中的原始 quality。
  /// `currentPlayUrl` 存的是解析后的实际播放 URL，
  /// 两者语义不同：UI 高亮对比必须用本字段。
  final Rx<PlayQuality?> currentQuality = Rx<PlayQuality?>(null);

  /// 当前播放源的 isDash 快照（用于 switchQuality 同步决策）
  /// null = 接口未指定；1 = DASH；0 = 非 DASH
  int? _currentPlayUrlIsDash;

  Map<String, int>? Function()? _iosPipSourceRectProvider;
  int? _iosPipOriginalEpisodeIndex;
  bool _iosPipWasPlaying = false;
  String? _activeRecordingPath;
  bool _recordingPermissionPromptOpen = false;

  /// 当前播放源的 DASH 外挂音频直链（非 DASH 源为 null）
  ///
  /// `_startPlay` / `switchQuality` 解析 MPD 后写入；
  /// `playerInit`（路由返回恢复播放 / 切换解码格式）重载数据源时复用，
  /// 避免重载后只剩视频流（无声）。
  String? _currentAudioUrl;

  final RxBool isPlaying = false.obs;
  bool _isDirectPushMode = false;
  bool _isMagnetDetailMode = false;
  bool _magnetRouteInFlight = false;
  bool _pipRestoreAutoPlay = false;

  /// 是否为合并列表模式（懒加载：每集先 getDetail 再 getPlayUrl）
  bool _isMergeListMode = false;

  // 外部播放事件监听器（仅 Jellyfin 等需要主动上报的服务器会注入）
  //   未注入时为 null，所有相关调用都会短路返回，行为与原版一致。
  PlaybackEventListener? _playbackEventListener;

  // push 模式下当前播放的标题（用于外部上报反查 itemId）
  //   因为 push 模式下 introController.currentPlayEpisode 可能是错的，
  //   只有 directTitle 才代表用户实际点击的那一集
  String? _currentDirectTitle;

  /// 从历史恢复的播放信息（仅 loadVideoDetail 首次消费一次）
  _ResumeInfo? _resumeInfo;

  // 外部上报的进度 Timer（仅在注入了 listener 时启动）
  Timer? _externalProgressTimer;

  /// 推送模式下的请求头（如 WebDAV Basic Auth、自建服务器 token）
  /// 仅在 isPush 模式下有效；非推送模式保持 null，不影响原逻辑。
  Map<String, String>? _initHeaders;

  /// Web 源推送的播放地址解析器（pageUrl → 真实直链）
  /// 仅 Web Tab 的 openVod 会注入；其它入口为 null
  Future<String?> Function(String url)? _webResolver;

  /// 判断 URL 是否已是可直接播放的媒体地址
  bool _isDirectMediaUrl(String url) {
    // 常见流媒体扩展名 + 带 .m3u8?xxx 参数 + .ts/.webm/.strm
    return RegExp(
          r'\.(m3u8|mp4|flv|mpd|mkv|mov|m4v|ts|webm|strm)(\?|#|$)',
          caseSensitive: false,
        ).hasMatch(url) ||
        // 兜底：任何 http(s) URL 且无 ".html"/".htm"/页面特征 → 视为直链候选
        (url.startsWith('http') && !url.contains('.html'));
  }

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
  List<SubtitleTrack> get subtitleTracks =>
      playerController.availableSubtitleTracks;

  int get currentAudioIndex {
    final current = playerController.currentAudioTrack.value;
    if (current == null) return -1;
    final id = current.id;
    if (id == 'auto') return -2;
    if (id == 'no') return -3;
    if (id.isEmpty) return -1;
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
    if (current == null) return '默认';
    final id = current.id;
    if (id == 'auto') return '自动选择';
    if (id == 'no') return '关闭音轨';
    if (id.isEmpty) return '默认';
    return current.title ?? '未知';
  }

  String get currentVideoName {
    final current = playerController.currentVideoTrack.value;
    return current?.title ?? '默认';
  }

  String get currentSubtitleName {
    final current = playerController.currentSubtitleTrack.value;
    if (current == null) return '关闭';
    final id = current.id;
    if (id == 'auto') return '自动选择';
    if (id == 'no') return '强制无字幕';
    if (id.isEmpty) return '关闭';
    return current.title ?? '未知';
  }

  // ===== 推送相关 =====
  final RxBool showPushButton = false.obs;
  final RxString pushVodId = ''.obs;
  Episode? _pendingMagnetPushEpisode;
  int _pendingMagnetPushSourceIndex = 0;

  // ===== 解析相关 =====
  final RxList<ParserSource> parserSources = <ParserSource>[].obs;
  final Rxn<ParserSource> currentParser = Rxn<ParserSource>();
  final RxBool showParserButton = false.obs;

  /// 自动播放状态（用于控制封面显示）
  final RxBool autoPlay = false.obs;

  String get magnetOwnerTag => 'detail:${_tag ?? 'default'}';

  /// 播放失败状态（用于切集失败时回退到封面 + 错误提示）
  final RxBool playFailed = false.obs;
  final RxString playErrorMessage = ''.obs;

  /// 统一处理播放失败：
  /// - 关闭残留弹窗
  /// - toast 提示用户
  /// - 记录失败状态
  /// - 把 autoPlay 拉回 false，触发 video_page 的封面 UI
  /// - 清掉 dataStatus，避免 loading 卡死
  void _handlePlayFailure(String message) {
    SmartDialog.dismiss(force: true);
    SmartDialog.showToast(message);
    playFailed.value = true;
    playErrorMessage.value = message;
    autoPlay.value = false;
    try {
      playerController.dataStatus.value = DataStatus.none;
    } catch (_) {}
  }

  /// 清除播放失败状态（每次开始新的播放前调用）
  void _clearPlayFailure() {
    if (playFailed.value) playFailed.value = false;
    if (playErrorMessage.value.isNotEmpty) playErrorMessage.value = '';
  }

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

  /// 字幕翻译进度（null 表示没有进行中的翻译）。
  ///
  /// 用 Rxn 独立暴露，进度更新只刷新监听它的小 widget，不触发整个页面重建。
  final Rxn<SubtitleTranslationProgress> translationProgress =
      Rxn<SubtitleTranslationProgress>(null);

  /// 是否正在翻译。
  bool get isTranslating => translationProgress.value != null;

  /// 临时字幕文件列表（用于 FVP 引擎的内存字幕缓存）
  final List<String> _tempSubtitleFiles = [];

  /// 当前选中的字幕索引（-1 表示关闭）
  late final RxInt vttSubtitlesIndex = (-1).obs;

  // ===== 临时站点（用于推送跳转等场景） =====
  Map<String, dynamic>? _tempSite;

  // 跳过片头片尾（仅当次有效，详情页级别）
  final RxInt skipStartDuration = 0.obs; // 片头跳过秒数
  final RxInt skipEndDuration = 0.obs; // 片尾跳过秒数

  // ===== 片头/片尾快捷标记 =====
  //
  // 标记按钮与“更多设置-跳过片头片尾”共用 skipStartDuration/skipEndDuration，
  // 不维护第二套标记状态，避免两边数值不同步或互相覆盖。
  /// 片头/片尾标记的容差范围（秒）
  static const int tipMarkToleranceSeconds = 180;

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
        track = SubtitleTrack(
          filePath,
          subtitle.lanDoc,
          subtitle.lan,
          uri: true,
        );
      } else {
        // media_kit 引擎
        if (entry.isData) {
          track = SubtitleTrack.data(
            entry.id,
            title: subtitle.lanDoc,
            language: subtitle.lan,
          );
        } else {
          // 修复本地文件路径格式转换
          //
          // 原始代码：SubtitleTrack(entry.id, ..., uri: true)
          //   entry.id 是 file:///C:/... 三斜杠 URI，mpv 的 sub-add 对
          //   Windows 三斜杠 URI 的编码兼容性差，路径含中文 / & / 空格时
          //   常报 "Can not open external file file:///C:/..."。
          //
          // 修复后：转为裸路径（正斜杠），uri 保持 true
          //   - 裸路径 C:/Users/.../x.ass 是 mpv 最稳的本地文件格式
          //   - uri: true 必须保留：media_kit 的 uri 标志为 false 时会构造
          //     sub-add memory://<base64(id)>，把路径当内联字幕内容，
          //     导致完全无字幕、CC 按钮不出现
          final localPath = _toLocalPath(entry.id).replaceAll('\\', '/');
          track = SubtitleTrack(
            localPath,
            subtitle.lanDoc,
            subtitle.lan,
            uri: true,
          );
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
        options: Options(
          responseType: ResponseType.bytes,
          // 字幕源无响应时快速失败，避免 loading 长时间转圈
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.statusCode == 200) {
        final content = utf8.decode(response.data as List<int>);
        final currentEngine = PlayerPref.playerEngine;
        SubtitleTrack track;

        if (currentEngine == PlayerEngineType.fvp) {
          final filePath = await _writeSubtitleToTempFile(content, 'vtt');
          track = SubtitleTrack(
            filePath,
            subtitle.lanDoc,
            subtitle.lan,
            uri: true,
          );
        } else {
          track = SubtitleTrack.data(
            content,
            title: subtitle.lanDoc,
            language: subtitle.lan,
          );
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

  /// 将 file:// URI 或原始路径统一转为本地文件路径（不带 file:// 前缀）
  ///
  /// 处理场景：
  /// - Windows: `file:///C:/Users/xxx/a.ass` → `C:\Users\xxx\a.ass`
  /// - macOS/Linux: `file:///Users/xxx/a.ass` → `/Users/xxx/a.ass`
  /// - 裸路径（已经是本地路径）：原样返回
  /// - 网络 URL（http/https）：原样返回
  String _toLocalPath(String id) {
    if (!id.startsWith('file://')) return id;
    try {
      return Uri.parse(id).toFilePath();
    } catch (_) {
      // 兜底：手动解析
      var path = id.substring('file://'.length);
      if (Platform.isWindows && path.startsWith('/')) {
        path = path.substring(1);
      }
      try {
        path = Uri.decodeComponent(path);
      } catch (_) {}
      return path;
    }
  }

  /// 解析指定索引的字幕为 [SubtitleEntry] 列表（1-based，与 setSubtitle 一致）。
  ///
  /// 支持来源：
  ///  - 内存中的 JSON / VTT / SRT 内容（isData: true）
  ///  - 本地文件路径（含 file:// URI）
  ///  - 网络字幕 URL（会下载）
  Future<List<SubtitleEntry>> _resolveSubtitleEntries(int index) async {
    if (index <= 0 || index > subtitles.length) return const [];
    final entry = vttSubtitles[index - 1];
    if (entry == null) return const [];

    String content;
    if (entry.isData) {
      content = entry.id;
    } else {
      final id = entry.id;
      if (id.startsWith('http://') || id.startsWith('https://')) {
        try {
          final response = await Dio().get(
            id,
            options: Options(
              responseType: ResponseType.plain,
              // 字幕源无响应时快速失败，避免翻译流程长时间挂起
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          content = (response.data ?? '').toString();
        } catch (e) {
          throw TranslationException('下载网络字幕失败：$e');
        }
      } else {
        var path = id;
        if (path.startsWith('file://')) {
          try {
            path = Uri.parse(path).toFilePath();
          } catch (_) {
            path = path.substring('file://'.length);
          }
        }
        final file = File(path);
        if (!await file.exists()) {
          throw const TranslationException('字幕文件不存在');
        }
        content = await file.readAsString();
      }
    }

    // 检测 ASS / SSA：ASS 承载特效样式，交给播放器原生渲染是最优解，
    // 翻译会丢样式、且常有 GBK/BIG5 编码问题，暂不支持。
    final head = content.length > 4096 ? content.substring(0, 4096) : content;
    final headTrimmed = head.trimLeft();
    if (headTrimmed.startsWith('[Script Info]') ||
        headTrimmed.contains('[Events]') ||
        headTrimmed.contains('[V4+ Styles]') ||
        headTrimmed.contains('[V4 Styles]')) {
      throw const TranslationException(
        'ASS / SSA 字幕包含特效样式，暂不支持翻译。'
        '可先用字幕编辑器导出为 SRT 后再加载',
      );
    }

    return SubtitleSrtParser.parse(content);
  }

  /// 翻译当前选中的字幕。
  ///
  /// 流程：解析 → 网络翻译（带缓存）→ 写临时 SRT → 注册到字幕列表 → 可选自动切换。
  /// 全部在独立 Future 中执行，不阻塞播放。
  Future<void> translateCurrentSubtitle() async {
    if (isTranslating) {
      SmartDialog.showToast('已有翻译任务在进行');
      return;
    }

    if (!PlayerPref.subtitleTranslationEnabled) {
      SmartDialog.showToast('请先在「设置 → 播放设置 → 字幕翻译」中启用');
      return;
    }

    final idx = vttSubtitlesIndex.value;
    if (idx <= 0 || idx > subtitles.length) {
      SmartDialog.showToast('请先通过「加载字幕」载入外部字幕文件（内嵌/硬字幕无法翻译）');
      return;
    }

    final engine = SubtitleTranslationService.instance.getActiveEngine();
    if (!engine.isConfigured) {
      SmartDialog.showToast(engine.configurationError ?? '翻译服务未配置');
      return;
    }

    final targetLang = PlayerPref.subtitleTranslationTargetLang;

    // 解析字幕源
    List<SubtitleEntry> entries;
    try {
      entries = await _resolveSubtitleEntries(idx);
    } catch (e) {
      SmartDialog.showToast('$e');
      return;
    }
    if (entries.isEmpty) {
      SmartDialog.showToast('字幕内容为空或格式不支持');
      return;
    }

    // 中文字幕检测：避免用户对已是中文的字幕重复翻译，
    // 白白消耗翻译服务的免费额度。
    if (SubtitleTranslationService.looksLikeAlreadyTargetLang(
      entries,
      targetLang,
    )) {
      final langName = TranslationLanguage.findByCode(targetLang).name;
      SmartDialog.showToast(
        '检测到字幕已是$langName，已跳过翻译。'
        '如需翻译请手动修改目标语言',
      );
      return;
    }

    // 用视频名做语境（百度大模型会用到）
    final contextTitle = introController.videoDetail.value?.vodName;

    translationProgress.value = SubtitleTranslationProgress(
      done: 0,
      total: entries.length,
    );

    try {
      final translated = await SubtitleTranslationService.instance.translate(
        videoId: vodId,
        subtitleIndex: idx,
        entries: entries,
        targetLang: targetLang,
        contextTitle: contextTitle,
        onProgress: (done, total) {
          translationProgress.value = SubtitleTranslationProgress(
            done: done,
            total: total,
          );
        },
      );

      if (isClosed) return;

      // 序列化为 SRT
      final srtContent = SubtitleSrtParser.serialize(translated);
      final srtPath = await _writeSubtitleToTempFile(srtContent, 'srt');

      if (isClosed) return;

      // 注册为一条新字幕
      final newIndex = subtitles.length + 1;
      final langName = TranslationLanguage.findByCode(targetLang).name;
      subtitles.add(
        Subtitle(
          lan: targetLang,
          lanDoc: 'AI 翻译（$langName）',
        ),
      );
      vttSubtitles[subtitles.length - 1] = (
        isData: false,
        id: Uri.file(srtPath).toString(),
      );

      // 自动切换
      if (PlayerPref.subtitleTranslationAutoApply) {
        await setSubtitle(newIndex);
        SmartDialog.showToast(
          '翻译完成（共 ${translated.length} 条），已切换为译文。'
          '原字幕仍保留在字幕列表里，可随时切回',
        );
      } else {
        SmartDialog.showToast(
          '翻译完成（共 ${translated.length} 条）。'
          '可在字幕菜单切换到「AI 翻译」',
        );
      }
    } catch (e) {
      SmartDialog.showToast('翻译失败：$e');
    } finally {
      translationProgress.value = null;
    }
  }

  /// 将字幕内容写入临时文件，返回文件路径
  Future<String> _writeSubtitleToTempFile(
    String content,
    String extension,
  ) async {
    final dir = await getTemporaryDirectory();
    final fileName =
        'subtitle_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.$extension';
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

  // ============================================================
  // 录制功能
  // ============================================================

  /// 获取录制保存目录（按平台）
  Future<Directory?> _getRecordingDir() async {
    try {
      String basePath;
      if (Platform.isAndroid) {
        final publicDirectory =
            await AndroidRecordingStorage.getRecordingDirectory();
        if (publicDirectory == null || publicDirectory.isEmpty) {
          return null;
        }
        basePath = publicDirectory;
      } else if (PlatformUtils.isDesktop) {
        final home =
            Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
        if (home == null) return null;
        basePath =
            '$home${Platform.pathSeparator}Downloads'
            '${Platform.pathSeparator}源影录制';
      } else {
        final docs = await getApplicationDocumentsDirectory();
        basePath = '${docs.path}${Platform.pathSeparator}源影录制';
      }
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (e) {
      debugPrint('[DetailController] 获取录制目录失败: $e');
      return null;
    }
  }

  Future<bool> _ensureAndroidRecordingStorageAccess() async {
    if (!Platform.isAndroid) return true;
    if (await AndroidRecordingStorage.hasAccess()) return true;
    if (_recordingPermissionPromptOpen) return false;

    final context = Get.context;
    if (context == null) {
      SmartDialog.showToast('请先允许文件访问后再录制');
      return false;
    }
    if (!context.mounted) return false;

    _recordingPermissionPromptOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要文件访问权限'),
          content: const Text(
            '录制视频需要保存到系统 Movies/源影录制 目录，'
            '以便在文件管理和媒体库中查看。是否前往授权？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('前往授权'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;

      final granted = await AndroidRecordingStorage.requestAccess();
      if (granted) return true;
      SmartDialog.showToast('完成授权后，请再次点击录制');
      return false;
    } finally {
      _recordingPermissionPromptOpen = false;
    }
  }

  /// 启动录制
  /// 返回 true 表示成功
  Future<bool> startRecording() async {
    if (playerController.isRecording.value) return false;
    if (!await _ensureAndroidRecordingStorageAccess()) return false;

    final dir = await _getRecordingDir();
    if (dir == null) {
      SmartDialog.showToast('无法创建录制目录');
      return false;
    }

    final videoName = introController.videoDetail.value?.vodName ?? '未知视频';
    // 过滤文件名非法字符
    final safeName = videoName.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');

    final now = DateTime.now();
    final ts =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    final path = '${dir.path}${Platform.pathSeparator}源影_${safeName}_$ts.mp4';

    final ok = playerController.startRecording(path);
    if (ok) {
      _activeRecordingPath = path;
      debugPrint('[DetailController] 录制文件: $path');
    } else {
      SmartDialog.showToast('录制启动失败，当前设备可能不支持');
    }
    return ok;
  }

  /// 停止录制
  void stopRecording() {
    if (playerController.isRecording.value || _activeRecordingPath != null) {
      unawaited(stopRecordingAndPublish());
    }
  }

  Future<String?> stopRecordingAndPublish() async {
    final path = _activeRecordingPath;
    _activeRecordingPath = null;
    playerController.stopRecording();
    if (path != null && Platform.isAndroid) {
      await _waitForRecordingFileReady(path);
      final scanned = await AndroidRecordingStorage.scanFile(path);
      if (!scanned) {
        debugPrint('[DetailController] 录制文件媒体扫描失败: $path');
      }
    }
    return path;
  }

  Future<void> _waitForRecordingFileReady(String path) async {
    var lastSize = -1;
    var stableCount = 0;
    for (var attempt = 0; attempt < 24; attempt++) {
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size > 0 && size == lastSize) {
          stableCount++;
          if (stableCount >= 3) return;
        } else {
          stableCount = 0;
        }
        lastSize = size;
      } catch (_) {}
    }
  }

  /// 在 `_playEpisode` 顶部调用（切集前）
  void _stopRecordingIfActive() {
    if (playerController.isRecording.value) {
      stopRecording();
      SmartDialog.showToast('已切换剧集，录制自动停止');
    }
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

  /// 从内容字符串挂载外部字幕（供字幕网站搜索下载使用）
  ///
  /// 存储格式与 `_loadSubtitle` 完全一致，保证新代码走原始 `setSubtitle`
  /// 的已知正常工作路径，不引入新分支：
  /// - SRT：转为 VTT 内容，`isData: true`（与 JSON 加载一致）
  /// - VTT：直接存内容，`isData: true`
  /// - ASS/SSA/SUB：写临时文件，`isData: false + file:// URI`（与本地字幕加载一致）
  Future<void> addSubtitleFromContent({
    required String content,
    required String name,
    required String ext,
  }) async {
    if (isClosed) return;
    final index = subtitles.length;
    final lower = ext.toLowerCase();

    if (lower == 'srt') {
      vttSubtitles[index] = (isData: true, id: _srtToVtt(content));
    } else if (lower == 'vtt') {
      vttSubtitles[index] = (isData: true, id: content);
    } else {
      // ASS / SSA / SUB：写临时文件，保留原格式
      // 关键：存 file:// URI，与 _loadSubtitle 完全一致，
      // 这样 setSubtitle 里 FVP / media_kit 分支都能走原始已知正常路径
      final path = await _writeSubtitleToTempFile(content, lower);
      vttSubtitles[index] = (
        isData: false,
        id: Uri.file(path).toString(),
      );
    }

    subtitles.add(Subtitle(lan: '', lanDoc: name));
    await setSubtitle(index + 1);
    if (!isClosed) {
      SmartDialog.showToast('已加载字幕：$name');
    }
  }

  /// SRT 内容转 VTT 内容
  ///
  /// 关键点：
  /// 1. 补 `WEBVTT` 头
  /// 2. 时间戳行的逗号必须改为点（SRT 是 `00:00:00,000`，VTT 规范要求 `00:00:00.000`）
  ///    不转换会导致 mpv / mdk 按严格模式解析失败，字幕不显示
  ///    只对时间戳行转换，不碰文本内容里的逗号
  String _srtToVtt(String srt) {
    final normalized = srt.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final buffer = StringBuffer('WEBVTT\n\n');
    final tsPattern = RegExp(r'^\d{1,2}:\d{2}:\d{2},\d{3}\s*-->');
    for (final line in lines) {
      if (tsPattern.hasMatch(line)) {
        buffer.writeln(line.replaceAll(',', '.'));
      } else {
        buffer.writeln(line);
      }
    }
    return buffer.toString().trim();
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
      _pipRestoreAutoPlay = args['pipRestoreAutoPlay'] == true;
      // ---- 独立磁力详情页（优先于普通推送/详情消息） ----
      if (args['isMagnetMode'] == true) {
        _initMagnetMode(args);
        return;
      }

      // ---- 合并列表模式（优先级最高，命中即返回） ----
      if (args['mergeDetail'] is VideoDetail) {
        _initMergeListMode(args);
        return;
      }

      // ---- 推送模式（直接播放，提前返回） ----
      if (args['isPush'] == true) {
        if (args['directUrl'] != null &&
            args['directUrl'].toString().isNotEmpty) {
          _initPushMode(args);
          return;
        }
      }

      // ---- 初始化 _apiService ----
      final independentSite = args['site'] as Map<String, dynamic>?;
      if (independentSite != null) {
        _apiService = Get.find<SourceManager>().createIndependentService(
          independentSite,
        );
        _currentSiteConfig = independentSite; // 新增
        // 传递来源名称
        final siteName = independentSite['name']?.toString() ?? '未知来源';
        introController.setSourceName(siteName);
      } else {
        // 默认使用全局当前源
        _apiService = Get.find<SourceManager>().currentApiService;
        _currentSiteConfig = Get.find<SourceManager>().currentSite.value; // 新增
        // 传递当前源名称
        final currentSite = Get.find<SourceManager>().currentSite.value;
        if (currentSite != null) {
          introController.setSourceName(
            currentSite['name']?.toString() ?? '未知来源',
          );
        }
      }

      // ---- 保存 vodId / pwd ----
      vodId = args['vodId'] ?? args['id'] ?? args['videoId'] ?? '';
      pwd = args['pwd'] ?? 'tinydust';
      introController.setOriginalVodId(vodId);
      // ---- 收藏基线：以本详情页实际生效的站点为准 ----
      // 独立站点页（args['site'] != null）时 _currentSiteConfig 是独立站点，
      // 不能沿用全局 currentSite，否则收藏记录的 api_url / site_key 全错，
      // 收藏恢复时会跳到错误的源。
      final effectiveSiteConfig = _currentSiteConfig;
      if (effectiveSiteConfig != null) {
        introController.setCurrentApiUrl(
          effectiveSiteConfig['api']?.toString() ?? '',
        );
        introController.setSiteConfig(effectiveSiteConfig);
      }

      // ===== 解析从历史恢复的播放信息 =====
      final rEpIdx = args['resumeEpisodeIndex'];
      final rSrcIdx = args['resumeSourceIndex'];
      final rSrcName = args['resumeSourceName']?.toString();
      final rEpName = args['resumeEpisodeName']?.toString();
      final rPos = args['resumePositionSeconds'];
      if (rEpIdx is int ||
          rSrcIdx is int ||
          rPos is num ||
          (rSrcName != null && rSrcName.isNotEmpty) ||
          (rEpName != null && rEpName.isNotEmpty)) {
        _resumeInfo = _ResumeInfo(
          episodeIndex: rEpIdx is int ? rEpIdx : null,
          sourceIndex: rSrcIdx is int ? rSrcIdx : null,
          sourceName: rSrcName,
          episodeName: rEpName,
          positionSeconds: rPos is num ? rPos.toInt() : null,
        );
        debugPrint(
          '[DetailController] 收到历史恢复参数: '
          'epIdx=${_resumeInfo!.episodeIndex}, '
          'srcIdx=${_resumeInfo!.sourceIndex}, '
          'srcName=${_resumeInfo!.sourceName}, '
          'epName=${_resumeInfo!.episodeName}, '
          'pos=${_resumeInfo!.positionSeconds}',
        );
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
    _isDirectPushMode =
        args['isDirectPushMode'] == true || args['videoDetail'] is VideoDetail;

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
      detail = args['videoDetail'] as VideoDetail;

      if (args['sourceName'] != null) {
        introController.setSourceName(args['sourceName'].toString());
      }

      if (detail.playSources.isEmpty) {
        detail = VideoDetail(
          vodId: detail.vodId,
          vodName: detail.vodName,
          vodPic: detail.vodPic,
          vodContent: detail.vodContent,
          vodYear: detail.vodYear,
          vodActor: detail.vodActor,
          vodDirector: detail.vodDirector,
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
      detail = VideoDetail(
        vodId: 'direct_${Uri.encodeComponent(url)}',
        vodName: title,
        vodPic: args['vodPic'] ?? '',
        vodContent: args['vodContent'] ?? (isParserMode ? '来自解析播放' : '来自推送播放'),
        vodYear: args['vodYear'] ?? '',
        vodActor: args['vodActor'] ?? '',
        vodDirector: args['vodDirector'] ?? '',
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

    final resumeSeconds = args['resumePositionSeconds'];
    _playDirect(
      url,
      seekTo: resumeSeconds is num && resumeSeconds > 0
          ? Duration(seconds: resumeSeconds.toInt())
          : null,
    );

    // Web 源解析器注入（可选）
    final resolver = args['webResolver'];
    if (resolver is Function) {
      _webResolver = (url) async {
        try {
          final r = await resolver(url);
          return r?.toString();
        } catch (_) {
          return null;
        }
      };
    }
  }

  void _initMagnetMode(Map args) {
    _isDirectPushMode = true;
    _isMagnetDetailMode = true;

    final magnet = args['magnetUrl']?.toString() ?? '';
    if (!MagnetUri.isMagnet(magnet)) {
      detailError.value = '磁力链接无效';
      isLoadingDetail.value = false;
      return;
    }

    vodId = 'magnet_${DateTime.now().millisecondsSinceEpoch}';
    pwd = 'tinydust';
    final title = args['magnetTitle']?.toString().trim().isNotEmpty == true
        ? args['magnetTitle'].toString()
        : args['directTitle']?.toString().trim().isNotEmpty == true
        ? args['directTitle'].toString()
        : MagnetUri.displayNameFromMagnet(magnet) ?? '磁力播放';
    final sourceName = args['sourceName']?.toString().trim().isNotEmpty == true
        ? args['sourceName'].toString()
        : '磁力';

    // 磁力详情页是临时播放上下文，不具备可持久化的站点 vodId。
    introController.setOriginalVodId('');
    introController.setSourceName(sourceName);
    _currentDirectTitle = title;
    tabCtr = TabController(length: 3, vsync: this, initialIndex: 0);

    final placeholder = VideoDetail(
      vodId: vodId,
      vodName: title,
      vodPic: args['vodPic']?.toString() ?? '',
      vodContent: args['vodContent']?.toString(),
      typeName: args['typeName']?.toString() ?? sourceName,
      playSources: [
        PlaySource(
          name: sourceName,
          episodes: [
            Episode(
              name: args['directTitle']?.toString() ?? title,
              url: magnet,
            ),
          ],
        ),
      ],
    );
    introController.setVideoDetail(placeholder);
    isLoadingDetail.value = false;
    autoPlay.value = false;

    final shouldAutoPlay = args['magnetAutoPlay'] == true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isClosed) {
        unawaited(
          _loadMagnetDetail(placeholder, shouldAutoPlay: shouldAutoPlay),
        );
      }
    });
  }

  Future<bool> _openMagnetDetailPage({
    required String magnet,
    required String title,
    required String vodName,
    String? vodPic,
    String? vodContent,
    String? typeName,
    required String sourceName,
    required bool autoPlay,
  }) async {
    if (_magnetRouteInFlight) return false;
    _magnetRouteInFlight = true;
    try {
      if (!await MagnetPluginGate.ensureReady()) return false;
      final tag = 'magnet_${DateTime.now().millisecondsSinceEpoch}';
      await Get.toNamed(
        AppPages.detail,
        arguments: {
          'isMagnetMode': true,
          'magnetUrl': magnet,
          'magnetAutoPlay': autoPlay,
          'magnetTitle': vodName,
          'directTitle': title,
          'vodPic': vodPic,
          'vodContent': vodContent,
          'typeName': typeName,
          'sourceName': sourceName,
          '_controllerTag': tag,
        },
        preventDuplicates: false,
      );
      return true;
    } finally {
      _magnetRouteInFlight = false;
    }
  }

  /// 将普通详情页中的磁力资源切换到独立磁力详情页。
  ///
  /// 仅由统一的推送入口调用。返回 true 表示已消费本次操作：无论插件是否
  /// 可用，调用方都不能继续原播放流程。
  Future<bool> _openMagnetDetailForEpisode(
    Episode episode, {
    required int sourceIndex,
    required bool autoPlay,
  }) async {
    if (_isMagnetDetailMode) return false;

    final magnet = episode.url;
    if (!MagnetUri.isMagnet(magnet)) return false;

    final detail = introController.videoDetail.value;
    final sourceName = introController.getSource(sourceIndex)?.name.trim();
    final vodName = detail?.vodName.trim();
    final opened = await _openMagnetDetailPage(
      magnet: magnet,
      title: episode.name,
      vodName: vodName == null || vodName.isEmpty ? episode.name : vodName,
      vodPic: detail?.vodPic,
      vodContent: detail?.vodContent,
      typeName: detail?.typeName,
      sourceName: sourceName == null || sourceName.isEmpty ? '磁力' : sourceName,
      autoPlay: autoPlay,
    );
    if (!opened) {
      final hasLoadedVideo =
          currentPlayUrl.value.isNotEmpty &&
          playerController.dataStatus.value == DataStatus.loaded;
      if (!hasLoadedVideo) {
        this.autoPlay.value = false;
        isPlaying.value = false;
        try {
          playerController.dataStatus.value = DataStatus.none;
        } catch (_) {}
      }
    }
    return true;
  }

  Future<void> _loadMagnetDetail(
    VideoDetail placeholder, {
    required bool shouldAutoPlay,
  }) async {
    final magnet = placeholder.playSources.first.episodes.first.url;
    if (!await MagnetPluginGate.ensureReady()) {
      autoPlay.value = false;
      return;
    }
    if (isClosed) return;

    const loadingTag = 'magnet_metadata_loading';
    SmartDialog.show(
      tag: loadingTag,
      maskColor: Colors.black54,
      clickMaskDismiss: false,
      backType: SmartBackType.block,
      animationType: SmartAnimationType.scale,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在读取磁力种子信息...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;

    try {
      final expansion = await MagnetPluginService.instance.expandMagnet(
        magnet,
        ownerTag: magnetOwnerTag,
        timeout: const Duration(seconds: 30),
      );
      if (isClosed) return;

      final detail = MagnetEpisodeAdapter.buildPushDetail(
        magnet: magnet,
        expansion: expansion,
        title: placeholder.vodName,
        vodPic: placeholder.vodPic,
        vodContent: placeholder.vodContent,
        typeName: placeholder.typeName,
      );
      if (detail == null) {
        _handlePlayFailure('种子中没有可播放的视频文件');
        return;
      }
      introController.setVideoDetail(detail);
      isLoadingDetail.value = false;
      autoPlay.value = false;
      SmartDialog.dismiss(tag: loadingTag, force: true);

      if (!shouldAutoPlay || detail.playSources.isEmpty) return;
      final videos = expansion.files
          .where((file) => file.isLikelyVideo)
          .toList();
      MagnetFileInfo? selected;
      if (videos.length == 1) {
        selected = videos.first;
      } else {
        final context = Get.context;
        if (context == null) return;
        selected = await showMagnetFilePickerSheet(
          context,
          title: videos.length > 1 ? '选择要播放的视频文件' : '选择种子文件',
          files: videos,
        );
      }
      if (selected == null || isClosed) return;

      final source = detail.playSources.first;
      final episodeIndex = source.episodes.indexWhere((episode) {
        final ref = MagnetUri.parse(episode.url);
        return ref?.fileIndex == selected!.index;
      });
      if (episodeIndex < 0) {
        _handlePlayFailure('种子文件信息无效');
        return;
      }

      _currentSourceIndex = 0;
      _currentEpisodeIndex = episodeIndex;
      _currentEpisode = source.episodes[episodeIndex];
      introController.switchPlaySource(0);
      introController.switchEpisode(episodeIndex);
      await _playEpisode(
        _currentEpisode!,
        sourceIndex: 0,
        episodeIndex: episodeIndex,
        autoPlay: true,
      );
    } catch (e) {
      if (!isClosed) {
        _handlePlayFailure('磁力解析失败: ${e.toString()}');
      }
    } finally {
      SmartDialog.dismiss(tag: loadingTag, force: true);
    }
  }

  /// 合并列表模式初始化
  ///
  /// 与其它模式的区别：
  /// - 调用方传入完整 VideoDetail，不请求详情 API
  /// - `_isDirectPushMode` 保持 false，走 getPlayUrl 换真实地址
  /// - 从 mergeStartVodId 定位起始集，然后自动播放
  void _initMergeListMode(Map args) {
    _isMergeListMode = true; // 开启标志
    final detail = args['mergeDetail'] as VideoDetail;
    final startVodId = args['mergeStartVodId']?.toString() ?? '';

    // ---- 1. _apiService + _currentSiteConfig ----
    final independentSite = args['site'] as Map<String, dynamic>?;
    if (independentSite != null) {
      _apiService = Get.find<SourceManager>().createIndependentService(
        independentSite,
      );
      _currentSiteConfig = independentSite;
      introController.setSourceName(
        independentSite['name']?.toString() ?? '未知来源',
      );
    } else {
      _apiService = Get.find<SourceManager>().currentApiService;
      _currentSiteConfig = Get.find<SourceManager>().currentSite.value;
      final currentSite = Get.find<SourceManager>().currentSite.value;
      if (currentSite != null) {
        introController.setSourceName(
          currentSite['name']?.toString() ?? '未知来源',
        );
      }
    }

    // ---- 2. vodId / pwd ----
    vodId = args['vodId']?.toString() ?? '';
    pwd = args['pwd']?.toString() ?? 'tinydust';
    introController.setOriginalVodId(vodId);
    // 与标准路径一致：收藏基线用本详情页实际生效的站点（可能为独立站点）
    final mergeEffectiveSite = _currentSiteConfig;
    if (mergeEffectiveSite != null) {
      introController.setCurrentApiUrl(
        mergeEffectiveSite['api']?.toString() ?? '',
      );
      introController.setSiteConfig(mergeEffectiveSite);
    }

    // ---- 3. 加载解析源 ----
    _loadParsers();

    // ---- 4. vodId 兜底校验 ----
    if (vodId.isEmpty) {
      detailError.value = '视频ID缺失';
      isLoadingDetail.value = false;
      return;
    }

    // ---- 5. TabController ----
    tabCtr = TabController(
      length: 3,
      vsync: this,
      initialIndex: 0,
    );

    // ---- 6. 设置详情 ----
    introController.setVideoDetail(detail);
    isLoadingDetail.value = false;

    // ---- 7. 空列表兜底 ----
    if (detail.playSources.isEmpty || detail.playSources[0].episodes.isEmpty) {
      detailError.value = '合并列表为空';
      return;
    }

    // ---- 8. 定位起始集（Episode.url == vodId）----
    final episodes = detail.playSources[0].episodes;
    int startIdx = 0;
    if (startVodId.isNotEmpty) {
      for (int i = 0; i < episodes.length; i++) {
        if (episodes[i].url == startVodId) {
          startIdx = i;
          break;
        }
      }
    }

    final startEpisode = episodes[startIdx];
    if (checkAndHandlePushEpisode(startEpisode, sourceIndex: 0)) return;

    _currentSourceIndex = 0;
    _currentEpisodeIndex = startIdx;
    _currentEpisode = episodes[startIdx];

    // ---- 9. 同步 IntroController 索引 ----
    introController.switchPlaySource(0);
    introController.switchEpisode(startIdx);

    // ---- 10. 走 API 播放（_isDirectPushMode 保持 false）----
    final mergeResumeSeconds = args['resumePositionSeconds'];
    _playEpisode(
      _currentEpisode!,
      sourceIndex: 0,
      episodeIndex: startIdx,
      autoPlay: true,
      seekTo: mergeResumeSeconds is num && mergeResumeSeconds > 0
          ? Duration(seconds: mergeResumeSeconds.toInt())
          : null,
    );
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
      debugPrint('[PushMode] 未匹配到 url=$url / title=$title，使用默认从第 0 集开始');
      return;
    }

    debugPrint(
      '[PushMode] 定位成功: source=$foundSourceIdx, episode=$foundEpisodeIdx',
    );

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

            // ===== 优先：从历史恢复播放 =====
            if (_resumeInfo != null && _resumeInfo!.hasData) {
              final resume = _resumeInfo!;
              _resumeInfo = null; // 只消费一次
              await _playWithResume(detail, resume);
              return;
            }

            final firstEpisode = firstSource.episodes.first;
            // 网盘推送和磁力推送共用手动/自动推送模式。
            if (checkAndHandlePushEpisode(firstEpisode, sourceIndex: 0)) {
              return;
            }

            final bool autoPlay =
                _pipRestoreAutoPlay || PlayerPref.autoPlayEnable;

            // 非推送链接：根据自动播放开关决定是否自动播放
            if (autoPlay) {
              _showPlayLoading();
            }
            try {
              await _playEpisode(
                firstEpisode,
                sourceIndex: 0,
                episodeIndex: 0,
                autoPlay: autoPlay,
              );
            } finally {
              // 兜底关闭"获取播放信息"弹窗。
              SmartDialog.dismiss(tag: 'play_loading', force: true);
            }
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

  /// 从历史恢复播放：定位到对应线路 + 集数 + 进度后播放
  ///
  /// 匹配策略（优先级从高到低）：
  ///   1. source_name / episode_name 名称匹配（防 line/episode 顺序变化）
  ///   2. source_index / episode_index 索引匹配
  ///   3. 缺失时回退到 0
  ///
  /// 保证：任一字段缺失/匹配失败都不会抛异常，
  /// 最坏情况等价于"从第 1 集从头播"。
  Future<void> _playWithResume(VideoDetail detail, _ResumeInfo resume) async {
    if (detail.playSources.isEmpty) {
      isLoadingDetail.value = false;
      return;
    }

    // ---- 1. 定位线路 ----
    int sourceIdx = resume.sourceIndex ?? 0;
    if (resume.sourceName != null && resume.sourceName!.isNotEmpty) {
      final found = detail.playSources.indexWhere(
        (s) => s.name == resume.sourceName,
      );
      if (found >= 0) sourceIdx = found;
    }
    sourceIdx = sourceIdx.clamp(0, detail.playSources.length - 1);

    final source = detail.playSources[sourceIdx];
    if (source.episodes.isEmpty) {
      isLoadingDetail.value = false;
      return;
    }

    // ---- 2. 定位集数 ----
    int epIdx = resume.episodeIndex ?? 0;
    if (resume.episodeName != null && resume.episodeName!.isNotEmpty) {
      final found = source.episodes.indexWhere(
        (e) => e.name == resume.episodeName,
      );
      if (found >= 0) epIdx = found;
    }
    epIdx = epIdx.clamp(0, source.episodes.length - 1);

    final episode = source.episodes[epIdx];
    final bool autoPlay = _pipRestoreAutoPlay || PlayerPref.autoPlayEnable;

    // ---- 3. 同步 UI / 状态索引 ----
    introController.switchDisplaySource(sourceIdx);
    introController.switchPlaySource(sourceIdx);
    introController.switchEpisode(epIdx);

    if (checkAndHandlePushEpisode(episode, sourceIndex: sourceIdx)) {
      isLoadingDetail.value = false;
      if (MagnetUri.isMagnet(episode.url)) {
        this.autoPlay.value = false;
      }
      return;
    }

    // ---- 4. 播放 ----
    final posSec = resume.positionSeconds ?? 0;
    final seekTo = posSec > 0 ? Duration(seconds: posSec) : null;

    if (autoPlay) _showPlayLoading();
    try {
      await _playEpisode(
        episode,
        sourceIndex: sourceIdx,
        episodeIndex: epIdx,
        autoPlay: autoPlay,
        seekTo: seekTo,
      );
    } finally {
      SmartDialog.dismiss(tag: 'play_loading', force: true);
    }
    if (!autoPlay) isLoadingDetail.value = false;

    debugPrint(
      '[DetailController] 历史恢复完成: '
      'src=$sourceIdx/${detail.playSources.length}, '
      'ep=$epIdx/${source.episodes.length}, '
      'seek=${seekTo?.inSeconds}s',
    );
  }

  void _showPlayLoading() {
    // 先关闭可能残留的相同 tag 的加载对话框
    SmartDialog.dismiss(tag: 'play_loading', force: true);

    SmartDialog.show(
      tag: 'play_loading', // 唯一标识
      maskColor: Colors.black54,
      clickMaskDismiss: false,
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

  /// 检测并登记网盘或磁力推送。
  ///
  /// 返回 true 表示当前剧集已交给推送流程处理。手动模式只显示统一的“推送”
  /// 按钮；自动模式在下一帧进入对应的二次详情页。
  bool checkAndHandlePushEpisode(
    Episode episode, {
    int sourceIndex = 0,
    String? magnetOverride,
  }) {
    // 磁力详情页内部已经完成磁力分流，不能再把其中的 magnet/magnetplay
    // 当作外部推送内容，否则会显示无效的“推送”按钮。
    if (_isMagnetDetailMode) {
      showPushButton.value = false;
      pushVodId.value = '';
      _pendingMagnetPushEpisode = null;
      _pendingMagnetPushSourceIndex = 0;
      return false;
    }

    final url = episode.url;
    final magnet = magnetOverride ?? (MagnetUri.isMagnet(url) ? url : null);
    final isCloudPush = url.startsWith('push://');
    final isMagnetPush = MagnetUri.isMagnet(magnet);
    if (!isCloudPush && !isMagnetPush) {
      showPushButton.value = false;
      pushVodId.value = '';
      _pendingMagnetPushEpisode = null;
      _pendingMagnetPushSourceIndex = 0;
      return false;
    }

    // 与网盘推送保持一致：检测到推送内容时先暂停当前播放。
    if (playerController.playerStatus.value.isPlaying) {
      playerController.pause();
    }

    if (isMagnetPush) {
      pushVodId.value = '';
      _pendingMagnetPushEpisode = Episode(name: episode.name, url: magnet!);
      _pendingMagnetPushSourceIndex = sourceIndex;
    } else {
      _pendingMagnetPushEpisode = null;
      _pendingMagnetPushSourceIndex = 0;
      String rawVodId = url.substring(7);
      try {
        final decoded = Uri.decodeComponent(rawVodId);
        final encoded = Uri.encodeComponent(decoded);
        pushVodId.value = encoded;
      } catch (_) {
        pushVodId.value = Uri.encodeComponent(rawVodId);
      }
    }

    if (PlayerPref.pushMode == 1) {
      // 自动模式：直接调用 pushToDetail，不显示按钮，不显示 toast。
      showPushButton.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isClosed) {
          pushToDetail(showToast: false);
        }
      });
      return true;
    }

    showPushButton.value = true;
    SmartDialog.showToast('检测到推送链接，点击推送按钮进行播放');
    return true;
  }

  /// 执行推送跳转
  Future<void> pushToDetail({bool showToast = true}) async {
    if (_isMagnetDetailMode) return;

    final magnetEpisode = _pendingMagnetPushEpisode;
    if (magnetEpisode != null) {
      if (showToast) SmartDialog.showToast('正在跳转到推送详情...');
      await _openMagnetDetailForEpisode(
        magnetEpisode,
        sourceIndex: _pendingMagnetPushSourceIndex,
        autoPlay: true,
      );
      return;
    }

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

  /// 切集时的"立即反馈"：
  /// 暂停旧播放器并清空数据状态，让 UI 立即切到"加载中"。
  ///
  /// 注意（与旧实现的区别）：
  /// - 旧实现把 autoPlay 置 false，导致 video_page 显示"封面 + 播放按钮"，
  ///   但封面停留时间受网络影响（20ms~800ms），常出现"封面一闪而过"的闪烁；
  /// - 新实现保持 autoPlay 为 true，让视频区始终是"黑底 + 加载中"，
  ///   视觉上只有一次跳变（loading → 首帧），与专业播放器一致；
  /// - 失败时由 _handlePlayFailure 主动把 autoPlay 拉回 false，
  ///   从而显示封面 + 错误文字 + 重试按钮。
  Future<void> _switchToPendingState() async {
    // 清掉上一次的失败状态（含 autoPlay 之外的所有失败 UI）
    _clearPlayFailure();

    // 暂停当前播放器（不停源，只是静音停帧）
    try {
      if (playerController.playerStatus.value.isPlaying) {
        await playerController.pause();
      }
    } catch (_) {}

    // 清掉 dataStatus，让"正在加载"的 UI 从干净状态开始
    try {
      playerController.dataStatus.value = DataStatus.none;
    } catch (_) {}
  }

  /// 播放核心逻辑
  Future<void> _playEpisode(
    Episode episode, {
    required int sourceIndex,
    required int episodeIndex,
    bool autoPlay = true,
    Duration? seekTo,
  }) async {
    if (!_isMagnetDetailMode &&
        checkAndHandlePushEpisode(episode, sourceIndex: sourceIndex)) {
      return;
    }

    // 切集前停止录制
    _stopRecordingIfActive();

    // 每次开始新的播放尝试 → 清掉上一次的失败状态
    _clearPlayFailure();

    _danmakuLoaded = false;
    _currentEpisode = episode;
    _currentSourceIndex = sourceIndex;
    _currentEpisodeIndex = episodeIndex;

    isPlaying.value = false;
    showParserButton.value = false;

    if (MagnetUri.isMagnetSource(episode.url)) {
      if (!_isMagnetDetailMode) return;
      await _playMagnetSource(
        episode.url,
        fileNameHint: episode.name,
        autoPlay: autoPlay,
        seekTo: seekTo,
      );
      return;
    }

    // 直链推送模式：直接用 episode.url 播放，不走 _apiService
    // 适用于 Emby / AList 等外部来源，其 Episode.url 已是完整 HTTP 直链
    // if (_isDirectPushMode) {
    //   final directPlayUrl = PlayUrl(
    //     parse: 0,
    //     qualities: [PlayQuality(label: '直链', url: episode.url)],
    //     headers: _initHeaders, // ← 新增：透传 headers（null 时与原逻辑一致）
    //   );
    //   await _startPlay(directPlayUrl, autoPlay, seekTo: seekTo);
    //   return;
    // }

    if (_isDirectPushMode) {
      var playUrl = episode.url;
      // Web 源懒解析：url 非直链且有 resolver → 页面内实时解析
      if (!_isDirectMediaUrl(playUrl) && _webResolver != null) {
        try {
          final resolved = await _webResolver!(playUrl);
          if (resolved != null && resolved.isNotEmpty) {
            playUrl = resolved;
          } else {
            _handlePlayFailure('解析播放地址失败，请重试');
            return;
          }
        } catch (e) {
          _handlePlayFailure('解析异常: $e');
          return;
        }
      }
      final directPlayUrl = PlayUrl(
        parse: 0,
        qualities: [PlayQuality(label: '直链', url: playUrl)],
        headers: _initHeaders,
      );
      await _startPlay(directPlayUrl, autoPlay, seekTo: seekTo);
      return;
    }

    try {
      final source = introController.getSource(sourceIndex);
      if (source == null) {
        _handlePlayFailure('获取播放地址失败');
        return;
      }

      // 合并模式懒加载：
      //   episode.url 是 vodId，先请求详情 API 拿真实 play 参数和 flag，
      //   再走原有的 getPlayUrl 流程。
      String realPlayParams = episode.url;
      String realFlag = source.name;

      if (_isMergeListMode) {
        try {
          final realDetail = await _apiService.getDetail(
            vodId: episode.url,
            pwd: pwd,
          );
          if (realDetail == null || realDetail.playSources.isEmpty) {
            _handlePlayFailure('无法获取播放信息');
            return;
          }
          final firstSource = realDetail.playSources.first;
          if (firstSource.episodes.isEmpty) {
            _handlePlayFailure('无法获取播放信息');
            return;
          }
          realPlayParams = firstSource.episodes.first.url;
          realFlag = firstSource.name;
        } catch (e) {
          _handlePlayFailure('获取详情失败: $e');
          return;
        }
      }

      final playUrl = await _apiService.getPlayUrl(
        playParams: realPlayParams, // 用真实 play 参数
        flag: realFlag, // 用真实 flag
        pwd: pwd,
      );

      if (playUrl == null) {
        _handlePlayFailure('获取播放地址失败');
        return;
      }

      if (MagnetUri.isMagnetSource(playUrl.defaultUrl)) {
        if (!_isMagnetDetailMode) {
          checkAndHandlePushEpisode(
            episode,
            sourceIndex: sourceIndex,
            magnetOverride: playUrl.defaultUrl,
          );
          return;
        }
        await _playMagnetSource(
          playUrl.defaultUrl!,
          fileNameHint: episode.name,
          autoPlay: autoPlay,
          seekTo: seekTo,
        );
        return;
      }

      if (playUrl.needParser) {
        showParserButton.value = true;

        // 关闭残留弹窗
        SmartDialog.dismiss(force: true);

        // 显示解析弹窗（唯一 tag + 禁止点击遮罩关闭）
        const parserTag = 'parser_loading';
        SmartDialog.show(
          tag: parserTag,
          maskColor: Colors.black54,
          clickMaskDismiss: false,
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

        PlayUrl? result;
        try {
          result = await _parseWithAllParsers(
            playUrl,
            preferredParser: isManualParser.value ? currentParser.value : null,
          );
        } finally {
          // 只关闭本次解析弹窗，避免误伤其它层（如再上层的 WebView 弹窗）
          SmartDialog.dismiss(tag: parserTag, force: true);
        }

        if (result != null) {
          await _startPlay(result, autoPlay, seekTo: seekTo);
        } else {
          final msg = (isManualParser.value && currentParser.value != null)
              ? '${currentParser.value!.name} 解析失败'
              : '所有解析源均失败，请切换线路';
          _handlePlayFailure(msg);
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
          if (!sniffUrl.startsWith('http://') &&
              !sniffUrl.startsWith('https://')) {
            final apiBase = site?['api']?.toString() ?? '';
            if (apiBase.isNotEmpty) {
              final uri = Uri.parse(apiBase);
              final baseWithoutQuery = uri
                  .replace(query: '', fragment: '')
                  .toString();
              final baseUrl = baseWithoutQuery.endsWith('/')
                  ? baseWithoutQuery
                  : '$baseWithoutQuery/';
              final relativePath = sniffUrl.startsWith('/')
                  ? sniffUrl.substring(1)
                  : sniffUrl;
              sniffUrl = baseUrl + relativePath;
            } else {
              _handlePlayFailure('无法获取播放地址');
              return;
            }
          }
        }

        if (sniffUrl == null || sniffUrl.isEmpty) {
          _handlePlayFailure('嗅探URL无效');
          return;
        }

        const sniffTag = 'sniff_loading';
        SmartDialog.show(
          tag: sniffTag,
          maskColor: Colors.black54,
          clickMaskDismiss: false, // 禁止点遮罩关闭
          animationType: SmartAnimationType.scale,
          builder: (_) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  '正在嗅探播放地址...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        );

        String? sniffedUrl;
        try {
          sniffedUrl = await ResourceSniffer.sniff(
            url: sniffUrl,
            headers: playUrl.headers,
            script: playUrl.script,
            useWebView: true,
          );
        } finally {
          SmartDialog.dismiss(tag: sniffTag, force: true); // ← 只关这一个
        }

        if (isClosed) return;

        if (sniffedUrl != null) {
          final sniffedPlayUrl = PlayUrl(
            parse: 0,
            qualities: [PlayQuality(label: '嗅探', url: sniffedUrl)],
            headers: playUrl.headers,
          );
          await _startPlay(sniffedPlayUrl, autoPlay, seekTo: seekTo);
        } else {
          _handlePlayFailure('嗅探失败，请尝试其他方式');
        }
        return;
      }

      _handlePlayFailure('未知的播放类型');
    } catch (e, stackTrace) {
      // 保留原用户提示，仅补充日志便于排查（此前异常信息被完全吞掉）
      debugPrint('[DetailController] _playEpisode 异常: $e\n$stackTrace');
      _handlePlayFailure('获取播放地址失败');
    }
  }

  Future<void> _playMagnetSource(
    String source, {
    required String fileNameHint,
    required bool autoPlay,
    Duration? seekTo,
  }) async {
    if (!_isMagnetDetailMode &&
        !(_isDirectPushMode && MagnetUri.isMagnetPlay(source))) {
      return;
    }
    if (!await MagnetPluginGate.ensureReady()) return;
    const loadingTag = 'magnet_loading';
    SmartDialog.show(
      tag: loadingTag,
      maskColor: Colors.black54,
      clickMaskDismiss: false,
      backType: SmartBackType.block,
      animationType: SmartAnimationType.scale,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在准备磁力播放...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    try {
      final result = await MagnetPluginService.instance.resolveToStream(
        source: source,
        ownerTag: magnetOwnerTag,
        fileNameHint: fileNameHint,
      );
      if (isClosed) {
        await MagnetPluginService.instance.disposeOwner(
          magnetOwnerTag,
          deleteMedia: null,
        );
        return;
      }
      final playUrl = PlayUrl(
        parse: 0,
        qualities: [
          PlayQuality(label: '磁力', url: result.streamUrl),
        ],
        headers: const {},
      );
      await _startPlay(playUrl, autoPlay, seekTo: seekTo);
    } catch (e) {
      if (!isClosed) {
        _handlePlayFailure('磁力播放失败: ${e.toString()}');
      }
    } finally {
      SmartDialog.dismiss(tag: loadingTag, force: true);
    }
  }

  Future<PlayUrl?> _processWithParser(
    PlayUrl playUrl,
    ParserSource parser,
  ) async {
    try {
      final fullUrl =
          '${parser.url}${Uri.encodeComponent(playUrl.defaultUrl ?? '')}';

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
          final url =
              data['url']?.toString() ??
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
    // 注意：这里不能重置 _isHandlingCompletion。
    // 因为 _startPlay 可能由 _handlePlayCompleted → switchEpisode → _playEpisode
    // 调用，此时锁必须保持到 _handlePlayCompleted 的 finally 才释放。
    // 用户手动切集时，锁本来就已经是 false（上一次处理已完成），无需重置。

    // 确保所有残留弹窗被关闭
    SmartDialog.dismiss(force: true);

    this.autoPlay.value = autoPlay;

    String? defaultUrl = playUrl.defaultUrl;
    if (defaultUrl == null) {
      _handlePlayFailure('获取播放地址失败');
      return;
    }

    // ===== DASH 决策：强信号 > 显式声明 > 自动检测 =====
    // 优先级：
    //   1. audioUrl 非空 → 直接 DASH（无视 isDash，audioUrl 是强信号）
    //   2. isDash == 1   → 强制解析；失败报错（接口声明是 DASH 但不可解析 = 接口 bug）
    //   3. isDash == 0   → 明确跳过
    //   4. isDash == null → 白名单判断；命中则解析，失败降级直连
    String? resolvedAudioUrl = playUrl.audioUrl;
    if (resolvedAudioUrl != null && resolvedAudioUrl.isEmpty) {
      resolvedAudioUrl = null;
    }

    bool shouldParseMpd = false;
    bool strictDash = false; // isDash=1 时解析失败必须报错

    if (resolvedAudioUrl != null) {
      debugPrint('[DetailController] audioUrl 非空，直接 DASH 播放');
    } else {
      final dash = playUrl.isDash;
      if (dash == 1) {
        shouldParseMpd = true;
        strictDash = true;
        debugPrint('[DetailController] isDash=1，强制解析');
      } else if (dash == 0) {
        debugPrint('[DetailController] isDash=0，跳过 DASH 检测');
      } else {
        shouldParseMpd = MpdParser.looksLikeMpd(defaultUrl);
        if (shouldParseMpd) {
          debugPrint('[DetailController] isDash 未指定，白名单命中');
        }
      }
    }

    if (shouldParseMpd) {
      debugPrint('[DetailController] MPD 候选: $defaultUrl');
      final mpdInfo = await MpdParser.parse(
        defaultUrl,
        headers: playUrl.headers,
      );
      if (mpdInfo != null) {
        defaultUrl = mpdInfo.videoUrl;
        resolvedAudioUrl = mpdInfo.hasAudio ? mpdInfo.audioUrl : null;
        debugPrint(
          '[DetailController] MPD 解析成功: '
          'audio=${resolvedAudioUrl != null ? "有" : "无"}',
        );
      } else if (strictDash) {
        // isDash=1 但解析失败：接口明确声明是 DASH，解析不出来的情况
        // 属于数据错误，报错而非静默播放坏链接
        _handlePlayFailure('DASH 流解析失败，无法播放');
        return;
      } else {
        // 白名单命中但解析失败：降级直连（与旧逻辑一致）
        debugPrint('[DetailController] MPD 解析失败，降级直连');
      }
    }

    // ===== 根据策略处理请求头 =====
    Map<String, String> headers = playUrl.headers != null
        ? Map<String, String>.from(playUrl.headers!)
        : <String, String>{};

    // 清洗 header 值中的控制字符（\r \n \t 等），
    // HTTP 规范禁止 header 值包含裸 CR/LF，B 站 Cookie 偶带 \r
    headers = _sanitizeHeaders(headers);

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

    // UI / 投屏 / 第三方播放器用原始 URL + 记录 currentQuality
    currentPlayUrl.value = defaultUrl;
    currentQualities.value = playUrl.qualities;
    currentHeaders.value = headers;
    _currentPlayUrlIsDash = playUrl.isDash;
    _currentAudioUrl = resolvedAudioUrl;

    // currentQuality 按 label 匹配保留用户选择；匹配不上时重置为第一个
    if (playUrl.qualities.isNotEmpty) {
      final prevLabel = currentQuality.value?.label;
      PlayQuality? matched;
      if (prevLabel != null) {
        for (final q in playUrl.qualities) {
          if (q.label == prevLabel) {
            matched = q;
            break;
          }
        }
      }
      currentQuality.value = matched ?? playUrl.qualities.first;
    } else {
      currentQuality.value = null;
    }

    // 只有播放器数据源走代理（M3U8 + 开关开启时）
    final proxyUrl = _wrapUrlIfNeeded(defaultUrl, headers: headers);

    final dataSource = NetworkSource(
      videoSource: proxyUrl,
      audioSource: resolvedAudioUrl,
      headers: headers,
    );

    // 跳过窗口属于当前详情页状态，每次设置新数据源前同步到当前引擎。
    // 这样切集、重载以及切换播放内核后仍延续片头/片尾标记。
    playerController.skipStartDuration.value = skipStartDuration.value;
    playerController.skipEndDuration.value = skipEndDuration.value;

    final effectiveSeek = seekTo ?? Duration.zero;
    await playerController.setDataSource(
      dataSource,
      autoplay: autoPlay,
      seekTo: effectiveSeek,
      vodId: _currentEpisode?.name ?? '',
      autoFullScreenFlag: PlayerPref.autoEnterFullScreen,
    );

    // ===== 失败兜底 =====
    // 各引擎 setDataSource 内部吞掉异常，只把 dataStatus 置为 error。
    // 若不检查，会继续走 play() 且保持 autoPlay=true，
    // 导致手动 UI（含返回 / 主页 / 重试按钮）不显示，最终黑屏无法退出。
    if (playerController.dataStatus.value == DataStatus.error) {
      _handlePlayFailure('视频加载失败，请尝试切换线路或内核');
      return;
    }

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

    _addToHistory(initialPosition: effectiveSeek);

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

    // ===== AI 助手：记录当前播放上下文（不影响任何现有逻辑，异常静默） =====
    _recordPlaybackContext();
  }

  /// 记录当前播放上下文供 AI 工具读取（异常静默，不影响播放）
  void _recordPlaybackContext() {
    try {
      final detail = introController.videoDetail.value;
      final site = _currentSiteConfig ?? _sourceManager.currentSite.value;
      PlaybackContextRegistry.instance.set(
        PlaybackContext(
          vodId: vodId,
          vodName: detail?.vodName ?? '',
          episodeName: _currentEpisode?.name ?? '',
          siteKey: site?['key']?.toString() ?? '',
          siteName:
              site?['name']?.toString() ?? introController.sourceName.value,
          controllerTag: _tag ?? '',
        ),
      );
    } catch (e) {
      debugPrint('[DetailController] _recordPlaybackContext 失败: $e');
    }
  }

  /// 播放完成处理（根据播放顺序自动切换）
  Future<void> _handlePlayCompleted() async {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;
    try {
      final repeat = playerController.playRepeat;
      switch (repeat) {
        case PlayRepeat.singleCycle:
          await playerController.seekTo(Duration.zero);
          await playerController.play();
          break;
        case PlayRepeat.listOrder:
          final success = await playNext();
          if (!success) {
            // 地址解析或播放失败时已由 _handlePlayFailure 给出具体提示，
            // 不能再误报为“已经是最后一集”。
            if (playFailed.value) return;
            await playerController.pause();
            SmartDialog.showToast('已经是最后一集');
            // 确实无法继续播放时，按 autoExitFullscreen 退出全屏
            // （引擎层已经在 playRepeat == pause 时自动退出，这里补上
            //  listOrder 最后一集的边界场景）
            if (PlayerPref.autoExitFullscreen &&
                playerController.isFullScreen.value) {
              await playerController.triggerFullScreen(status: false);
            }
          }
          break;
        case PlayRepeat.listCycle:
          final success = await playNext();
          if (!success) {
            final episodes = introController.displayEpisodes;
            if (episodes.isNotEmpty) {
              await switchEpisode(0);
            } else {
              await playerController.pause();
              // 列表为空时（极端场景），按 autoExitFullscreen 退出全屏
              if (PlayerPref.autoExitFullscreen &&
                  playerController.isFullScreen.value) {
                await playerController.triggerFullScreen(status: false);
              }
            }
          }
          break;
        case PlayRepeat.pause:
          await playerController.pause();
          SmartDialog.showToast('播放已结束');
          // 退出全屏由引擎层处理（playRepeat == pause 分支）
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

  /// 移除 header 值中的 ASCII 控制字符（\r \n \t 等）
  /// HTTP 规范禁止 header 值包含裸 CR/LF，B 站等源偶尔会返回带 \r 的 Cookie
  Map<String, String> _sanitizeHeaders(Map<String, String>? raw) {
    if (raw == null) return {};
    final cleaned = <String, String>{};
    for (final e in raw.entries) {
      final v = e.value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (v.isNotEmpty) cleaned[e.key] = v;
    }
    return cleaned;
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
      'pikpak',
      'pan.quark',
      'aliyundrive',
      'yunpan',
      'xunlei',
      'weiyun',
      'baidu',
      '115.com',
      '123pan',
    ];
    return cloudDomains.any((d) => domain.contains(d));
  }

  // ===== 添加历史记录 =====
  void _addToHistory({Duration? initialPosition}) {
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

      // 当前线路名（PlaySource.name）
      final playSource = introController.getCurrentPlaySource();
      final lineName = playSource?.name ?? '';

      // 进度位置：优先 seekTo 目标值（setDataSource 返回时 position 可能未就绪），
      // 否则用当前 playerController.position
      Duration effectivePosition;
      if (initialPosition != null && initialPosition > Duration.zero) {
        effectivePosition = initialPosition;
      } else if (playerController.position > Duration.zero) {
        effectivePosition = playerController.position;
      } else {
        effectivePosition = Duration.zero;
      }
      final duration = playerController.duration.value;
      final progressStr = duration.inSeconds > 0
          ? '${_formatDuration(effectivePosition)} / ${_formatDuration(duration)}'
          : '00:00 / 00:00';
      final progressSeconds = effectivePosition.inSeconds;

      // 读取现有历史
      final existingHistory = GStorage.getHistory();

      // 查找是否存在相同 vod_id 且相同 api_url 的记录
      final existingIndex = existingHistory.indexWhere(
        (item) => item['vod_id'] == vodId && item['api_url'] == currentApiUrl,
      );

      if (existingIndex != -1) {
        // 同一源同一视频：更新
        final item = existingHistory[existingIndex];
        item['vod_remarks'] = episode.name;
        item['watchTime'] = DateTime.now().millisecondsSinceEpoch;
        item['progress'] = progressStr;
        item['progress_seconds'] = progressSeconds;
        item['episode_index'] = _currentEpisodeIndex;
        item['episode_name'] = episode.name;
        item['source_index'] = _currentSourceIndex;
        item['source_name'] = lineName;
        GStorage.saveHistory(existingHistory);
      } else {
        // 不同源：新增一条独立记录
        // ===== 拼装带源类型标签的显示名 =====
        final typeLabel = SourceManager.sourceTypeLabel(site);
        final typeName = typeLabel.isEmpty
            ? sourceName
            : '$sourceName ($typeLabel)';

        final historyItem = {
          'vod_id': vodId,
          'vod_name': detail.vodName,
          'vod_pic': detail.vodPic,
          'vod_remarks': episode.name,
          'vod_tag': detail.vodTag ?? '',
          'type_name': typeName,
          'api_url': currentApiUrl,
          'site_key': siteKey,
          'config_key': Get.find<SourceManager>().currentConfigKey.value,
          'progress': progressStr,
          'progress_seconds': progressSeconds,
          'watchTime': DateTime.now().millisecondsSinceEpoch,
          'detail_type': detailType,
          'episode_index': _currentEpisodeIndex,
          'episode_name': episode.name,
          'source_index': _currentSourceIndex,
          'source_name': lineName,
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
    _stopProgressUpdater(); // 先停止之前的
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

      final posStr = _formatDuration(position);
      final durStr = duration.inSeconds > 0
          ? _formatDuration(duration)
          : '--:--';
      final progress = '$posStr / $durStr';

      final historyList = GStorage.getHistory();

      // 与 _addToHistory 一致：vod_id + api_url 精确定位；
      // api_url 缺失时回退到 vod_id 匹配（保持原行为）。
      // 额外加了 detail.vodId 双匹配兜底：若构造时的 vodId 与 API 返回的
      // detail.vodId 不一致（少数源会出现），依然能命中同一条记录。
      final currentApiUrl = _currentSiteConfig?['api']?.toString() ?? '';
      int index = -1;
      if (currentApiUrl.isNotEmpty) {
        index = historyList.indexWhere(
          (item) => item['vod_id'] == vodId && item['api_url'] == currentApiUrl,
        );
        if (index == -1) {
          index = historyList.indexWhere(
            (item) =>
                item['vod_id'] == detail.vodId &&
                item['api_url'] == currentApiUrl,
          );
        }
      }
      if (index == -1) {
        index = historyList.indexWhere((item) => item['vod_id'] == vodId);
        if (index == -1) {
          index = historyList.indexWhere(
            (item) => item['vod_id'] == detail.vodId,
          );
        }
      }
      if (index == -1) return;

      final item = historyList[index];
      item['progress'] = progress;
      item['progress_seconds'] = position.inSeconds;
      item['episode_index'] = _currentEpisodeIndex;
      item['source_index'] = _currentSourceIndex;

      final ep = _currentEpisode;
      if (ep != null) {
        item['episode_name'] = ep.name;
        item['vod_remarks'] = ep.name;
      }
      final ps = introController.getCurrentPlaySource();
      if (ps != null) item['source_name'] = ps.name;

      GStorage.saveHistory(historyList);
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
    await _playEpisode(
      episode,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
      autoPlay: autoPlay,
    );
  }

  Future<void> switchQuality(PlayQuality quality) async {
    if (currentQuality.value?.url == quality.url) return;

    final position = playerController.position;

    // 复用当前播放已生效的 headers（首次播放已写入 currentHeaders）
    final headers = currentHeaders.value.isNotEmpty
        ? Map<String, String>.from(currentHeaders.value)
        : <String, String>{};

    // ===== DASH 决策树（与 _startPlay 保持一致） =====
    // 说明：PlayQuality 本身不带 audioUrl（audioUrl 属于 PlayUrl 视频级），
    //       所以这里不需要处理"audioUrl 非空优先"的分支。
    // 优先级：
    //   - isDash == 1   → 强制解析；失败报错
    //   - isDash == 0   → 跳过
    //   - isDash == null → 白名单判断；失败降级直连
    String videoUrl = quality.url;
    String? audioUrl;

    bool shouldParseMpd = false;
    bool strictDash = false;
    final dash = _currentPlayUrlIsDash;
    if (dash == 1) {
      shouldParseMpd = true;
      strictDash = true;
      debugPrint('[DetailController] 切画质 isDash=1，强制解析');
    } else if (dash == 0) {
      debugPrint('[DetailController] 切画质 isDash=0，跳过 DASH 检测');
    } else {
      shouldParseMpd = MpdParser.looksLikeMpd(quality.url);
      if (shouldParseMpd) {
        debugPrint('[DetailController] 切画质 isDash 未指定，白名单命中');
      }
    }

    if (shouldParseMpd) {
      final mpdInfo = await MpdParser.parse(
        quality.url,
        headers: headers.isEmpty ? null : headers,
      );
      if (mpdInfo == null) {
        SmartDialog.showToast(
          strictDash ? 'DASH 流解析失败' : '解析播放地址失败',
        );
        return;
      }
      videoUrl = mpdInfo.videoUrl;
      audioUrl = mpdInfo.hasAudio ? mpdInfo.audioUrl : null;
      debugPrint('[DetailController] 切画质 MPD 解析成功');
    }

    // 记录选中项与实际播放 URL（两者分离）
    currentQuality.value = quality;
    currentPlayUrl.value = videoUrl;
    _currentAudioUrl = audioUrl;

    try {
      playerController.skipStartDuration.value = skipStartDuration.value;
      playerController.skipEndDuration.value = skipEndDuration.value;

      final proxyUrl = _wrapUrlIfNeeded(
        videoUrl,
        headers: headers.isEmpty ? null : headers,
      );

      await playerController.setDataSource(
        NetworkSource(
          videoSource: proxyUrl,
          audioSource: audioUrl,
          headers: headers.isEmpty ? null : headers,
        ),
        autoplay: true,
        seekTo: position,
      );

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
    final episode = episodes[index];

    introController.switchPlaySource(displayIdx);
    introController.switchEpisode(index);

    if (checkAndHandlePushEpisode(episode, sourceIndex: displayIdx)) {
      return;
    }

    // 保留解析选择：切集沿用本详情页此前选定的解析站。
    // - 手动模式（isManualParser == true）继续用 currentParser；
    // - 自动模式（isManualParser == false）继续走自动（currentParser 为上次成功的源，
    //   但 isManualParser 为 false 时不会被当作 preferredParser，仍按 parseMode 走）。
    // 若手动模式下的解析站对当前集失败，由 _handlePlayFailure 提示，
    // 由用户主动切换，不自动回退

    // 切换剧集时重置为自动模式
    // isManualParser.value = false;

    // ===== 立即视觉反馈：先切到"封面 + 播放按钮"状态 =====
    // 让用户点击后立刻看到反应，而不是旧视频继续播几秒。
    await _switchToPendingState();

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
    if (checkAndHandlePushEpisode(
      episode,
      sourceIndex: introController.currentSourceIndex.value,
    )) {
      return true;
    }

    introController.switchEpisode(newIndex);

    // 上一集时重置为自动模式
    // isManualParser.value = false;

    // ===== 立即视觉反馈 =====
    await _switchToPendingState();

    await playEpisode(
      episode,
      sourceIndex: introController.currentSourceIndex.value,
      episodeIndex: newIndex,
    );
    return !playFailed.value;
  }

  Future<bool> playNext() async {
    final source = introController.getCurrentPlaySource();
    if (source == null) return false;
    final episodes = source.episodes;
    if (episodes.isEmpty) return false;

    int newIndex = introController.currentEpisodeIndex.value + 1;
    if (newIndex >= episodes.length) return false;

    final episode = episodes[newIndex];
    if (checkAndHandlePushEpisode(
      episode,
      sourceIndex: introController.currentSourceIndex.value,
    )) {
      return true;
    }

    introController.switchEpisode(newIndex);

    // 下一集时重置为自动模式
    // isManualParser.value = false;

    // ===== 立即视觉反馈 =====
    await _switchToPendingState();

    await playEpisode(
      episode,
      sourceIndex: introController.currentSourceIndex.value,
      episodeIndex: newIndex,
    );
    return !playFailed.value;
  }

  void toggleDanmaku() {
    playerController.toggleDanmaku();
  }

  void setIosPipSourceRectProvider(
    Map<String, int>? Function()? provider,
  ) {
    _iosPipSourceRectProvider = provider;
  }

  bool get canEnterIosPictureInPicture {
    if (!Platform.isIOS || currentPlayUrl.value.isEmpty) return false;
    return playerController.dataStatus.value == DataStatus.loaded;
  }

  bool _isAvPlayerCandidateUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme == 'file') return true;
    if (uri.scheme == 'http' || uri.scheme == 'https') return true;
    return File(value).existsSync();
  }

  Future<bool> enterIosPictureInPicture() async {
    if (!Platform.isIOS) return false;
    if (!canEnterIosPictureInPicture) {
      SmartDialog.showToast('视频尚未加载完成，请稍后再试');
      return false;
    }
    if (!IosPipHelper.instance.isSupported.value) {
      await IosPipHelper.instance.refreshStatus();
    }
    if (!IosPipHelper.instance.isSupported.value) {
      SmartDialog.showToast('当前设备或系统不支持画中画');
      return false;
    }

    final wasPlaying = playerController.playerStatus.value.isPlaying;
    final position = playerController.position;
    _iosPipWasPlaying = wasPlaying;
    _iosPipOriginalEpisodeIndex = _currentEpisodeIndex;

    if (wasPlaying) {
      await playerController.pause();
    }
    isPlaying.value = false;
    SmartDialog.showToast('正在启动画中画...');

    final rect = _iosPipSourceRectProvider?.call();
    final videoWidth = playerController.videoWidth.value;
    final videoHeight = playerController.videoHeight.value;
    final pipHeaders = Map<String, String>.from(currentHeaders.value);
    final pipUrl = _wrapUrlIfNeeded(
      currentPlayUrl.value,
      headers: pipHeaders,
    );
    final sourceSnapshot = introController.getCurrentPlaySource();
    final detailSnapshot = introController.videoDetail.value;
    final siteSnapshot = _currentSiteConfig ?? _sourceManager.currentSite.value;
    final result = await IosPipHelper.instance.enter(
      tag: _tag ?? 'detail',
      url: pipUrl,
      headers: pipHeaders,
      positionMs: position.inMilliseconds,
      speed: playerController.playbackSpeed,
      episodeIndex: _currentEpisodeIndex,
      title: introController.videoDetail.value?.vodName,
      width: videoWidth > 0 ? videoWidth : null,
      height: videoHeight > 0 ? videoHeight : null,
      sourceRect: rect,
      restoreArguments: (positionMs) => _buildIosPipRestoreArguments(
        positionMs,
        source: sourceSnapshot,
        detail: detailSnapshot,
        site: siteSnapshot,
      ),
      resolveNext: (index) => _resolveIosPipEpisode(index, sourceSnapshot),
      nextEpisodeIndex: (index) => _nextIosPipEpisodeIndex(
        index,
        sourceSnapshot,
      ),
      onEpisodeAdvanced: (index) =>
          _applyIosPipEpisodeAdvanced(index, sourceSnapshot),
      onRestoreCurrent: _restoreIosPipCurrent,
      onStatusChanged: _handleIosPipStatusChanged,
    );

    if (!result.active && !result.requested) {
      if (wasPlaying) {
        await playerController.play();
        isPlaying.value = true;
      }
      if (result.error != null && result.error!.isNotEmpty) {
        SmartDialog.showToast(result.error!);
      }
      _iosPipOriginalEpisodeIndex = null;
      return false;
    }
    return true;
  }

  Future<void> stopIosPictureInPictureAndRestore() async {
    await IosPipHelper.instance.stop();
  }

  Future<void> _handleIosPipStatusChanged(
    bool active,
    String? error,
    int? positionMs,
  ) async {
    if (active || (error == null || error.isEmpty)) return;
    final lower = error.toLowerCase();
    final message =
        lower.contains('could not be completed') ||
            lower.contains('cannot be completed')
        ? '当前视频暂不支持在画中画中播放'
        : error;
    SmartDialog.showToast(message);
    _iosPipOriginalEpisodeIndex = null;
    if (_iosPipWasPlaying && !isClosed) {
      await playerController.play();
      isPlaying.value = true;
    }
  }

  Map<String, dynamic> _buildIosPipRestoreArguments(
    int positionMs, {
    required PlaySource? source,
    required VideoDetail? detail,
    required Map<String, dynamic>? site,
  }) {
    final episode = _currentEpisode;
    if (_isDirectPushMode) {
      return <String, dynamic>{
        'isPush': true,
        'directUrl': episode?.url ?? currentPlayUrl.value,
        'directTitle': episode?.name ?? detail?.vodName ?? '画中画播放',
        'videoDetail': detail,
        if (_initHeaders != null) 'headers': _initHeaders,
        'resumePositionSeconds': positionMs ~/ 1000,
        'pipRestoreAutoPlay': true,
      };
    }

    if (_isMergeListMode) {
      return <String, dynamic>{
        'mergeDetail': detail,
        'mergeStartVodId': episode?.url ?? '',
        'vodId': vodId,
        'pwd': pwd,
        if (site != null) 'site': site,
        'resumePositionSeconds': positionMs ~/ 1000,
        'pipRestoreAutoPlay': true,
      };
    }

    return <String, dynamic>{
      'vodId': vodId,
      'pwd': pwd,
      if (site != null) 'site': site,
      'resumeEpisodeIndex': _currentEpisodeIndex,
      'resumeSourceIndex': _currentSourceIndex,
      if (source != null) 'resumeSourceName': source.name,
      if (episode != null) 'resumeEpisodeName': episode.name,
      'resumePositionSeconds': positionMs ~/ 1000,
      'pipRestoreAutoPlay': true,
    };
  }

  void _applyIosPipEpisodeAdvanced(int index, PlaySource? source) {
    if (index < 0) return;
    if (source == null || index >= source.episodes.length) return;
    if (introController.videoDetail.value != null) {
      introController.switchEpisode(index);
    }
    _currentEpisodeIndex = index;
    _currentEpisode = source.episodes[index];
    _currentSourceIndex = introController.currentSourceIndex.value;
  }

  Future<void> _restoreIosPipCurrent(
    int positionMs,
    int episodeIndex,
  ) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final appVisible =
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    final resumePlayback = _iosPipWasPlaying && appVisible;
    final advanced =
        _iosPipOriginalEpisodeIndex != null &&
        _iosPipOriginalEpisodeIndex != episodeIndex;
    _iosPipOriginalEpisodeIndex = null;
    _pipRestoreAutoPlay = false;
    if (advanced) {
      final source = introController.getCurrentPlaySource();
      if (source != null &&
          episodeIndex >= 0 &&
          episodeIndex < source.episodes.length) {
        final episode = source.episodes[episodeIndex];
        if (checkAndHandlePushEpisode(
          episode,
          sourceIndex: introController.currentSourceIndex.value,
        )) {
          return;
        }
        introController.switchEpisode(episodeIndex);
        await _playEpisode(
          episode,
          sourceIndex: introController.currentSourceIndex.value,
          episodeIndex: episodeIndex,
          autoPlay: resumePlayback,
          seekTo: Duration(milliseconds: positionMs),
        );
      }
      return;
    }

    if (positionMs > 0) {
      await playerController.seekTo(
        Duration(milliseconds: positionMs),
        isSeek: false,
      );
    }
    if (resumePlayback) {
      await playerController.play();
      isPlaying.value = true;
    }
  }

  Future<IosPipMedia?> _resolveIosPipEpisode(
    int index,
    PlaySource? source,
  ) async {
    if (source == null || index < 0 || index >= source.episodes.length) {
      return null;
    }
    final episode = source.episodes[index];

    if (_isDirectPushMode) {
      var mediaUrl = episode.url;
      if (!_isDirectMediaUrl(mediaUrl) && _webResolver != null) {
        final resolved = await _webResolver!(mediaUrl);
        if (resolved == null || resolved.isEmpty) return null;
        mediaUrl = resolved;
      }
      if (!_isAvPlayerCandidateUrl(mediaUrl)) return null;
      return IosPipMedia(
        url: mediaUrl,
        headers: Map<String, String>.from(
          _initHeaders ?? const <String, String>{},
        ),
        episodeIndex: index,
        episodeName: episode.name,
      );
    }

    String playParams = episode.url;
    String flag = source.name;
    if (_isMergeListMode) {
      final detail = await _apiService.getDetail(
        vodId: episode.url,
        pwd: pwd,
      );
      if (detail == null ||
          detail.playSources.isEmpty ||
          detail.playSources.first.episodes.isEmpty) {
        return null;
      }
      playParams = detail.playSources.first.episodes.first.url;
      flag = detail.playSources.first.name;
    }

    final playUrl = await _apiService.getPlayUrl(
      playParams: playParams,
      flag: flag,
      pwd: pwd,
    );
    if (playUrl == null ||
        playUrl.needParser ||
        playUrl.needSniff ||
        playUrl.defaultUrl == null) {
      return null;
    }
    if (playUrl.isDash == 1 ||
        (playUrl.audioUrl != null && playUrl.audioUrl!.isNotEmpty) ||
        MpdParser.looksLikeMpd(playUrl.defaultUrl!) ||
        !_isAvPlayerCandidateUrl(playUrl.defaultUrl!)) {
      return null;
    }

    final headers = _prepareIosPipHeaders(
      playUrl,
      playUrl.defaultUrl!,
    );
    final url = _wrapUrlIfNeeded(
      playUrl.defaultUrl!,
      headers: headers,
    );
    return IosPipMedia(
      url: url,
      headers: headers,
      episodeIndex: index,
      episodeName: episode.name,
    );
  }

  int? _nextIosPipEpisodeIndex(int index, PlaySource? source) {
    if (source == null || source.episodes.isEmpty) return null;
    switch (playerController.playRepeat) {
      case PlayRepeat.singleCycle:
        return index;
      case PlayRepeat.listOrder:
        final next = index + 1;
        return next < source.episodes.length ? next : null;
      case PlayRepeat.listCycle:
        return (index + 1) % source.episodes.length;
      case PlayRepeat.pause:
        return null;
    }
  }

  Map<String, String> _prepareIosPipHeaders(
    PlayUrl playUrl,
    String url,
  ) {
    var headers = _sanitizeHeaders(playUrl.headers);
    final strategy = PlayerPref.requestHeaderStrategy;
    if (strategy == 0 && headers.isEmpty) {
      final domain = _extractDomain(url);
      headers['User-Agent'] = _isCloudStorage(domain)
          ? BrowserUa.mob
          : BrowserUa.pc;
    } else if (strategy == 1) {
      headers['User-Agent'] = BrowserUa.pc;
    } else if (strategy == 2) {
      final accept = headers['Accept'] ?? '*/*';
      headers = <String, String>{'Accept': accept};
    }
    return headers;
  }

  /// 标记片头：当前播放位置在开头 180 秒内合法
  /// 返回 null 表示成功，返回 String 表示失败原因（用于 toast）
  String? markTipStart(Duration position) {
    if (position.inSeconds <= 0) {
      return '当前位置已在视频开头，无需标记片头';
    }
    if (position > Duration(seconds: tipMarkToleranceSeconds)) {
      return '片头仅支持 ${tipMarkToleranceSeconds} 秒内标记';
    }
    skipStartDuration.value = position.inSeconds;
    playerController.skipStartDuration.value = position.inSeconds;
    return null;
  }

  /// 标记片尾：当前播放位置在末尾 180 秒内合法
  /// 总时长未知或标记剩余不足 1 秒时无法生效，直接拒绝
  String? markTipEnd(Duration position, Duration total) {
    if (total <= Duration.zero) {
      return '视频总时长未知，暂不能标记片尾';
    }
    if (position < total - Duration(seconds: tipMarkToleranceSeconds)) {
      return '片尾仅支持最后 ${tipMarkToleranceSeconds} 秒内标记';
    }
    final remaining = total > position ? total - position : Duration.zero;
    if (remaining.inSeconds <= 0) {
      return '当前位置已在视频末尾，无需标记片尾';
    }
    skipEndDuration.value = remaining.inSeconds;
    playerController.skipEndDuration.value = remaining.inSeconds;
    return null;
  }

  /// 清除片头标记
  void clearTipStart() {
    skipStartDuration.value = 0;
    playerController.skipStartDuration.value = 0;
  }

  /// 清除片尾标记
  void clearTipEnd() {
    skipEndDuration.value = 0;
    playerController.skipEndDuration.value = 0;
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
    final headers = currentHeaders.value.isNotEmpty
        ? currentHeaders.value
        : null;

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
    final headers = currentHeaders.value.isNotEmpty
        ? currentHeaders.value
        : null;

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

  /// 缓存当前正在播放的视频
  ///
  /// 流程：
  /// 1. 校验当前剧集 / 播放地址
  /// 2. 弹出画质选择对话框（源影的 PlayUrl 通常带多个画质）
  /// 3. 构造 CacheEntry，加入 CacheService 队列
  /// 缓存当前正在播放的视频
  Future<void> cacheCurrentVideo() async {
    // 拦截本地文件
    final currentUrl = currentPlayUrl.value;
    if (currentUrl.isNotEmpty) {
      final isLocalFile =
          currentUrl.startsWith('file://') ||
          (Uri.tryParse(currentUrl)?.scheme == 'file') ||
          (File(currentUrl).existsSync());

      if (isLocalFile) {
        SmartDialog.showToast('本地文件不需要重复下载');
        return; // 直接返回，不执行后续的下载逻辑
      }
    }

    final detail = introController.videoDetail.value;
    if (detail == null) {
      SmartDialog.showToast('没有可缓存的视频');
      return;
    }

    final episode = introController.currentPlayEpisode;
    if (episode == null) {
      SmartDialog.showToast('没有正在播放的集数');
      return;
    }

    final qualities = currentQualities;
    if (qualities.isEmpty) {
      SmartDialog.showToast('没有可用的画质');
      return;
    }

    // ===== 选择画质 =====
    final selectedQuality = await showDialog<PlayQuality>(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: const Text('选择画质'),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: qualities.length,
            itemBuilder: (context, index) {
              final q = qualities[index];
              final isCurrent = currentPlayUrl.value == q.url;
              return ListTile(
                dense: true,
                title: Text(q.label),
                trailing: isCurrent
                    ? Text(
                        '当前播放',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : null,
                onTap: () => Navigator.pop(context, q),
              );
            },
          ),
        ),
      ),
    );
    if (selectedQuality == null) return;

    // ===== 请求头：直接复用播放器当前 headers =====
    // 播放器能播放成功，说明它手里的 headers 是有效的，
    // 下载时复用同一套即可避免 403 / 空响应。
    final headers = <String, String>{};
    final current = currentHeaders.value;
    if (current.isNotEmpty) {
      headers.addAll(current);
    }

    // 兜底：智能补充缺失的常见头
    if (!_hasHeader(headers, 'User-Agent')) {
      final domain = _extractDomain(selectedQuality.url);
      headers['User-Agent'] = _isCloudStorage(domain)
          ? BrowserUa.mob
          : BrowserUa.pc;
    }
    if (!_hasHeader(headers, 'Accept')) {
      headers['Accept'] = '*/*';
    }

    // ===== M3U8 走代理（与播放一致） =====
    final downloadUrl = _wrapUrlIfNeeded(
      selectedQuality.url,
      headers: headers.isEmpty ? null : headers,
    );

    final isM3u8 = selectedQuality.url.toLowerCase().contains('.m3u8');

    final entry = CacheEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}_${downloadUrl.hashCode.abs()}',
      vodId: vodId,
      vodName: detail.vodName,
      episodeName: episode.name,
      vodPic: detail.vodPic,
      qualityLabel: selectedQuality.label,
      url: downloadUrl,
      headers: headers.isEmpty ? null : headers,
      isM3u8: isM3u8,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final service = Get.find<CacheService>();
    if (service.isMigrating.value) {
      SmartDialog.showToast('正在迁移下载目录，请稍后再缓存');
      return;
    }
    try {
      await service.addDownload(entry);
      SmartDialog.showToast('已加入缓存队列');
    } catch (error) {
      SmartDialog.showToast('缓存失败：$error');
    }
  }

  /// 判断 headers 里是否存在某个 key（大小写不敏感）
  bool _hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    return headers.keys.any((k) => k.toLowerCase() == lower);
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
          headers: currentHeaders.value.isNotEmpty
              ? currentHeaders.value
              : null,
        );
        await playerController.setDataSource(
          NetworkSource(
            videoSource: proxyUrl,
            // 复用 _startPlay 解析出的 DASH 外挂音频直链（非 DASH 源为 null），
            // 避免重载后只剩视频流（无声）
            audioSource: _currentAudioUrl,
            headers: currentHeaders.value.isNotEmpty
                ? currentHeaders.value
                : null,
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
  ///
  /// [seekTo] 指定起始位置，若不传则从头开始。
  /// [autoPlay] 是否自动播放，默认 true。
  ///   切换内核时可传入切换前的播放状态，以保留用户「暂停中」的意图。
  Future<void> reloadCurrentEpisode({
    Duration? seekTo,
    bool autoPlay = true,
  }) async {
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
      autoPlay: autoPlay,
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
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
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
            position:
                Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  ),
                ),
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
    isManualParser.value = true; // 标记为手动模式

    if (_currentEpisode != null) {
      await _playEpisode(
        _currentEpisode!,
        sourceIndex: _currentSourceIndex,
        episodeIndex: _currentEpisodeIndex,
        autoPlay: true,
      );
    }
  }

  void _loadDanmakuOnPlay(
    String? originalDanmakuUrl,
    Map<String, String>? headers,
  ) {
    if (_danmakuLoaded) return; // 避免重复请求

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
      final items = await _danmakuParser.loadFromUrl(
        url,
        headers: _sanitizeHeaders(headers),
      );
      if (items.isNotEmpty && Get.isRegistered<DanmakuController>()) {
        final danmakuController = Get.find<DanmakuController>();
        danmakuController.loadDanmaku(items);
      }
    } catch (e) {}
  }

  @override
  void onClose() {
    IosPipHelper.instance.notifyPlayerDisposed(_tag ?? 'detail');

    // 停止录制
    if (playerController.isRecording.value) {
      stopRecording();
    }

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

    unawaited(
      MagnetPluginService.instance.disposeOwner(
        magnetOwnerTag,
        deleteMedia: null,
      ),
    );

    autoPlay.value = false;

    playerController.dispose();
    // _cleanTempSubtitleFiles();
    tabCtr.dispose();

    // 移除播放完成监听，防止内存泄漏
    if (_playCompletedListener != null) {
      playerController.removeStatusLister(_playCompletedListener!);
      _playCompletedListener = null;
    }

    // 清理字幕翻译进度
    translationProgress.value = null;

    // ===== AI 助手：清理播放上下文（仅当前 tag 匹配时清理，不影响多标签） =====
    try {
      PlaybackContextRegistry.instance.clearByTag(_tag);
    } catch (_) {}

    super.onClose();
  }

  // void toAudioPage() {
  //   final detail = introController.videoDetail.value;
  //   if (detail == null) return;

  //   final playlist = <AudioItem>[];
  //   for (final source in detail.playSources) {
  //     for (final episode in source.episodes) {
  //       playlist.add(AudioItem(
  //         title: episode.name,
  //         url: episode.url,
  //         artist: detail.vodName,
  //         cover: detail.vodPic,
  //       ));
  //     }
  //   }

  //   if (playlist.isEmpty) return;

  //   int index = 0;
  //   final currentEpisode = introController.currentPlayEpisode;
  //   if (currentEpisode != null) {
  //     for (int i = 0; i < playlist.length; i++) {
  //       if (playlist[i].title == currentEpisode.name) {
  //         index = i;
  //         break;
  //       }
  //     }
  //   }

  //   AudioPage.toAudioPage(
  //     playlist: playlist,
  //     index: index,
  //   );
  // }

  // ===== 内核切换 =====
  /// 切换内核防重入标志
  bool _isSwitchingEngine = false;

  /// 切换播放器内核（含 loading、进度/播放状态保留、reload 当前剧集）
  ///
  /// 供顶部栏 [HeaderControl] 与失败视图 [DetailPage._buildManualPlayerUI] 共用。
  ///
  /// [autoPlayOverride] 可选：控制切换后是否自动播放。
  /// - `null`（默认）：沿用切换前的播放状态（顶部栏行为）
  /// - `true`：强制自动播放（失败视图行为——用户点切换即期望能播放）
  /// - `false`：强制不播放
  ///
  /// 返回 `true` 表示切换流程完成（不代表新内核播放一定成功，
  /// 播放结果由 reloadCurrentEpisode 内部的失败处理决定）。
  Future<bool> switchPlayerEngine(
    PlayerEngineType newType, {
    bool? autoPlayOverride,
  }) async {
    // 防重入：避免用户快速连续点击或其它途径重复触发
    if (_isSwitchingEngine) return false;

    final current = PlayerPref.playerEngine;
    if (newType == current) {
      SmartDialog.showToast('已是当前内核');
      return false;
    }

    _isSwitchingEngine = true;
    SmartDialog.showLoading(msg: '切换内核中...');

    try {
      final wasFullScreen = playerController.isFullScreen.value;

      // 切换前抓取播放进度
      // 抓取时机：pause() 之前，此时 position 已稳定在用户看到的最后一帧
      final savedPosition = playerController.position;

      // 决定切换后是否自动播放：
      // - 未传 autoPlayOverride 时沿用当前播放状态（顶部栏切换语义）
      // - 传入时强制覆盖（失败视图传 true，让新内核尝试自动播放）
      final shouldAutoPlay =
          autoPlayOverride ?? playerController.playerStatus.value.isPlaying;

      // 暂停当前播放器
      if (playerController.playerStatus.value.isPlaying) {
        await playerController.pause();
      }

      // 重置数据状态，避免旧引擎的 loaded/error 残留影响新引擎
      playerController.dataStatus.value = DataStatus.none;

      // 只切换引擎，不恢复数据源
      // 切换完成后由下方 reloadCurrentEpisode 完整重载
      await playerController.switchEngine(
        newType,
        restoreData: false,
        restoreFullScreen: false,
      );

      // 关闭「切换内核中」loading，让后续重载的 loading 露出来
      SmartDialog.dismiss();

      // 传入切换前的进度和是否自动播放
      await reloadCurrentEpisode(
        seekTo: savedPosition,
        autoPlay: shouldAutoPlay,
      );

      // 通知详情页 Obx 重新收集 isFullScreen 依赖
      // （新引擎的 isFullScreen 默认值可能与旧引擎不同）
      engineSwitchNotifier.value++;

      // 数据源和页面均已使用新引擎重建，再恢复切换前的全屏状态。
      // 播放失败时不强行进入全屏，保留普通错误视图便于用户处理。
      if (wasFullScreen && !playFailed.value) {
        await WidgetsBinding.instance.endOfFrame;
        if (!isClosed) {
          await playerController.triggerFullScreen(
            status: true,
            isManualFS: false,
          );
        }
      }

      SmartDialog.showToast(
        '已切换到 ${newType == PlayerEngineType.fvp ? 'MDK' : 'MPV'} 内核',
      );
      return true;
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('切换失败: $e');
      return false;
    } finally {
      _isSwitchingEngine = false;
    }
  }

  Future<void> switchDecodeFormat(String format) async {
    PlayerPref.hardwareDecoding = format;
    await playerInit(showLoading: false);
    SmartDialog.showToast('已切换到 ${format.toUpperCase()} 解码');
  }

  /// 直链播放（跳过详情 API 请求）
  Future<void> _playDirect(String url, {Duration? seekTo}) async {
    if (MagnetUri.isMagnetSource(url)) {
      if (!_isMagnetDetailMode) {
        isLoadingDetail.value = false;
        autoPlay.value = false;
        if (MagnetUri.isMagnetPlay(url)) {
          await _playMagnetSource(
            url,
            fileNameHint:
                _currentDirectTitle ??
                introController.videoDetail.value?.vodName ??
                '磁力播放',
            autoPlay: true,
            seekTo: seekTo,
          );
          return;
        }
        final episode = _currentEpisode?.url == url
            ? _currentEpisode!
            : Episode(
                name:
                    _currentDirectTitle ??
                    MagnetUri.displayNameFromMagnet(url) ??
                    '磁力播放',
                url: url,
              );
        checkAndHandlePushEpisode(episode, sourceIndex: 0);
        return;
      }
      await _playMagnetSource(
        url,
        fileNameHint:
            _currentDirectTitle ??
            introController.videoDetail.value?.vodName ??
            '磁力播放',
        autoPlay: true,
        seekTo: seekTo,
      );
      return;
    }
    currentPlayUrl.value = url;
    currentQualities.value = [PlayQuality(label: '直链', url: url)];
    // 直链模式绕过了 getPlayUrl，不能沿用上一个源的 DASH 元数据。
    _currentPlayUrlIsDash = null;
    _currentAudioUrl = null;

    // 应用请求头
    final headers = _initHeaders ?? <String, String>{};
    currentHeaders.value = headers;

    final isLocalFile =
        url.startsWith('file://') ||
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
      // ===== 关键：提前关闭整页 loading 并切到播放态 =====
      // 原因：setDataSource 是 await 的，会一直等到 dataStatus 变成 loaded 才返回。
      // 若在此之后才关闭整页 loading，视频区启动时 dataStatus 已是 loaded，
      // dataStatus=loading 阶段被整页 loading 遮住，视频区的 loading overlay 永远看不到。
      // 因此必须在 setDataSource 之前就关闭整页 loading，让视频区先渲染，
      // 从而能捕获 setDataSource 里 dataStatus: none → loading → loaded 的完整变化。
      autoPlay.value = true;
      isLoadingDetail.value = false;

      await playerController.setDataSource(
        dataSource,
        autoplay: true,
        seekTo: seekTo,
        vodId: '直链播放',
      );

      // ===== 失败兜底 =====
      if (playerController.dataStatus.value == DataStatus.error) {
        autoPlay.value = false;
        detailError.value = '播放失败：视频加载失败';
        isLoadingDetail.value = false;
        return;
      }

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
    currentQuality.value = null;
    _currentPlayUrlIsDash = null;
    _currentAudioUrl = null;
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
      // 顺序解析（保持原状）
      for (final parser in sources) {
        final result = await _processWithParser(playUrl, parser);
        if (result != null) {
          currentParser.value = parser;
          return result;
        }
      }
      return null;
    } else {
      // 并发解析：谁先成功用谁；全部失败才返回 null。
      final completer = Completer<PlayUrl?>();
      var remaining = sources.length;

      if (remaining == 0) {
        return null;
      }

      for (final parser in sources) {
        _processWithParser(playUrl, parser)
            .then((result) {
              if (result != null) {
                if (!completer.isCompleted) {
                  currentParser.value = parser;
                  completer.complete(result);
                }
              } else {
                remaining--;
                if (remaining == 0 && !completer.isCompleted) {
                  completer.complete(null);
                }
              }
            })
            .catchError((_) {
              // _processWithParser 内部已有 try-catch 兜底，实际不会抛。
              // 这里保留 catchError 是为了防止未来改动后出现未捕获异常导致
              // completer 永不完成（调用方挂起）。
              remaining--;
              if (remaining == 0 && !completer.isCompleted) {
                completer.complete(null);
              }
            });
      }

      return completer.future;
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
            position:
                Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  ),
                ),
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

    final uri = Uri.parse(normalized).replace(
      queryParameters: {
        'name': title,
        'episode': episode.toString(),
      },
    );
    return uri.toString();
  }

  /// 尝试从设置中配置的弹幕 API 加载弹幕，成功返回 true
  Future<bool> _loadDanmakuFromUserApi() async {
    // 1. 检查自动匹配开关
    final autoMatch =
        StorageManager.getSetting<bool>(SettingBoxKey.danmakuAutoMatch) ??
        false;
    if (!autoMatch) return false;

    // 2. 读取 API 列表和当前选中的 key
    final apisJson =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.danmakuApis) ??
        [];
    if (apisJson.isEmpty) {
      SmartDialog.showToast('未匹配到弹幕');
      return false;
    }
    final currentKey =
        StorageManager.getSetting<String>(SettingBoxKey.danmakuCurrentKey) ??
        '';
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
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          // 弹幕 API 无响应时快速失败，避免 loading 长时间转圈
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.statusCode != 200) {
        SmartDialog.showToast('未匹配到弹幕');
        return false;
      }

      final data = response.data;

      // 6.1 检查是否为候选列表格式
      if (data is List &&
          data.isNotEmpty &&
          data[0] is Map &&
          (data[0] as Map).containsKey('url')) {
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

  /// 根据用户选定的标题手动加载弹幕
  ///
  /// 作用域：**仅当前集生效**。
  /// 切换剧集后 `_startPlay` 会重置 `_danmakuLoaded` 并触发
  /// `_loadDanmakuOnPlay` → `_loadDanmakuFromUserApi`，使用视频原始 `vodName`
  /// 重新走自动匹配，手动选择的弹幕不会残留到下一集，也不影响自动匹配机制。
  ///
  /// 流程：
  ///   1. 读取当前选中的弹幕 API base（currentKey 失效时回退第一个）
  ///   2. 构造 /api/v2/fongmi/danmaku?name=title&episode=N 请求
  ///   3. 若返回候选列表（[{url:...}]）→ 取第一个 url 再下载
  ///      否则直接按弹幕内容解析
  ///
  /// 与 `_loadDanmakuFromUserApi` 区别：不检查 autoMatch 开关，
  /// 用调用方传入的 title，而不是当前视频名。
  Future<void> loadDanmakuByTitle(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      SmartDialog.showToast('标题为空');
      return;
    }

    // 1. 读取 API 配置
    final apisJson =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.danmakuApis) ??
        [];
    if (apisJson.isEmpty) {
      SmartDialog.showToast('未配置弹幕API，请先在弹幕设置中添加');
      return;
    }
    final currentKey =
        StorageManager.getSetting<String>(SettingBoxKey.danmakuCurrentKey) ??
        '';

    Map<String, dynamic>? apiMap;
    if (currentKey.isNotEmpty) {
      for (final item in apisJson) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          if (m['key'] == currentKey) {
            apiMap = m;
            break;
          }
        }
      }
    }
    // 兜底：currentKey 未落库时取第一个
    if (apiMap == null) {
      final first = apisJson.firstWhere(
        (e) => e is Map,
        orElse: () => null,
      );
      if (first is Map) apiMap = Map<String, dynamic>.from(first);
    }
    if (apiMap == null) {
      SmartDialog.showToast('未找到弹幕API配置');
      return;
    }

    final apiBase = apiMap['api']?.toString();
    if (apiBase == null || apiBase.isEmpty) {
      SmartDialog.showToast('弹幕API地址无效');
      return;
    }

    // 2. 构造 FongMi URL（使用当前集数）
    final episodeNumber = introController.currentEpisodeIndex.value + 1;
    final fongmiUrl = _buildFongmiUrl(apiBase, trimmed, episodeNumber);
    debugPrint(
      '[Danmaku] 手动加载: title=$trimmed, ep=$episodeNumber, url=$fongmiUrl',
    );

    // 3. loading（独立 tag，避免误关其它弹窗）
    const loadingTag = 'danmaku_manual_loading';
    SmartDialog.dismiss(tag: loadingTag, force: true);
    SmartDialog.show(
      tag: loadingTag,
      maskColor: Colors.black54,
      clickMaskDismiss: false,
      animationType: SmartAnimationType.scale,
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在加载弹幕...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );

    // 4. 请求 FongMi 接口
    try {
      final dio = Dio();
      final response = await dio.get(
        fongmiUrl,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          responseType: ResponseType.plain,
          // 弹幕 API 无响应时快速失败，避免 loading 长时间转圈
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (isClosed) return;
      SmartDialog.dismiss(tag: loadingTag, force: true);

      if (response.statusCode != 200) {
        SmartDialog.showToast('接口返回异常 (${response.statusCode})');
        return;
      }

      final raw = response.data;
      debugPrint('[Danmaku] FongMi 响应类型: ${raw.runtimeType}');

      // 4.1 候选列表 [{url: ...}] → 取第一个 url
      String? actualUrl;
      if (raw is String && raw.trim().startsWith('[')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List &&
              decoded.isNotEmpty &&
              decoded[0] is Map &&
              (decoded[0] as Map).containsKey('url')) {
            actualUrl = decoded[0]['url']?.toString();
          }
        } catch (_) {}
      } else if (raw is List &&
          raw.isNotEmpty &&
          raw[0] is Map &&
          (raw[0] as Map).containsKey('url')) {
        actualUrl = raw[0]['url']?.toString();
      }

      final parser = DanmakuParser();
      final items = (actualUrl != null && actualUrl.isNotEmpty)
          ? await parser.loadFromUrl(actualUrl)
          : await parser.loadFromUrl(fongmiUrl);

      if (isClosed) return;

      if (items.isNotEmpty && Get.isRegistered<DanmakuController>()) {
        Get.find<DanmakuController>().loadDanmaku(items);

        // 弹幕开关关闭时主动提示，避免"应用了却看不到"的困惑
        if (!playerController.enableShowDanmaku.value) {
          SmartDialog.showToast(
            '已加载 ${items.length} 条，但弹幕开关已关闭，请手动打开',
          );
        } else {
          SmartDialog.showToast('已加载 ${items.length} 条弹幕（仅当前集）');
        }
      } else {
        SmartDialog.showToast('未找到该视频的弹幕');
      }
    } catch (e) {
      if (isClosed) return;
      SmartDialog.dismiss(tag: loadingTag, force: true);
      debugPrint('[Danmaku] 手动加载异常: $e');
      SmartDialog.showToast('加载弹幕失败：$e');
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/modules/music/controllers/music_player_controller.dart';
import 'package:yuanying/services/silence_keeper.dart';
import 'package:yuanying/utils/business_exception.dart';

enum NovelTtsEngine { system, network }

class NovelTtsVoice {
  final String id;
  final String name;
  final String contentType;
  final String url;

  const NovelTtsVoice({
    required this.id,
    required this.name,
    required this.contentType,
    required this.url,
  });

  factory NovelTtsVoice.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final url = json['url']?.toString().trim() ?? '';
    final rawId = json['id']?.toString().trim() ?? '';
    return NovelTtsVoice(
      id: rawId.isNotEmpty
          ? rawId
          : md5.convert(utf8.encode('$name|$url')).toString().substring(0, 12),
      name: name,
      contentType: json['contentType']?.toString().trim().isNotEmpty == true
          ? json['contentType'].toString().trim()
          : 'audio/mpeg',
      url: url,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'contentType': contentType,
    'url': url,
    'id': id,
  };
}

class RaTtsRemoteVoice {
  final String label;
  final String shortName;
  final String gender;
  final String locale;
  final String personalities;

  const RaTtsRemoteVoice({
    required this.label,
    required this.shortName,
    required this.gender,
    required this.locale,
    required this.personalities,
  });
}

class NovelTtsServiceStatus {
  final bool pluginInstalled;
  final bool pluginEnabled;
  final bool serviceConfigured;
  final bool running;
  final int port;
  final String baseUrl;
  final String? message;

  const NovelTtsServiceStatus({
    required this.pluginInstalled,
    required this.pluginEnabled,
    required this.serviceConfigured,
    required this.running,
    required this.port,
    required this.baseUrl,
    this.message,
  });
}

class NovelTtsImportResult {
  final int added;
  final int skipped;

  const NovelTtsImportResult({
    required this.added,
    required this.skipped,
  });
}

class NovelTtsService extends GetxService {
  static const String raTtsPluginId = 'ra-tts';
  static const String raTtsServiceId = 'svc-mkt-ra-tts';
  static const int raTtsDefaultPort = 38080;
  static const String unsupportedPlatformMessage =
      '在线朗读仅支持 Android 和 Windows，当前平台不支持';

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _networkPlayer = AudioPlayer();
  bool _inited = false;
  double rate = 0.5;
  double networkRate = 1.0;
  String? _voiceKey;
  NovelTtsEngine engine = NovelTtsEngine.system;
  List<NovelTtsVoice> _networkVoices = [];
  String? _networkVoiceId;
  int _networkVoiceRevision = 0;
  Future<void> _engineSwitchQueue = Future.value();
  Future<void>? _activeStop;
  bool _systemPlaybackActive = false;
  bool _networkPlaybackActive = false;

  @override
  void onInit() {
    super.onInit();
    rate = StorageManager.getSetting<double>(SettingBoxKey.ttsRate) ?? 0.5;
    _voiceKey = StorageManager.getSetting<String>(SettingBoxKey.ttsVoiceKey);
    engine =
        isSupportedPlatform &&
            StorageManager.getSetting<String>(SettingBoxKey.ttsEngine) ==
                'network'
        ? NovelTtsEngine.network
        : NovelTtsEngine.system;
    networkRate =
        StorageManager.getSetting<double>(SettingBoxKey.ttsNetworkRate) ?? 1.0;
    _networkVoiceId = StorageManager.getSetting<String>(
      SettingBoxKey.ttsNetworkVoiceId,
    );
    final rawVoices =
        StorageManager.getSetting<List<dynamic>>(
          SettingBoxKey.ttsNetworkVoices,
        ) ??
        const [];
    _networkVoices = rawVoices
        .whereType<Map>()
        .map((item) => NovelTtsVoice.fromJson(Map<String, dynamic>.from(item)))
        .where(_isValidVoice)
        .toList();
    if (_networkVoices.isNotEmpty &&
        !_networkVoices.any((voice) => voice.id == _networkVoiceId)) {
      _networkVoiceId = _networkVoices.first.id;
    }
    _init();
  }

  @override
  void onClose() {
    _networkPlayer.dispose();
    super.onClose();
  }

  Future<void> _init() async {
    if (_inited) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      if (_voiceKey != null) await _applyVoice(_voiceKey!);
      _inited = true;
    } catch (_) {}
  }

  Future<void> _applyVoice(String key) async {
    final parts = key.split('|');
    if (parts.length == 2) {
      await _tts.setVoice({'name': parts[0], 'locale': parts[1]});
    }
  }

  List<NovelTtsVoice> get networkVoices =>
      List<NovelTtsVoice>.unmodifiable(_networkVoices);

  String? get networkVoiceId => _networkVoiceId;
  int get networkVoiceRevision => _networkVoiceRevision;

  NovelTtsVoice? get currentNetworkVoice {
    for (final voice in _networkVoices) {
      if (voice.id == _networkVoiceId) return voice;
    }
    return null;
  }

  Future<void> setEngine(
    NovelTtsEngine value, {
    bool stopPlayback = true,
  }) {
    final operation = _engineSwitchQueue.then((_) async {
      if (engine == value) return;
      if (value == NovelTtsEngine.network && !isSupportedPlatform) {
        throw const BusinessException(unsupportedPlatformMessage);
      }
      if (stopPlayback) await stop();
      engine = value;
      await StorageManager.setSetting(
        SettingBoxKey.ttsEngine,
        value == NovelTtsEngine.network ? 'network' : 'system',
      );
    });
    _engineSwitchQueue = operation.then<void>(
      (_) {},
      onError: (_, _) {},
    );
    return operation;
  }

  Future<void> setNetworkRate(double value) async {
    networkRate = value.clamp(0.5, 2.0);
    await StorageManager.setSetting(
      SettingBoxKey.ttsNetworkRate,
      networkRate,
    );
  }

  Future<void> setNetworkVoice(String id) async {
    if (!_networkVoices.any((voice) => voice.id == id)) return;
    if (_networkVoiceId == id) return;
    _networkVoiceId = id;
    _networkVoiceRevision++;
    await StorageManager.setSetting(
      SettingBoxKey.ttsNetworkVoiceId,
      id,
    );
  }

  Future<NovelTtsImportResult> importVoiceText(String text) {
    final parsed = _parseVoicePack(text);
    return addNetworkVoices(parsed);
  }

  Future<NovelTtsImportResult> importVoiceUrl(String url) async {
    final response = await HttpClientFactory.dio.get<dynamic>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final text = response.data?.toString() ?? '';
    if (text.trim().isEmpty) {
      throw const BusinessException('音色包 URL 返回内容为空');
    }
    return importVoiceText(text);
  }

  Future<NovelTtsImportResult> addNetworkVoices(
    List<NovelTtsVoice> voices,
  ) async {
    final ids = _networkVoices.map((voice) => voice.id).toSet();
    var added = 0;
    var skipped = 0;
    for (final voice in voices) {
      if (!_isValidVoice(voice) || !ids.add(voice.id)) {
        skipped++;
        continue;
      }
      _networkVoices.add(voice);
      added++;
    }
    if (added > 0) {
      _networkVoiceId ??= _networkVoices.first.id;
      _networkVoiceRevision++;
      await _saveNetworkVoices();
    }
    return NovelTtsImportResult(added: added, skipped: skipped);
  }

  Future<void> updateNetworkVoice(NovelTtsVoice voice) async {
    final index = _networkVoices.indexWhere((item) => item.id == voice.id);
    if (index < 0) throw const BusinessException('音色不存在');
    if (!_isValidVoice(voice)) {
      throw const BusinessException('音色 JSON 格式不正确');
    }
    _networkVoices[index] = voice;
    _networkVoiceRevision++;
    await _saveNetworkVoices();
  }

  Future<void> removeNetworkVoice(String id) async {
    _networkVoices.removeWhere((voice) => voice.id == id);
    if (_networkVoiceId == id) {
      _networkVoiceId = _networkVoices.isEmpty ? null : _networkVoices.first.id;
    }
    _networkVoiceRevision++;
    await _saveNetworkVoices();
  }

  NovelTtsVoice? parseSingleVoice(String text) {
    final voices = _parseVoicePack(text);
    return voices.length == 1 ? voices.first : null;
  }

  String buildVoiceUrl(
    NovelTtsVoice voice,
    String text, {
    double? speed,
  }) {
    final pct = (((speed ?? networkRate) - 1.0) * 100).round().clamp(-100, 100);
    return voice.url
        .replaceAll('{{speakText}}', Uri.encodeQueryComponent(text))
        .replaceAll('{{speakSpeedPct}}', '$pct');
  }

  Future<void> previewVoice(
    NovelTtsVoice voice,
    String text,
  ) async {
    if (!_isValidVoice(voice)) {
      throw const BusinessException('音色 URL 缺少 {{speakText}} 占位符');
    }
    await stop();
    await _stopMusicForTts();
    await _playNetworkToCompletion(url: buildVoiceUrl(voice, text));
  }

  /// Windows 的 just_audio_media_kit 中 play() 只表示“已发出播放指令”，
  /// 不会等待音频真正播放结束。必须监听 processingState，否则连续分句时
  /// 会立即 stop/setUrl，导致每一句都在真正播放前被中断。
  Future<bool> _playNetworkToCompletion({
    String? url,
    String? filePath,
    void Function()? onReady,
  }) async {
    assert(url != null || filePath != null);
    _networkPlaybackActive = true;
    try {
      if (filePath != null && filePath.isNotEmpty) {
        await _networkPlayer.setFilePath(filePath);
      } else {
        await _networkPlayer.setUrl(url!);
      }
      if (_networkPlayer.processingState == ProcessingState.completed) {
        return true;
      }

      final completed = Completer<bool?>();
      final subscription = _networkPlayer.processingStateStream.listen((state) {
        if (completed.isCompleted) return;
        if (state == ProcessingState.completed) {
          completed.complete(true);
        } else if (state == ProcessingState.idle) {
          completed.complete(false);
        }
      });
      try {
        await _networkPlayer.play();
        try {
          onReady?.call();
        } catch (_) {
          // 高亮/跟随失败不能中断音频播放链路。
        }
        final finished = await completed.future.timeout(
          const Duration(minutes: 3),
          onTimeout: () => null,
        );
        if (finished == null) {
          await _networkPlayer.stop();
        }
        return finished == true;
      } catch (_) {
        await _networkPlayer.stop();
        rethrow;
      } finally {
        await subscription.cancel();
      }
    } finally {
      _networkPlaybackActive = false;
    }
  }

  Future<File> _downloadTtsAudio(String url) async {
    final response = await HttpClientFactory.dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const BusinessException('朗读音频响应为空');
    }
    final dir = await getTemporaryDirectory();
    final name =
        '${md5.convert(utf8.encode(url))}'
        '_${DateTime.now().microsecondsSinceEpoch}';
    final file = File('${dir.path}${Platform.pathSeparator}tts_$name.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _deleteTtsFile(File? file) async {
    if (file == null) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<List<Map<String, String>>> voices() async {
    await _init();
    final list = <Map<String, String>>[];
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final m = {
              for (final e in item.entries) '${e.key}': '${e.value}',
            };
            list.add(m);
          }
        }
      }
    } catch (_) {}
    list.sort((a, b) {
      bool zh(Map<String, String> v) =>
          (v['locale'] ?? '').toLowerCase().startsWith('zh');
      if (zh(a) && !zh(b)) return -1;
      if (!zh(a) && zh(b)) return 1;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    return list;
  }

  Future<NovelTtsServiceStatus> raTtsStatus({
    bool probe = true,
  }) async {
    final plugin = InstallManager.instance.findInstalled(raTtsPluginId);
    final config = ServiceManager.instance.find(raTtsServiceId);
    final port = config?.port ?? raTtsDefaultPort;
    final baseUrl = 'http://127.0.0.1:$port';
    var running =
        config != null &&
        plugin?.enabled == true &&
        ServiceManager.instance.getStatus(raTtsServiceId) ==
            ServiceStatus.running;
    String? message = ServiceManager.instance.getLastError(raTtsServiceId);
    if (probe && running) {
      try {
        final response = await HttpClientFactory.dio.get<dynamic>(
          baseUrl,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 3),
            sendTimeout: const Duration(seconds: 3),
          ),
        );
        running =
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 400;
        if (!running) message = '服务探活失败（HTTP ${response.statusCode}）';
      } catch (e) {
        running = false;
        message = '无法连接 Edge 朗读 TTS：$e';
      }
    }
    return NovelTtsServiceStatus(
      pluginInstalled: plugin != null,
      pluginEnabled: plugin?.enabled == true,
      serviceConfigured: config != null,
      running: running,
      port: port,
      baseUrl: baseUrl,
      message: message,
    );
  }

  Future<NovelTtsServiceStatus> startRaTts() async {
    if (!isSupportedPlatform) {
      throw const BusinessException(unsupportedPlatformMessage);
    }
    final plugin = InstallManager.instance.findInstalled(raTtsPluginId);
    if (plugin == null) {
      throw const BusinessException('未安装 Edge 朗读 TTS，请前往插件中心安装');
    }
    if (!plugin.enabled) {
      throw const BusinessException('Edge 朗读 TTS 插件已关闭，请先在插件中心开启');
    }
    if (ServiceManager.instance.find(raTtsServiceId) == null) {
      throw const BusinessException('Edge 朗读 TTS 服务配置不存在，请重新安装插件');
    }
    await ServiceManager.instance.start(raTtsServiceId);
    return raTtsStatus();
  }

  Future<void> ensureRaTtsReady() async {
    if (!isSupportedPlatform) {
      throw const BusinessException(unsupportedPlatformMessage);
    }
    final status = await raTtsStatus();
    if (!status.pluginInstalled) {
      throw const BusinessException('未安装 Edge 朗读 TTS 插件，请前往插件中心安装');
    }
    if (!status.pluginEnabled) {
      throw const BusinessException('Edge 朗读 TTS 插件已关闭，请前往插件中心开启');
    }
    if (!status.serviceConfigured) {
      throw const BusinessException('Edge 朗读 TTS 服务配置缺失，请重新安装插件');
    }
    if (!status.running) {
      throw const BusinessException('Edge 朗读 TTS 服务未启动，请先启动服务');
    }
  }

  Future<List<RaTtsRemoteVoice>> fetchRaTtsVoices({
    String? baseUrl,
  }) async {
    if (!isSupportedPlatform) {
      throw const BusinessException(unsupportedPlatformMessage);
    }
    final status = await raTtsStatus();
    final root =
        (baseUrl?.trim().isNotEmpty == true ? baseUrl!.trim() : status.baseUrl)
            .replaceFirst(RegExp(r'/+$'), '');
    final response = await HttpClientFactory.dio.get<dynamic>(
      '$root/api/voices',
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final raw = response.data;
    if (raw is! List) {
      throw const BusinessException('音色服务返回格式错误');
    }
    return raw
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          final personalities = map['personalities'];
          return RaTtsRemoteVoice(
            label: map['label']?.toString() ?? '',
            shortName: map['shortName']?.toString() ?? '',
            gender: map['gender']?.toString() ?? '',
            locale: map['locale']?.toString() ?? '',
            personalities: personalities is List
                ? personalities.map((e) => e.toString()).join(' · ')
                : personalities?.toString() ?? '',
          );
        })
        .where((voice) => voice.shortName.isNotEmpty)
        .toList();
  }

  NovelTtsVoice createRaTtsVoice(
    RaTtsRemoteVoice voice, {
    String? baseUrl,
  }) {
    final root =
        (baseUrl?.trim().isNotEmpty == true
                ? baseUrl!.trim()
                : 'http://127.0.0.1:$raTtsDefaultPort')
            .replaceFirst(RegExp(r'/+$'), '');
    const knownNames = <String, String>{
      'zh-CN-XiaoxiaoNeural': '晓晓（女·温暖）',
      'zh-CN-YunjianNeural': '云健（男·浑厚）',
      'zh-CN-YunxiNeural': '云希（男·年轻）',
      'zh-CN-XiaoyiNeural': '晓伊（女·活泼）',
      'zh-CN-YunyangNeural': '云扬（男·专业）',
      'zh-CN-YunxiaNeural': '云夏（男·少年）',
    };
    final name =
        knownNames[voice.shortName] ??
        (voice.label.isNotEmpty ? voice.label : voice.shortName);
    return NovelTtsVoice(
      id: voice.shortName,
      name: name,
      contentType: 'audio/mpeg',
      url:
          '$root/api/text-to-speech?'
          'voice=${Uri.encodeQueryComponent(voice.shortName)}'
          '&rate={{speakSpeedPct}}&volume=100&pitch=0&text={{speakText}}',
    );
  }

  String? get voiceKey => _voiceKey;

  Future<void> setVoice(String key) async {
    _voiceKey = key;
    await StorageManager.setSetting(SettingBoxKey.ttsVoiceKey, key);
    if (_inited) {
      try {
        await _applyVoice(key);
      } catch (_) {}
    }
  }

  Future<void> setRate(double r) async {
    rate = r;
    await StorageManager.setSetting(SettingBoxKey.ttsRate, r);
    if (_inited) {
      try {
        await _tts.setSpeechRate(r);
      } catch (_) {}
    }
  }

  Future<void> speakChunks(
    List<String> chunks, {
    required bool Function() isCancelled,
    void Function(int index)? onChunk,
  }) async {
    // 主动停止音乐播放，避免 TTS 与音乐同时播放
    await _stopMusicForTts();

    if (engine == NovelTtsEngine.network) {
      Future<File> downloadChunk(String text) {
        final voice = currentNetworkVoice;
        if (voice == null) {
          throw const BusinessException('请先选择网络音色');
        }
        if (!_isValidVoice(voice)) {
          throw const BusinessException('音色 URL 缺少 {{speakText}} 占位符');
        }
        return _downloadTtsAudio(buildVoiceUrl(voice, text));
      }

      File? currentFile;
      Future<File>? nextDownload;
      try {
        if (chunks.isNotEmpty) {
          currentFile = await downloadChunk(chunks.first);
        }
        for (var i = 0; i < chunks.length; i++) {
          if (isCancelled()) break;
          final file = currentFile;
          if (file == null) break;
          if (i + 1 < chunks.length) {
            nextDownload = downloadChunk(chunks[i + 1]);
          }
          try {
            final finished = await _playNetworkToCompletion(
              filePath: file.path,
              onReady: () => onChunk?.call(i),
            );
            await _deleteTtsFile(file);
            currentFile = null;
            if (!finished) break;
          } on PlayerInterruptedException {
            if (isCancelled()) break;
            rethrow;
          }
          final pending = nextDownload;
          nextDownload = null;
          currentFile = pending == null ? null : await pending;
        }
      } finally {
        await _deleteTtsFile(currentFile);
        final pending = nextDownload;
        if (pending != null) {
          unawaited(
            pending.then(_deleteTtsFile).catchError((_) {}),
          );
        }
      }
      return;
    }

    await _init();
    await _networkPlayer.stop();
    for (int i = 0; i < chunks.length; i++) {
      if (isCancelled()) break;
      onChunk?.call(i);
      try {
        _systemPlaybackActive = true;
        await _tts.speak(chunks[i]);
      } catch (_) {
        break;
      } finally {
        _systemPlaybackActive = false;
      }
    }
  }

  /// TTS 开始前停止音乐
  ///
  /// 跨平台通用：Android/iOS/桌面端都需要避免 TTS 与音乐混合。
  Future<void> _stopMusicForTts() async {
    // 1. 停止音乐播放器
    if (Get.isRegistered<MusicPlayerController>()) {
      try {
        final musicController = Get.find<MusicPlayerController>();
        if (musicController.isPlaying) {
          await musicController.pause();
        }
      } catch (_) {}
    }
    // 2. 停止 iOS 静音保活引擎（Dart 封装已在非 iOS 平台 no-op）
    try {
      await SilenceKeeper.stop();
    } catch (_) {}
  }

  Future<void> stop() {
    final activeStop = _activeStop;
    if (activeStop != null) return activeStop;
    late final Future<void> tracked;
    tracked = _stopInternal().whenComplete(() {
      if (identical(_activeStop, tracked)) {
        _activeStop = null;
      }
    });
    _activeStop = tracked;
    return tracked;
  }

  Future<void> _stopInternal() async {
    if (_systemPlaybackActive) {
      try {
        await _tts.stop();
      } catch (_) {}
      _systemPlaybackActive = false;
    }
    if (_networkPlaybackActive) {
      try {
        await _networkPlayer.stop();
      } catch (_) {}
      _networkPlaybackActive = false;
    }
  }

  List<NovelTtsVoice> _parseVoicePack(String input) {
    var text = input.trim();
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1).trimLeft();
    }
    if (text.isEmpty) {
      throw const BusinessException('音色包内容为空');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      final items = <dynamic>[];
      for (final line in const LineSplitter().convert(text)) {
        final item = line.trim();
        if (item.isEmpty) continue;
        items.add(jsonDecode(item));
      }
      decoded = items;
    }

    final rawList = decoded is List ? decoded : [decoded];
    return rawList.whereType<Map>().map((item) {
      final voice = NovelTtsVoice.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (!_isValidVoice(voice)) {
        throw const BusinessException(
          '音色格式错误：name/url 不能为空，url 必须包含 {{speakText}}',
        );
      }
      return voice;
    }).toList();
  }

  bool _isValidVoice(NovelTtsVoice voice) {
    final uri = Uri.tryParse(voice.url);
    return voice.name.trim().isNotEmpty &&
        voice.id.trim().isNotEmpty &&
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        voice.url.contains('{{speakText}}');
  }

  Future<void> _saveNetworkVoices() async {
    await StorageManager.setSetting(
      SettingBoxKey.ttsNetworkVoices,
      _networkVoices.map((voice) => voice.toJson()).toList(),
    );
    await StorageManager.setSetting(
      SettingBoxKey.ttsNetworkVoiceId,
      _networkVoiceId,
    );
  }
}

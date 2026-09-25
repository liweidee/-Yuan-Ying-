import '../models/lx_music_model.dart';
import '../models/lx_script_model.dart';
import '../utils/lx_logger.dart';
import 'lx_js_engine.dart';

/// 洛雪音乐取播放地址服务
class LxMusicUrlService {
  LxMusicUrlService._();
  static final LxMusicUrlService instance = LxMusicUrlService._();

  final LxJsEngine _engine = LxJsEngine.instance;

  /// 最近一次成功取 URL 的实际音质
  String? lastUsedQuality;

  bool get isUserApiActive => _engine.isActive;
  LxScript? get currentScript => _engine.currentScript;

  bool supportsSource(String source) {
    if (!_engine.isActive) return false;
    return _engine.sources.containsKey(source);
  }

  /// 获取播放地址
  Future<String?> getMusicUrl({
    required LxMusic music,
    String quality = '320k',
  }) async {
    final source = music.source ?? 'kw';

    if (!_engine.isActive) {
      LxLogger.warn('未激活用户 API 源，无法获取播放地址');
      return null;
    }

    if (!_engine.sources.containsKey(source)) {
      LxLogger.warn('用户 API 源不支持音源: $source');
      return null;
    }

    final scriptActions =
        _engine.sources[source]?.actions ?? const <String>[];
    if (scriptActions.isNotEmpty && !scriptActions.contains('musicUrl')) {
      LxLogger.warn('脚本未声明支持 musicUrl ($source)，跳过');
      return null;
    }

    final actualQuality = pickQuality(source, music, quality);

    final apiId = _engine.currentScript?.id;
    if (apiId == null) {
      LxLogger.warn('用户 API 脚本为空');
      return null;
    }

    LxLogger.info('请求用户 API 获取播放地址 (source=$source, quality=$actualQuality)');
    var url = await _engine.getMusicUrl(
      apiId: apiId,
      music: music,
      quality: actualQuality,
    );

    if ((url == null || url.isEmpty) &&
        actualQuality != '128k' &&
        _engine.lastScriptError == null) {
      LxLogger.warn('$actualQuality 获取失败（无结果），尝试 128k 兜底');
      url = await _engine.getMusicUrl(
        apiId: apiId,
        music: music,
        quality: '128k',
      );
      if (url != null && url.isNotEmpty) {
        lastUsedQuality = '128k';
      }
    }

    if (url != null && url.isNotEmpty) {
      LxLogger.info('用户 API 获取 URL 成功: $url');
      lastUsedQuality = actualQuality;
      return url;
    }

    final lastErr = _engine.lastScriptError;
    LxLogger.error('用户 API 获取 URL 失败 (lastError=$lastErr)');
    if (lastErr != null) {
      throw LxMusicUrlException(lastErr,
          retryable: !LxMusicUrlException.isFatal(lastErr));
    }

    return null;
  }

  /// 音质预选
  String pickQuality(String source, LxMusic music, String preferred) {
    const order = ['flac24bit', 'flac', '320k', '192k', '128k'];
    final declared = _engine.sources[source]?.qualitys ?? const <String>[];
    final musicTypes =
        music.types?.map((t) => t.type).toSet() ?? const <String>{};

    final reqIdx = order.indexOf(preferred);
    if (reqIdx < 0) return '128k';
    for (var i = reqIdx; i < order.length; i++) {
      final q = order[i];
      if (musicTypes.isNotEmpty && !musicTypes.contains(q)) continue;
      if (declared.isNotEmpty && !declared.contains(q)) continue;
      return q;
    }
    for (var i = reqIdx; i < order.length; i++) {
      if (declared.contains(order[i])) return order[i];
    }
    return '128k';
  }

  /// 并行取 URL（独立临时运行时）
  Future<String?> getMusicUrlParallel({
    required LxMusic music,
    String quality = '320k',
  }) async {
    final source = music.source ?? 'kw';

    if (!_engine.isActive) return null;
    if (!_engine.sources.containsKey(source)) return null;

    final scriptActions =
        _engine.sources[source]?.actions ?? const <String>[];
    if (scriptActions.isNotEmpty && !scriptActions.contains('musicUrl')) {
      return null;
    }

    final apiId = _engine.currentScript?.id;
    if (apiId == null) return null;

    final actualQuality = pickQuality(source, music, quality);

    return _engine.getMusicUrlParallel(
      apiId: apiId,
      music: music,
      quality: actualQuality,
    );
  }

  /// 获取歌词
  Future<Map<String, String?>?> getLyric({
    required LxMusic music,
  }) async {
    if (!_engine.isActive) return null;

    final source = music.source ?? 'kw';
    final scriptActions = _engine.sources[source]?.actions;
    if (scriptActions == null || !scriptActions.contains('lyric')) {
      return null;
    }

    final apiId = _engine.currentScript?.id;
    if (apiId == null) return null;

    return _engine.getLyric(
      apiId: apiId,
      music: music,
    );
  }
}
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../plugin/pl_player/player_pref.dart';
import '../models/subtitle_entry.dart';
import 'azure_translation_engine.dart';
import 'baidu_translation_engine.dart';
import 'translation_engine.dart';

/// 字幕翻译调度服务：批量、节流、缓存。
///
/// 性能要点：
/// - 所有网络请求都在独立 Future 里执行，不阻塞主 isolate；
/// - 缓存读写走应用目录，单文件 < 500KB，写盘毫秒级；
/// - 进度回调只更新外部状态，不做任何重建操作。
class SubtitleTranslationService {
  SubtitleTranslationService._();
  static final SubtitleTranslationService instance =
      SubtitleTranslationService._();

  /// 根据 PlayerPref 构建当前翻译引擎。
  TranslationEngine getActiveEngine() {
    final provider = PlayerPref.subtitleTranslationProvider;
    switch (provider) {
      case 'azure':
        return AzureTranslationEngine(
          key: PlayerPref.subtitleTranslationAzureKey,
          region: PlayerPref.subtitleTranslationAzureRegion,
        );
      case 'baidu':
      default:
        return BaiduTranslationEngine(
          appId: PlayerPref.subtitleTranslationBaiduAppId,
          secretKey: PlayerPref.subtitleTranslationBaiduSecret,
          modelType: PlayerPref.subtitleTranslationBaiduModel,
        );
    }
  }

  /// 检测字幕是否已经是目标语言（主要针对中文字幕翻中文这种无意义场景）。
  ///
  /// 判定逻辑：
  ///  - 只处理中文目标（zh-Hans / zh-Hant），其它语言不做检测；
  ///  - 取前 20 条字幕采样，避免长视频全文扫描；
  ///  - 只统计"中文字符"与"英文字母"两类字符，标点、数字、空格、
  ///    日文假名都不参与，避免被无关字符干扰；
  ///  - 中文字符占"中文 + 英文字母"总数的比例 ≥ 0.7 时判定为已是中文。
  ///
  /// 阈值取 0.7 是为了：
  ///  - 挡住纯中文字幕（比例约 0.95~1.0）；
  ///  - 放过中英混排（比例约 0.5~0.7）；
  ///  - 放过日文字幕（汉字占比通常 0.3~0.5）。
  static bool looksLikeAlreadyTargetLang(
    List<SubtitleEntry> entries,
    String targetLang,
  ) {
    if (targetLang != 'zh-Hans' && targetLang != 'zh-Hant') return false;
    if (entries.isEmpty) return false;

    final sample = entries.length > 20 ? entries.sublist(0, 20) : entries;

    var cjkCount = 0;
    var letterCount = 0;

    for (final e in sample) {
      for (final rune in e.text.runes) {
        // 中日韩统一表意文字（基本区）
        if (rune >= 0x4E00 && rune <= 0x9FFF) {
          cjkCount++;
          letterCount++;
        }
        // ASCII 英文字母
        else if ((rune >= 0x41 && rune <= 0x5A) ||
            (rune >= 0x61 && rune <= 0x7A)) {
          letterCount++;
        }
      }
    }

    // 样本太小不做判定，避免误伤
    if (letterCount < 20) return false;

    return (cjkCount / letterCount) >= 0.7;
  }

  /// 检查配置是否就绪。
  ({bool ok, String? error}) checkConfiguration() {
    final engine = getActiveEngine();
    if (!engine.isConfigured) {
      return (ok: false, error: engine.configurationError);
    }
    return (ok: true, error: null);
  }

  /// 翻译整批字幕。
  ///
  /// 命中磁盘缓存时直接返回缓存，不会再请求网络。
  Future<List<SubtitleEntry>> translate({
    required String videoId,
    required int subtitleIndex,
    required List<SubtitleEntry> entries,
    required String targetLang,
    String? contextTitle,
    void Function(int done, int total)? onProgress,
  }) async {
    if (entries.isEmpty) return const [];

    final engine = getActiveEngine();
    if (!engine.isConfigured) {
      throw TranslationException(engine.configurationError ?? '翻译服务未配置');
    }

    // 读缓存（要求长度一致才复用，避免字幕内容变动后错位）
    final cached =
        await _loadCache(videoId, subtitleIndex, targetLang, engine.id);
    if (cached != null && cached.length == entries.length) {
      onProgress?.call(entries.length, entries.length);
      return cached;
    }

    final batchSize = engine.id == 'azure' ? 40 : 25;
    final delayMs = engine.id == 'azure' ? 150 : 1000;

    final total = entries.length;
    final results = <SubtitleEntry>[];

    for (var i = 0; i < total; i += batchSize) {
      final end = (i + batchSize > total) ? total : i + batchSize;
      final chunk = entries.sublist(i, end);
      final texts = chunk.map((e) => e.text).toList(growable: false);

      List<String> translated;
      var retry = 0;
      while (true) {
        try {
          translated = await engine.translateBatch(
            texts: texts,
            targetLanguage: targetLang,
            contextTitle: contextTitle,
          );
          break;
        } catch (e) {
          retry++;
          if (retry >= 2) rethrow;
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }

      for (var j = 0; j < chunk.length; j++) {
        final t = (j < translated.length) ? translated[j] : '';
        results.add(SubtitleEntry(
          start: chunk[j].start,
          end: chunk[j].end,
          text: chunk[j].text,
          translatedText: t.isNotEmpty ? t : null,
        ));
      }

      onProgress?.call(results.length, total);

      if (end < total && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    // 写缓存
    await _saveCache(videoId, subtitleIndex, targetLang, engine.id, results);

    return results;
  }

  // ---------------- 缓存 ----------------

  Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}subtitle_translation',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _cacheFileName(
    String videoId,
    int subtitleIndex,
    String targetLang,
    String engineId,
  ) {
    final safeId = videoId.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    final truncated = safeId.length > 64 ? safeId.substring(0, 64) : safeId;
    return '${truncated}_sub${subtitleIndex}_${targetLang}_$engineId.json';
  }

  Future<List<SubtitleEntry>?> _loadCache(
    String videoId,
    int subtitleIndex,
    String targetLang,
    String engineId,
  ) async {
    try {
      final dir = await _cacheDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${_cacheFileName(videoId, subtitleIndex, targetLang, engineId)}',
      );
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      final out = <SubtitleEntry>[];
      for (final item in list) {
        if (item is! Map) continue;
        final startMs = (item['startMs'] as num?)?.toInt() ?? 0;
        final endMs = (item['endMs'] as num?)?.toInt() ?? 0;
        final text = item['text']?.toString() ?? '';
        final tText = item['translatedText']?.toString();
        out.add(SubtitleEntry(
          start: Duration(milliseconds: startMs),
          end: Duration(milliseconds: endMs),
          text: text,
          translatedText: (tText != null && tText.isNotEmpty) ? tText : null,
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(
    String videoId,
    int subtitleIndex,
    String targetLang,
    String engineId,
    List<SubtitleEntry> entries,
  ) async {
    try {
      final dir = await _cacheDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${_cacheFileName(videoId, subtitleIndex, targetLang, engineId)}',
      );
      final list = entries
          .map((e) => <String, Object?>{
                'startMs': e.start.inMilliseconds,
                'endMs': e.end.inMilliseconds,
                'text': e.text,
                if (e.translatedText != null)
                  'translatedText': e.translatedText,
              })
          .toList(growable: false);
      await file.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  /// 清理全部翻译缓存，返回删除的文件数。
  Future<int> clearAllCache() async {
    try {
      final dir = await _cacheDir();
      var count = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            await entity.delete();
            count++;
          } catch (_) {}
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }
}
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'translation_engine.dart';

/// 百度翻译引擎（大模型 / 通用）。
class BaiduTranslationEngine implements TranslationEngine {
  BaiduTranslationEngine({
    required String appId,
    required String secretKey,
    this.modelType = 'llm',
  })  : appId = _clean(appId),
        secretKey = _clean(secretKey);

  final String appId;
  final String secretKey;

  /// 'llm' 大模型翻译（默认）| 'nmt' 通用机器翻译。
  final String modelType;

  static const String _nmtEndpoint =
      'https://fanyi-api.baidu.com/api/trans/vip/translate';
  static const String _llmEndpoint =
      'https://fanyi-api.baidu.com/ait/api/aiTextTranslate';

  static final Dio _dio = Dio();

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '');

  @override
  String get id => 'baidu';

  @override
  String get displayName =>
      modelType == 'llm' ? '百度翻译（大模型）' : '百度翻译（通用）';

  @override
  bool get isConfigured => appId.isNotEmpty && secretKey.isNotEmpty;

  @override
  String? get configurationError =>
      isConfigured ? null : '未配置百度翻译 APP ID 或密钥';

  /// 清洗视频标题，剔除压制组信息（用于给大模型做语境）。
  static String? sanitizeVideoTitle(String? rawTitle) {
    if (rawTitle == null) return null;
    var title = rawTitle.trim();
    if (title.isEmpty) return null;

    if (title.contains('/') || title.contains('\\')) {
      final sep = title.contains('/') ? '/' : '\\';
      title = title.split(sep).last.trim();
    }
    title = title
        .replaceAll(
          RegExp(r'\.(mp4|mkv|avi|mov|wmv|flv|webm|ts|m2ts|rmvb|iso|vob|m4v)$',
              caseSensitive: false),
          '',
        )
        .trim();
    title = title.replaceAll(
      RegExp(r'\[[A-Za-z0-9_.\s-]+-(Raws?|sub|fansub|rip)\]',
          caseSensitive: false),
      ' ',
    );
    title = title.replaceAll(RegExp(r'【.*?字幕组.*?】', caseSensitive: false), ' ');
    final techPattern = RegExp(
      r'\b(2160p|1080p|1080i|720p|480p|360p|4k|8k|uhd|fhd|hd|'
      r'bluray|bdrip|brrip|web-?dl|web-?rip|hdtv|dvdrip|remux|'
      r'hdr10\+?|hdr|dolby|vision|atmos|dts-?hd(\.ma)?|dts|truehd|ac3|eac3|aac|flac|mp3|'
      r'x264|x265|h264|h265|hevc|avc|10bit|8bit|12bit|'
      r'complete|proper|repack|internal|unrated|extended|directors\.cut)\b',
      caseSensitive: false,
    );
    title = title.replaceAll(techPattern, ' ');
    title = title.replaceAll(RegExp(r'[\[\]【】()（）._+\-–—]'), ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (title.length < 2) return null;
    if (RegExp(r'^\d+$').hasMatch(title)) return null;
    if (RegExp(r'^[0-9a-fA-F]{16,}$').hasMatch(title.replaceAll(' ', ''))) {
      return null;
    }
    final validChars =
        RegExp(r'[\u4e00-\u9fa5a-zA-Z0-9\u3040-\u30ff\uac00-\ud7af]');
    final validMatches = validChars.allMatches(title).length;
    if (validMatches < 2 || (validMatches / title.length) < 0.4) return null;
    if (title.length > 50) title = title.substring(0, 50).trim();
    return title;
  }

  static String buildLlmReference({String? rawTitle}) {
    final cleanTitle = sanitizeVideoTitle(rawTitle);
    if (cleanTitle != null && cleanTitle.isNotEmpty) {
      return '当前对白出自影视作品《$cleanTitle》。请结合该作品的背景、角色关系与剧情口语语境，'
          '将以下对白台词翻译为通顺、地道的目标语言字幕，保持口语化。';
    }
    return '请将以下影视对白台词翻译为通顺、地道的目标语言字幕，保持口语化。';
  }

  @override
  Future<String> testConnection({String testText = 'Hello'}) async {
    final results = await translateBatch(
      texts: [testText],
      targetLanguage: 'zh-Hans',
    );
    if (results.isEmpty || results.first.trim().isEmpty) {
      throw const TranslationException('百度翻译返回空结果');
    }
    return results.first;
  }

  @override
  Future<List<String>> translateBatch({
    required List<String> texts,
    required String targetLanguage,
    String sourceLanguage = 'auto',
    String? contextTitle,
  }) async {
    if (texts.isEmpty) return const [];
    if (!isConfigured) {
      throw const TranslationException('未配置百度翻译 APP ID 或密钥');
    }

    final isLlm = modelType == 'llm';
    final lang = TranslationLanguage.findByCode(targetLanguage);
    final toLang = lang.baiduCode;
    final fromLang = sourceLanguage == 'auto'
        ? 'auto'
        : TranslationLanguage.findByCode(sourceLanguage).baiduCode;

    final sanitizedTexts =
        texts.map((t) => t.replaceAll('\n', ' ').trim()).toList();
    final query = sanitizedTexts.join('\n');

    // 处理 I/l 视觉混淆
    final candidateKeys = <String>[secretKey];
    if (secretKey.startsWith('ol')) {
      candidateKeys.add('oI${secretKey.substring(2)}');
    } else if (secretKey.startsWith('oI')) {
      candidateKeys.add('ol${secretKey.substring(2)}');
    }

    final endpoints = isLlm
        ? [_llmEndpoint]
        : [_nmtEndpoint];

    Response<dynamic>? response;
    dynamic lastError;

    for (final currentKey in candidateKeys) {
      final salt =
          (DateTime.now().millisecondsSinceEpoch + Random().nextInt(10000))
              .toString();
      final signStr = '$appId$query$salt$currentKey';
      final sign =
          md5.convert(utf8.encode(signStr)).toString().toLowerCase();

      final bodyData = <String, String>{
        'q': query,
        'from': fromLang,
        'to': toLang,
        'appid': appId,
        'salt': salt,
        'sign': sign,
      };
      if (isLlm) {
        bodyData['model_type'] = 'llm';
        bodyData['reference'] = buildLlmReference(rawTitle: contextTitle);
      }

      for (final endpoint in endpoints) {
        try {
          final res = await _dio.post(
            endpoint,
            data: bodyData,
            options: Options(
              contentType: Headers.formUrlEncodedContentType,
              sendTimeout: Duration(seconds: isLlm ? 15 : 10),
              receiveTimeout: Duration(seconds: isLlm ? 25 : 15),
              validateStatus: (_) => true,
            ),
          );

          if (res.statusCode == 200 && res.data != null) {
            final Map<String, dynamic> data = _asMap(res.data);
            if (data['error_code']?.toString() == '54001') {
              lastError = data;
              break;
            }
            response = res;
            break;
          } else {
            lastError = 'HTTP ${res.statusCode}';
          }
        } catch (e) {
          lastError = e;
        }
      }

      if (response != null) break;
    }

    if (response == null) {
      if (lastError is Map && lastError.containsKey('error_code')) {
        final code = lastError['error_code'].toString();
        final msg = lastError['error_msg']?.toString() ?? '未知错误';
        throw TranslationException(_friendly(code, msg), code: code);
      }
      throw TranslationException('连接百度翻译失败：$lastError',
          rawError: lastError);
    }

    final Map<String, dynamic> data = _asMap(response.data);
    if (data.containsKey('error_code')) {
      final code = data['error_code'].toString();
      if (code != '52000') {
        final msg = data['error_msg']?.toString() ?? '未知错误';
        throw TranslationException(_friendly(code, msg), code: code);
      }
    }

    List<dynamic>? transList;
    if (data['result'] is Map && data['result']['trans_result'] is List) {
      transList = data['result']['trans_result'] as List<dynamic>;
    } else if (data['trans_result'] is List) {
      transList = data['trans_result'] as List<dynamic>;
    }

    if (transList == null || transList.isEmpty) {
      return List.filled(texts.length, '');
    }

    if (transList.length == texts.length) {
      return transList
          .map((item) => (item is Map ? item['dst']?.toString() ?? '' : ''))
          .toList();
    }

    final results = <String>[];
    for (var i = 0; i < texts.length; i++) {
      if (i < transList.length && transList[i] is Map) {
        results.add((transList[i] as Map)['dst']?.toString() ?? '');
      } else {
        results.add('');
      }
    }
    return results;
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  static String _friendly(String code, String rawMsg) {
    switch (code) {
      case '52001':
        return '请求超时，请重试';
      case '52002':
        return '系统错误，请重试';
      case '52003':
        return '未授权用户，请检查 APP ID 和密钥，且已开通对应服务';
      case '54000':
        return '必填参数为空';
      case '54001':
        return '签名错误，请检查密钥';
      case '54003':
        return '访问频率受限，请稍候再试';
      case '54004':
        return '账户余额不足或免费额度已耗尽';
      case '58000':
        return '客户端 IP 非法';
      case '58001':
        return '译文语言方向不支持';
      case '58002':
        return '服务当前已关闭，请前往控制台开启';
      default:
        return '百度翻译错误 [$code]: $rawMsg';
    }
  }
}
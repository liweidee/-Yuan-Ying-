import 'dart:convert';

import 'package:dio/dio.dart';

import 'translation_engine.dart';

/// 微软 Azure AI Translator 引擎。
class AzureTranslationEngine implements TranslationEngine {
  AzureTranslationEngine({
    required String key,
    String region = 'eastasia',
  })  : key = _clean(key),
        region = region.trim().toLowerCase();

  final String key;
  final String region;

  static const String _endpoint =
      'https://api.cognitive.microsofttranslator.com/translate';

  static final Dio _dio = Dio();

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '');

  @override
  String get id => 'azure';

  @override
  String get displayName => '微软 Azure 翻译';

  @override
  bool get isConfigured => key.isNotEmpty;

  @override
  String? get configurationError =>
      isConfigured ? null : '未配置微软 Azure 翻译密钥';

  @override
  Future<String> testConnection({String testText = 'Hello'}) async {
    final results = await translateBatch(
      texts: [testText],
      targetLanguage: 'zh-Hans',
    );
    if (results.isEmpty || results.first.trim().isEmpty) {
      throw const TranslationException('Azure 翻译返回空结果');
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
      throw const TranslationException('未配置微软 Azure 翻译密钥');
    }

    final lang = TranslationLanguage.findByCode(targetLanguage);
    final toLang = lang.azureCode;

    var url = '$_endpoint?api-version=3.0&to=$toLang';
    if (sourceLanguage != 'auto') {
      final fromLang =
          TranslationLanguage.findByCode(sourceLanguage).azureCode;
      url += '&from=$fromLang';
    }

    final bodyJson =
        jsonEncode(texts.map((t) => {'Text': t}).toList(growable: false));

    final headers = <String, String>{
      'Ocp-Apim-Subscription-Key': key,
    };
    if (region.isNotEmpty && region != 'global') {
      headers['Ocp-Apim-Subscription-Region'] = region;
    }

    Response<dynamic> response;
    try {
      response = await _dio.post(
        url,
        data: bodyJson,
        options: Options(
          contentType: 'application/json; charset=UTF-8',
          headers: headers,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (_) => true,
        ),
      );
    } catch (e) {
      throw TranslationException('连接 Azure 翻译失败：$e', rawError: e);
    }

    if (response.statusCode != 200) {
      String msg = 'HTTP ${response.statusCode}';
      String? errCode;
      try {
        final raw = response.data;
        final Map<String, dynamic> data = raw is Map
            ? Map<String, dynamic>.from(raw)
            : (raw is String
                ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
                : <String, dynamic>{});
        if (data['error'] is Map) {
          final err = Map<String, dynamic>.from(data['error'] as Map);
          errCode = err['code']?.toString();
          msg = err['message']?.toString() ?? msg;
        }
      } catch (_) {}
      throw TranslationException(
        _friendly(response.statusCode ?? 0, errCode, msg),
        code: errCode,
      );
    }

    final dynamic raw = response.data;
    final dynamic data = raw is String ? jsonDecode(raw) : raw;
    if (data is! List) {
      throw const TranslationException('Azure 返回数据格式异常');
    }

    final results = <String>[];
    for (final item in data) {
      if (item is Map && item['translations'] is List) {
        final list = item['translations'] as List;
        if (list.isNotEmpty && list.first is Map) {
          results.add((list.first as Map)['text']?.toString() ?? '');
          continue;
        }
      }
      results.add('');
    }
    return results;
  }

  static String _friendly(int status, String? errCode, String rawMsg) {
    if (status == 401 || errCode == '401000') {
      return 'Azure 密钥无效或未授权';
    }
    if (status == 400 && rawMsg.contains('region')) {
      return '区域（Region）不匹配，请检查是否与 Azure 资源区域一致';
    }
    if (status == 403 || errCode == '403001') {
      return '配额受限或余额不足';
    }
    if (status == 429) {
      return '并发过多，超出定价层 QPS 上限';
    }
    return 'Azure 翻译错误：$rawMsg';
  }
}
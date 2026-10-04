/// 翻译异常。
class TranslationException implements Exception {
  const TranslationException(this.message, {this.code, this.rawError});

  final String message;
  final String? code;
  final dynamic rawError;

  @override
  String toString() {
    if (code != null && code!.isNotEmpty) {
      return '[$code] $message';
    }
    return message;
  }
}

/// 目标语言定义。
class TranslationLanguage {
  const TranslationLanguage({
    required this.code,
    required this.name,
    required this.baiduCode,
    required this.azureCode,
  });

  final String code;
  final String name;
  final String baiduCode;
  final String azureCode;

  static const List<TranslationLanguage> supportedLanguages = [
    TranslationLanguage(
      code: 'zh-Hans',
      name: '简体中文',
      baiduCode: 'zh',
      azureCode: 'zh-Hans',
    ),
    TranslationLanguage(
      code: 'zh-Hant',
      name: '繁体中文',
      baiduCode: 'cht',
      azureCode: 'zh-Hant',
    ),
    TranslationLanguage(
      code: 'en',
      name: '英语',
      baiduCode: 'en',
      azureCode: 'en',
    ),
    TranslationLanguage(
      code: 'ja',
      name: '日语',
      baiduCode: 'jp',
      azureCode: 'ja',
    ),
    TranslationLanguage(
      code: 'ko',
      name: '韩语',
      baiduCode: 'kor',
      azureCode: 'ko',
    ),
  ];

  static TranslationLanguage findByCode(String code) {
    return supportedLanguages.firstWhere(
      (l) => l.code == code || l.baiduCode == code,
      orElse: () => supportedLanguages.first,
    );
  }
}

/// 翻译引擎统一接口。
abstract class TranslationEngine {
  /// 引擎唯一标识（baidu / azure）。
  String get id;

  /// 引擎显示名称。
  String get displayName;

  /// 当前引擎是否已完成必要配置。
  bool get isConfigured;

  /// 未配置时的提示文案（已就绪则返回 null）。
  String? get configurationError;

  /// 测试连接（成功返回目标语言译文）。
  Future<String> testConnection({String testText = 'Hello'});

  /// 批量翻译。
  Future<List<String>> translateBatch({
    required List<String> texts,
    required String targetLanguage,
    String sourceLanguage = 'auto',
    String? contextTitle,
  });
}
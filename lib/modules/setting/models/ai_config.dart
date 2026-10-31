// lib/modules/setting/models/ai_config.dart

/// AI 助手配置（OpenAI 兼容接口）
class AiConfig {
  /// API 基址，例如 https://api.openai.com/v1
  final String apiBaseUrl;

  /// API Key
  final String apiKey;

  /// 模型名，例如 gpt-4o-mini
  final String model;

  /// 工具调用轮数上限（页面侧"工具使用次数"滑块）
  final int maxToolCalls;

  const AiConfig({
    this.apiBaseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
    this.maxToolCalls = 5,
  });

  AiConfig copyWith({
    String? apiBaseUrl,
    String? apiKey,
    String? model,
    int? maxToolCalls,
  }) {
    return AiConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      maxToolCalls: maxToolCalls ?? this.maxToolCalls,
    );
  }

  /// 是否已配置（基址和 Key 都非空）
  bool get isConfigured => apiBaseUrl.isNotEmpty && apiKey.isNotEmpty;

  /// 拼接完整 chat completions 地址，兼容 base 末尾带/不带 `/`
  String get chatCompletionsUrl {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/chat/completions';
  }

  /// 拼接 models 地址（用于测试连接）
  String get modelsUrl {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/models';
  }

  Map<String, dynamic> toJson() => {
        'apiBaseUrl': apiBaseUrl,
        'apiKey': apiKey,
        'model': model,
        'maxToolCalls': maxToolCalls,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        apiBaseUrl: json['apiBaseUrl']?.toString() ?? 'https://api.openai.com/v1',
        apiKey: json['apiKey']?.toString() ?? '',
        model: json['model']?.toString() ?? 'gpt-4o-mini',
        maxToolCalls: (json['maxToolCalls'] is num)
            ? (json['maxToolCalls'] as num).toInt()
            : 5,
      );
}
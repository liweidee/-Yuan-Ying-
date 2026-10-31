// lib/modules/setting/controllers/ai_config_controller.dart

import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/setting/models/ai_config.dart';
import 'package:yuanying/utils/storage_manager.dart';

class AiConfigController extends GetxController {
  final Rx<AiConfig> config = const AiConfig().obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    config.value = AiConfig(
      apiBaseUrl:
          StorageManager.getSetting<String>(SettingBoxKey.aiApiBaseUrl) ??
              'https://api.openai.com/v1',
      apiKey: StorageManager.getSetting<String>(SettingBoxKey.aiApiKey) ?? '',
      model: StorageManager.getSetting<String>(SettingBoxKey.aiModel) ??
          'gpt-4o-mini',
      maxToolCalls:
          StorageManager.getSetting<int>(SettingBoxKey.aiMaxToolCalls) ?? 5,
    );
  }

  /// 当前 Hive 里保存的配置是否完整（基址 + Key 都非空）
  bool get isReady =>
      config.value.apiBaseUrl.trim().isNotEmpty &&
      config.value.apiKey.trim().isNotEmpty;

  void save(AiConfig cfg) {
    StorageManager.setSetting(SettingBoxKey.aiApiBaseUrl, cfg.apiBaseUrl);
    StorageManager.setSetting(SettingBoxKey.aiApiKey, cfg.apiKey);
    StorageManager.setSetting(SettingBoxKey.aiModel, cfg.model);
    StorageManager.setSetting(SettingBoxKey.aiMaxToolCalls, cfg.maxToolCalls);
    config.value = cfg;
  }

  void clear() {
    StorageManager.setSetting(SettingBoxKey.aiApiBaseUrl, '');
    StorageManager.setSetting(SettingBoxKey.aiApiKey, '');
    StorageManager.setSetting(SettingBoxKey.aiModel, 'gpt-4o-mini');
    StorageManager.setSetting(SettingBoxKey.aiMaxToolCalls, 5);
    config.value = const AiConfig(apiKey: '');
  }

  /// 测试连接：GET {base}/models，带 Authorization
  /// 返回 (ok, message)
  Future<({bool ok, String message})> testConnection(AiConfig cfg) async {
    if (cfg.apiBaseUrl.trim().isEmpty) {
      return (ok: false, message: '请先填写 API 基址');
    }
    if (cfg.apiKey.trim().isEmpty) {
      return (ok: false, message: '请先填写 API Key');
    }
    try {
      final uri = Uri.parse(cfg.modelsUrl);
      final resp = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${cfg.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          final data = jsonDecode(resp.body);
          if (data is Map && data['data'] is List) {
            final count = (data['data'] as List).length;
            return (ok: true, message: '连接成功，可用模型 $count 个');
          }
          return (ok: true, message: '连接成功（HTTP ${resp.statusCode}）');
        } catch (_) {
          return (ok: true, message: '连接成功（HTTP ${resp.statusCode}）');
        }
      }
      if (resp.statusCode == 401) {
        return (ok: false, message: '认证失败（401），请检查 API Key');
      }
      return (ok: false, message: '连接失败：HTTP ${resp.statusCode}');
    } catch (e) {
      return (ok: false, message: '连接失败：$e');
    }
  }

  /// 探测常见本地网关端口，返回 (port, models) 或 null
  Future<({int port, List<String> models})?> probeLocalGateway() async {
    const candidates = <int>[3065, 8080, 3000, 1234, 8000, 5000];
    for (final port in candidates) {
      try {
        final resp = await http
            .get(Uri.parse('http://127.0.0.1:$port/v1/models'))
            .timeout(const Duration(milliseconds: 600));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map && data['data'] is List) {
            final models = (data['data'] as List)
                .map((e) => e is Map ? (e['id']?.toString() ?? '') : '')
                .where((s) => s.isNotEmpty)
                .toList();
            return (port: port, models: models);
          }
        }
      } catch (_) {
        // 端口不通，继续
      }
    }
    return null;
  }

  /// 从当前配置的 {base}/models 拉取模型列表。
  /// 返回 (ok, models, message)：
  /// - ok=true 时 models 非空（或为空但接口正常，提示用户手填）
  /// - ok=false 时 message 为错误原因
  Future<({bool ok, List<String> models, String message})> fetchModels(
    AiConfig cfg,
  ) async {
    if (cfg.apiBaseUrl.trim().isEmpty) {
      return (ok: false, models: const <String>[], message: '请先填写 API 基址');
    }
    if (cfg.apiKey.trim().isEmpty) {
      return (ok: false, models: const <String>[], message: '请先填写 API Key');
    }
    try {
      final resp = await http
          .get(
            Uri.parse(cfg.modelsUrl),
            headers: {
              'Authorization': 'Bearer ${cfg.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 401) {
        return (
          ok: false,
          models: const <String>[],
          message: '认证失败（401），请检查 API Key',
        );
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return (
          ok: false,
          models: const <String>[],
          message: '拉取失败：HTTP ${resp.statusCode}',
        );
      }

      final data = jsonDecode(resp.body);
      if (data is! Map || data['data'] is! List) {
        return (
          ok: false,
          models: const <String>[],
          message: '接口返回格式不是标准 /models 结构',
        );
      }

      final models = <String>[];
      for (final item in data['data'] as List) {
        if (item is Map) {
          final id = item['id']?.toString() ?? '';
          if (id.isNotEmpty) models.add(id);
        }
      }
      models.sort();

      if (models.isEmpty) {
        return (
          ok: true,
          models: const <String>[],
          message: '接口可用，但未返回模型列表，请手动填写模型名',
        );
      }
      return (
        ok: true,
        models: models,
        message: '拉取到 ${models.length} 个模型',
      );
    } catch (e) {
      return (
        ok: false,
        models: const <String>[],
        message: '拉取失败：$e',
      );
    }
  }
}
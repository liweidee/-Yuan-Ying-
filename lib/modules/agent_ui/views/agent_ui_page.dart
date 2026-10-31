// lib/modules/agent_ui/views/agent_ui_page.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import 'package:yuanying/main.dart' show webViewEnvironment;
import 'package:yuanying/modules/agent_ui/services/agent_ui_gateway.dart';
import 'package:yuanying/modules/setting/controllers/ai_config_controller.dart';
import 'package:yuanying/modules/setting/models/ai_config.dart';
import 'package:yuanying/modules/agent_llm/services/agent_llm_server.dart';

class AgentUiPage extends StatefulWidget {
  const AgentUiPage({super.key});

  @override
  State<AgentUiPage> createState() => _AgentUiPageState();
}

class _AgentUiPageState extends State<AgentUiPage> {
  InAppWebViewController? _web;
  String? _url;
  String? _error;

  /// 防止 onLoadStop 里 reload 导致的死循环
  bool _configInjected = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. 先起本地 LLM 网关（和 DsPlayer 一致：先起网关再开页面）
    await AgentLlmServer.instance.ensureStarted();

    // 2. 再起静态资源服务
    final url = await AgentUiGateway.instance.ensureStarted();
    if (!mounted) return;
    if (url == null) {
      setState(() {
        _error = '未检测到 agent-ui 插件，请先在「插件中心」安装「AI 助手界面」';
      });
      return;
    }
    setState(() => _url = url);
  }

  /// 从 Hive 读取配置
  AiConfig _readConfig() {
    if (Get.isRegistered<AiConfigController>()) {
      return Get.find<AiConfigController>().config.value;
    }
    return const AiConfig();
  }

  /// 生成注入脚本：把配置写进 NextChat 的 localStorage('app-config')
  String _buildInjectScript(AiConfig cfg) {
    // NextChat 的 Zustand persist key 是 'app-config'
    // 结构：{ state: {...}, version: 4 }
    // 关键字段：openaiUrl / openaiApiKey / useCustomConfig / modelConfig.model
    final llmBase = AgentLlmServer.instance.baseUrl;
    final llmToken = AgentLlmServer.instance.token;
    final useLocalGateway = llmBase != null && llmToken.isNotEmpty;

    final statePatch = <String, dynamic>{
      'openaiUrl': useLocalGateway ? llmBase : cfg.apiBaseUrl,
      'openaiApiKey': useLocalGateway ? llmToken : cfg.apiKey,
      'useCustomConfig': true,
      'modelConfig': <String, dynamic>{
        'model': cfg.model,
        'providerName': 'OpenAI',
      },
    };

    final patchJson = jsonEncode(statePatch);

    return '''
(function(){
  try {
    var KEY = 'app-config';
    var raw = localStorage.getItem(KEY);
    var store = raw ? JSON.parse(raw) : { state: {}, version: 4 };
    store.state = store.state || {};
    var patch = $patchJson;
    for (var k in patch) {
      if (k === 'modelConfig') {
        store.state.modelConfig = store.state.modelConfig || {};
        for (var mk in patch.modelConfig) {
          store.state.modelConfig[mk] = patch.modelConfig[mk];
        }
      } else {
        store.state[k] = patch[k];
      }
    }
    localStorage.setItem(KEY, JSON.stringify(store));
    sessionStorage.setItem('__ds_ai_injected', '1');
    return 'ok';
  } catch (e) {
    return 'err:' + e;
  }
})();
''';
  }

  Future<void> _injectConfigAndReload() async {
    final c = _web;
    if (c == null || _configInjected) return;

    final cfg = _readConfig();
    if (!cfg.isConfigured) {
      // 配置不完整就不注入，让用户在页面里自己填
      return;
    }

    // 先检查 sessionStorage，避免每次 reload 都重复注入
    final already = await c.evaluateJavascript(
      source: "sessionStorage.getItem('__ds_ai_injected')",
    );
    if (already == '1' || already == '"1"') {
      _configInjected = true;
      return;
    }

    final result = await c.evaluateJavascript(
      source: _buildInjectScript(cfg),
    );
    debugPrint('[AgentUiPage] inject result: $result');

    if (result is String && result.startsWith('ok')) {
      _configInjected = true;
      await c.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 助手')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_url == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // 手动刷新时清掉注入标记，允许重新注入（用户在设置页改了配置）
              await _web?.evaluateJavascript(
                source: "sessionStorage.removeItem('__ds_ai_injected')",
              );
              _configInjected = false;
              await _web?.reload();
            },
          ),
          IconButton(
            tooltip: '在页面内打开设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await _web?.loadUrl(
                urlRequest: URLRequest(
                  url: WebUri('$_url#/settings'),
                ),
              );
            },
          ),
        ],
      ),
      body: InAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(_url!)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          supportMultipleWindows: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        onWebViewCreated: (c) => _web = c,
        onLoadStop: (c, url) async {
          await _injectConfigAndReload();
        },
      ),
    );
  }
}
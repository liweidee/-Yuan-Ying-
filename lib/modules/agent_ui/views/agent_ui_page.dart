// lib/modules/agent_ui/views/agent_ui_page.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import 'package:yuanying/main.dart' show webViewEnvironment;
import 'package:yuanying/modules/agent_ui/services/agent_ui_gateway.dart';
import 'package:yuanying/modules/agent_llm/services/agent_llm_server.dart';
import 'package:yuanying/modules/setting/controllers/ai_config_controller.dart';
import 'package:yuanying/modules/setting/models/ai_config.dart';

class AgentUiPage extends StatefulWidget {
  const AgentUiPage({super.key});

  @override
  State<AgentUiPage> createState() => _AgentUiPageState();
}

class _AgentUiPageState extends State<AgentUiPage> {
  InAppWebViewController? _web;
  String? _url;
  String? _error;

  /// 防止 reload 死循环（仅作为辅助，主判断靠 openaiUrl 匹配）
  bool _configInjected = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Get.isRegistered<AiConfigController>()) {
      Get.put(AiConfigController());
    }

    // 先起网关（生成 token + 端口）
    await AgentLlmServer.instance.ensureStarted();

    // 再起静态资源服务
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

  AiConfig _readConfig() {
    if (Get.isRegistered<AiConfigController>()) {
      return Get.find<AiConfigController>().config.value;
    }
    return const AiConfig();
  }

  /// 生成注入脚本。
  ///
  /// 核心：openaiUrl 用 rootUrl（不带 /v1）。
  /// NextChat 会自己拼 openaiUrl + '/v1/chat/completions'。
  String _buildInjectScript(AiConfig cfg) {
    // 关键：rootUrl 不带 /v1
    final llmBase = AgentLlmServer.instance.rootUrl;
    final llmToken = AgentLlmServer.instance.token;
    final useLocalGateway = llmBase != null && llmToken.isNotEmpty;

    final url = useLocalGateway ? llmBase : cfg.apiBaseUrl.trim();
    final key = useLocalGateway ? llmToken : cfg.apiKey.trim();
    final model = cfg.model.trim().isEmpty ? 'gpt-4o-mini' : cfg.model.trim();

    final urlJson = jsonEncode(url);
    final keyJson = jsonEncode(key);
    final modelJson = jsonEncode(model);

    return '''
(function(){
  try {
    var URL = $urlJson;
    var KEY = $keyJson;
    var MODEL = $modelJson;

    // ============================================================
    // patch 1: access-control（接口配置，核心）
    // ============================================================
    var AKEY = 'access-control';
    var araw = localStorage.getItem(AKEY);
    var astore = araw ? JSON.parse(araw) : { state: {}, version: 2 };
    astore.state = astore.state || {};
    astore.state.useCustomConfig = true;
    astore.state.provider = 'OpenAI';
    astore.state.openaiUrl = URL;      // 不带 /v1！
    astore.state.openaiApiKey = KEY;
    astore.state.needCode = false;
    localStorage.setItem(AKEY, JSON.stringify(astore));

    // ============================================================
    // patch 2: app-config（全局 modelConfig）
    // ============================================================
    var CKEY = 'app-config';
    var craw = localStorage.getItem(CKEY);
    var cstore = craw ? JSON.parse(craw) : { state: {}, version: 4 };
    cstore.state = cstore.state || {};
    cstore.state.modelConfig = cstore.state.modelConfig || {};
    cstore.state.modelConfig.model = MODEL;
    cstore.state.modelConfig.providerName = 'OpenAI';
    cstore.state.modelConfig.stream = false;
    if (Array.isArray(cstore.state.masks)) {
      cstore.state.masks.forEach(function(m){
        if (!m) return;
        if (!m.modelConfig) m.modelConfig = {};
        m.modelConfig.model = MODEL;
        m.modelConfig.providerName = 'OpenAI';
        m.modelConfig.stream = false;
      });
    }
    localStorage.setItem(CKEY, JSON.stringify(cstore));

    // ============================================================
    // patch 3: chat-next-web-store（所有已有会话的 mask）
    // ============================================================
    var SKEY = 'chat-next-web-store';
    var sraw = localStorage.getItem(SKEY);
    if (sraw) {
      try {
        var ss = JSON.parse(sraw);
        ss.state = ss.state || {};
        if (Array.isArray(ss.state.sessions)) {
          ss.state.sessions.forEach(function(sess){
            if (!sess) return;
            if (!sess.mask) sess.mask = {};
            if (!sess.mask.modelConfig) sess.mask.modelConfig = {};
            sess.mask.modelConfig.model = MODEL;
            sess.mask.modelConfig.providerName = 'OpenAI';
            sess.mask.modelConfig.stream = false;
          });
        }
        localStorage.setItem(SKEY, JSON.stringify(ss));
      } catch (e) {}
    }

    // ============================================================
    // patch 4: mask-store（用户自定义 mask 模板）
    // ============================================================
    var MKEY = 'mask-store';
    var mraw = localStorage.getItem(MKEY);
    if (mraw) {
      try {
        var ms = JSON.parse(mraw);
        ms.state = ms.state || {};
        if (ms.state.masks && typeof ms.state.masks === 'object') {
          Object.keys(ms.state.masks).forEach(function(k){
            var m = ms.state.masks[k];
            if (!m) return;
            if (!m.modelConfig) m.modelConfig = {};
            m.modelConfig.model = MODEL;
            m.modelConfig.providerName = 'OpenAI';
            m.modelConfig.stream = false;
          });
        }
        localStorage.setItem(MKEY, JSON.stringify(ms));
      } catch (e) {}
    }

    // ============================================================
    // patch 5: 清 IndexedDB 里的 access-control / app-config
    //
    // NextChat storage.getItem 是「先 IndexedDB 再 localStorage」，
    // 不清 IDB 的话，reload 后 hydration 会读到旧值覆盖 localStorage。
    // 用异步 Promise + window.__ds_inject_done 标志等待完成。
    // ============================================================
    var cleanIDB = function(){
      var promises = [];
      var tryDelete = function(dbName){
        promises.push(new Promise(function(resolve){
          try {
            var req = indexedDB.deleteDatabase(dbName);
            req.onsuccess = function(){ resolve(); };
            req.onerror = function(){ resolve(); };
            req.onblocked = function(){ resolve(); };
          } catch(e){ resolve(); }
        }));
      };
      if (indexedDB.databases) {
        promises.push(
          indexedDB.databases().then(function(dbs){
            (dbs || []).forEach(function(d){
              if (d && d.name) tryDelete(d.name);
            });
          }).catch(function(){})
        );
      }
      ['keyval-store', 'nextchat', 'chat-next-web-store', 'keyval'].forEach(tryDelete);
      return Promise.all(promises);
    };

    window.__ds_inject_done = false;
    cleanIDB().then(function(){
      sessionStorage.setItem('__ds_ai_injected', '1');
      window.__ds_inject_done = true;
    }).catch(function(){
      sessionStorage.setItem('__ds_ai_injected', '1');
      window.__ds_inject_done = true;
    });

    return 'ok';
  } catch (e) {
    window.__ds_inject_done = true;
    return 'err:' + e;
  }
})();
''';
  }

  /// 注入 + 必要时 reload。
  ///
  /// 每次 onLoadStop 都会调用。判断逻辑：
  ///   1. 读当前 access-control.openaiUrl
  ///   2. 如果等于网关 rootUrl → 已注入，跳过
  ///   3. 否则（null / 被用户改过 / 被重置）→ 强制注入 + reload
  ///
  /// 这样即使用户在 AI 助手内手动改配置，下次 onLoadStop 会强制覆盖回来。
  Future<void> _injectConfigAndReload() async {
    final c = _web;
    if (c == null) return;

    final cfg = _readConfig();
    if (!cfg.isConfigured || cfg.model.trim().isEmpty) {
      debugPrint(
        '[AgentUiPage] 配置不完整，跳过注入: '
        'base=${cfg.apiBaseUrl.isEmpty ? "空" : "已填"} '
        'key=${cfg.apiKey.isEmpty ? "空" : "已填"} '
        'model=${cfg.model.isEmpty ? "空" : cfg.model}',
      );
      return;
    }

    final expectedUrl = AgentLlmServer.instance.rootUrl;
    if (expectedUrl == null) {
      debugPrint('[AgentUiPage] 网关未启动');
      return;
    }

    // 检查当前 openaiUrl
    final currentUrl = await c.evaluateJavascript(
      source: "(function(){"
          "try{"
          "var s=localStorage.getItem('access-control');"
          "if(!s)return null;"
          "var j=JSON.parse(s);"
          "return j.state && j.state.openaiUrl ? j.state.openaiUrl : null;"
          "}catch(e){return null;}"
          "})()",
    );
    final currentUrlStr = currentUrl?.toString();
    // evaluateJavascript 返回可能是带引号的字符串，去掉引号
    final cleanUrl = currentUrlStr?.replaceAll('"', '') ?? '';

    if (cleanUrl == expectedUrl && _configInjected) {
      // 已是最新，跳过
      return;
    }

    debugPrint(
      '[AgentUiPage] 注入 (currentUrl=$cleanUrl, expected=$expectedUrl)',
    );

    final result = await c.evaluateJavascript(
      source: _buildInjectScript(cfg),
    );
    debugPrint('[AgentUiPage] inject result: $result');

    if (result is String && result.startsWith('ok')) {
      _configInjected = true;
      // 等 IndexedDB 清理完成（最多 2 秒）
      for (var i = 0; i < 20; i++) {
        final done = await c.evaluateJavascript(
          source: "window.__ds_inject_done === true",
        );
        if (done == true || done == 'true') break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      debugPrint('[AgentUiPage] reload 应用注入');
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
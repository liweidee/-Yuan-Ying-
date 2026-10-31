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
    // AiConfigController.onInit 是同步 _load()，
    // Get.put 返回后 config.value 已是最新值。
    if (!Get.isRegistered<AiConfigController>()) {
      Get.put(AiConfigController());
    }

    // 1. 先起本地 LLM 网关
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

  AiConfig _readConfig() {
    if (Get.isRegistered<AiConfigController>()) {
      return Get.find<AiConfigController>().config.value;
    }
    return const AiConfig();
  }

  /// 生成注入脚本：把配置写进 NextChat 的正确存储位置。
  ///
  /// 【NextChat 存储结构（从 page-8904b7358f096194.js 反推）】
  ///
  ///   access-control       ← o._X，存 openaiUrl / openaiApiKey / useCustomConfig
  ///                          ★ 接口配置在这里！不在 app-config 里
  ///   app-config           ← o.MG，存 modelConfig（model / temperature / ...）
  ///   chat-next-web-store  ← o.aK，存 sessions[]（含 sessions[].mask.modelConfig）
  ///   mask-store           ← o.Zy，存自定义 mask
  ///
  /// 【请求实际的 model 来源（优先级从高到低）】
  ///   sessions[current].mask.modelConfig.model    （会话 mask，会话创建时固化）
  /// > app-config.modelConfig.model                 （全局默认，新会话复制源）
  ///
  /// 【IndexedDB 优先级高于 localStorage】
  ///   NextChat 的 storage.getItem 是「先 IndexedDB 再 localStorage」，
  ///   所以必须同时清掉 IndexedDB 里的 access-control / app-config，
  ///   否则 localStorage 里的新值会被 IndexedDB 里的旧值覆盖。
  String _buildInjectScript(AiConfig cfg) {
    final llmBase = AgentLlmServer.instance.baseUrl;
    final llmToken = AgentLlmServer.instance.token;
    final useLocalGateway = llmBase != null && llmToken.isNotEmpty;

    // AiConfig.isConfigured 没 trim，这里都 trim 一遍防止空白字符
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
    // patch 1: access-control（接口配置，核心！）
    //
    // 这是 o._X store，class p.path() 读 t.openaiUrl、
    // class R() 读 t.openaiApiKey，都是从这里读。
    // 之前 patch app-config 无效就是这个原因。
    // ============================================================
    var AKEY = 'access-control';
    var araw = localStorage.getItem(AKEY);
    var astore = araw ? JSON.parse(araw) : { state: {}, version: 2 };
    astore.state = astore.state || {};
    astore.state.useCustomConfig = true;
    astore.state.provider = 'OpenAI';
    astore.state.openaiUrl = URL;
    astore.state.openaiApiKey = KEY;
    astore.state.needCode = false;   // 避免被 auth 页拦截
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
    //
    // 会话的 mask.modelConfig 在会话创建时固化，
    // 后续改全局 modelConfig 不会影响已有会话，
    // 必须逐条改 sessions[].mask.modelConfig。
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
    // patch 5: 清掉 IndexedDB 里的 access-control / app-config 条目
    //
    // NextChat 的 storage.getItem 是「先 IndexedDB 再 localStorage」，
    // IndexedDB 里的旧值会覆盖我们刚写的 localStorage。
    // 只删 access-control / app-config（配置类），不动
    // chat-next-web-store / mask-store（保留对话和自定义 mask）。
    // ============================================================
    try {
      if (window.indexedDB && indexedDB.databases) {
        indexedDB.databases().then(function(dbs){
          (dbs || []).forEach(function(info){
            var name = info && info.name;
            if (!name) return;
            try {
              var req = indexedDB.open(name);
              req.onsuccess = function(ev){
                var db = ev.target.result;
                try {
                  if (db.objectStoreNames.contains('keyval')) {
                    var tx = db.transaction('keyval', 'readwrite');
                    var store = tx.objectStore('keyval');
                    try { store.delete('access-control'); } catch(e) {}
                    try { store.delete('app-config'); } catch(e) {}
                    tx.oncomplete = function(){ try { db.close(); } catch(e) {} };
                    tx.onerror = function(){ try { db.close(); } catch(e) {} };
                  } else {
                    db.close();
                  }
                } catch(e) { try { db.close(); } catch(e2) {} }
              };
            } catch(e) {}
          });
        });
      }
    } catch (e) {}

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
    // 必须同时有 base、key、model 才注入，避免注入空 model
    if (!cfg.isConfigured || cfg.model.trim().isEmpty) {
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
      // 给 IndexedDB 异步删除留一点时间（IDB 操作几毫秒完成，300ms 足够）
      await Future.delayed(const Duration(milliseconds: 300));
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
// lib/modules/agent_ui/views/agent_ui_page.dart

import 'dart:collection' show UnmodifiableListView;
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

  /// 预生成的注入脚本。在 _init 里生成一次，
  /// 通过 InAppWebView 的 initialUserScripts 在 AT_DOCUMENT_START 注入。
  ///
  /// 为什么用 initialUserScripts 而不是 onLoadStop + reload：
  ///   - initialUserScripts 在页面 HTML 解析前执行，localStorage 已经写好，
  ///     NextChat 加载时直接读到正确值，不需要 reload → 用户感知不到刷新
  ///   - DsPlayer 也是这个思路（首屏就是正确的）
  String? _injectScript;

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

    // 预生成注入脚本（此时网关已启动，rootUrl / token 已就绪）
    final cfg = _readConfig();
    if (cfg.isConfigured && cfg.model.trim().isNotEmpty) {
      _injectScript = _buildInjectScript(cfg);
      debugPrint('[AgentUiPage] 注入脚本已生成');
    } else {
      debugPrint(
        '[AgentUiPage] 配置不完整，跳过注入: '
        'base=${cfg.apiBaseUrl.isEmpty ? "空" : "已填"} '
        'key=${cfg.apiKey.isEmpty ? "空" : "已填"} '
        'model=${cfg.model.isEmpty ? "空" : cfg.model}',
      );
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
  /// 关键改动（相比上一版）：
  ///   1. openaiUrl 用 rootUrl（不带 /v1），NextChat 会自己拼 /v1/chat/completions
  ///   2. IndexedDB 只删除 access-control 和 app-config 两个 key，
  ///      不再 deleteDatabase，保留 chat-next-web-store（对话历史）
  ///      和 mask-store（自定义 mask）
  ///   3. 去掉了 sessionStorage 标记和 window.__ds_inject_done 等待，
  ///      因为改用 initialUserScripts 后不需要 reload
  String _buildInjectScript(AiConfig cfg) {
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
    // openaiUrl 不带 /v1，NextChat 会拼 /v1/chat/completions
    // ============================================================
    var AKEY = 'access-control';
    var araw = localStorage.getItem(AKEY);
    var astore = araw ? JSON.parse(araw) : { state: {}, version: 2 };
    astore.state = astore.state || {};
    astore.state.useCustomConfig = true;
    astore.state.provider = 'OpenAI';
    astore.state.openaiUrl = URL;
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
    // patch 3: chat-next-web-store（会话列表）
    //
    // 只更新 model 字段，保留所有会话内容（对话历史）。
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
    // patch 4: mask-store（自定义 mask）
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
    // patch 5: 精确删除 IndexedDB 里的 access-control / app-config
    //
    // NextChat storage.getItem 是「先 IndexedDB 再 localStorage」。
    // 只删这两个配置 key，删除后 hydrate 会 fallback 到 localStorage
    // 的新值。
    //
    // 关键：不 deleteDatabase！chat-next-web-store（对话历史）和
    // mask-store（自定义 mask）必须保留，否则用户历史全丢。
    // ============================================================
    var deleteIDBKeys = function(){
      var promises = [];
      var tryDelete = function(dbName){
        promises.push(new Promise(function(resolve){
          try {
            var req = indexedDB.open(dbName);
            req.onerror = function(){ resolve(); };
            req.onblocked = function(){ resolve(); };
            req.onsuccess = function(ev){
              var db = ev.target.result;
              try {
                var stores = Array.from(db.objectStoreNames);
                if (stores.length === 0) { db.close(); resolve(); return; }
                var pending = stores.length;
                var done = function(){
                  if (--pending <= 0) { db.close(); resolve(); }
                };
                stores.forEach(function(sn){
                  try {
                    var tx = db.transaction(sn, 'readwrite');
                    var st = tx.objectStore(sn);
                    try { st.delete('access-control'); } catch(e) {}
                    try { st.delete('app-config'); } catch(e) {}
                    tx.oncomplete = done;
                    tx.onerror = done;
                    tx.onabort = done;
                  } catch(e){ done(); }
                });
              } catch(e){ db.close(); resolve(); }
            };
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
      // 兜底常见库名（localforage 默认是 keyval-store）
      ['keyval-store', 'nextchat', 'keyval'].forEach(tryDelete);
      return Promise.all(promises);
    };

    // 异步清理，不阻塞脚本返回
    deleteIDBKeys().then(function(){}).catch(function(){});

    return 'ok';
  } catch (e) {
    return 'err:' + e;
  }
})();
''';
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

    // 注入脚本通过 initialUserScripts 在 AT_DOCUMENT_START 执行，
    // 首屏加载时 localStorage 就已经写好，不需要 reload。
    final userScripts = <UserScript>[];
    if (_injectScript != null && _injectScript!.isNotEmpty) {
      userScripts.add(UserScript(
        source: _injectScript!,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // 直接 reload：initialUserScripts 会自动重新执行
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
        initialUserScripts: UnmodifiableListView(userScripts),
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
          // 仅做诊断日志，不做 reload 也不做注入
          // （initialUserScripts 已在 AT_DOCUMENT_START 注入过）
          try {
            final currentUrl = await c.evaluateJavascript(
              source: "(function(){try{var s=localStorage.getItem('access-control');"
                  "if(!s)return null;var j=JSON.parse(s);"
                  "return j.state&&j.state.openaiUrl?j.state.openaiUrl:null;}"
                  "catch(e){return null;}})()",
            );
            final cleanUrl = currentUrl?.toString().replaceAll('"', '') ?? '空';
            debugPrint('[AgentUiPage] onLoadStop openaiUrl=$cleanUrl');
          } catch (e) {
            debugPrint('[AgentUiPage] onLoadStop 检查异常: $e');
          }
        },
      ),
    );
  }
}
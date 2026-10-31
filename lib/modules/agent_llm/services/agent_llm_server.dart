// lib/modules/agent_llm/services/agent_llm_server.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';
import 'package:yuanying/modules/agent_llm/services/app_context_provider.dart';
import 'package:yuanying/modules/agent_llm/services/capability_bootstrap.dart';
import 'package:yuanying/modules/agent_llm/services/tool_dispatcher.dart';
import 'package:yuanying/modules/setting/controllers/ai_config_controller.dart';

/// OpenAI 兼容网关。
///
/// 【关键设计】
///
/// 1. 双 URL：
///    - rootUrl = http://127.0.0.1:9978（注入给 NextChat 用）
///      NextChat 自己拼 rootUrl + '/v1/chat/completions' → 正确
///    - baseUrl = http://127.0.0.1:9978/v1（内部/文档用）
///
/// 2. CORS：
///    NextChat 页面在 gateway 随机端口，请求网关 9978 跨域。
///    必须处理 OPTIONS 预检 + 带 CORS 头，否则浏览器直接拒绝 POST。
///
/// 3. SSE：
///    NextChat onUserInput 硬编码 config.stream = true，用 SSE 解析器
///    解析响应。网关内部对上游永远发 stream=false（tool_calls 拦截需要
///    完整响应），处理完包装成 SSE 返回给 NextChat。
///
/// 4. tool loop + 兜底：
///    模型返回 tool_calls → 执行 → 再请求上游 → 直到纯文本。
///    模型不返回 tool_calls → registry.matchFallback（保险）。
class AgentLlmServer {
  AgentLlmServer._();
  static final AgentLlmServer instance = AgentLlmServer._();

  static const int _preferredPort = 9978;
  static const int _maxToolRounds = 3;

  // CORS 头：所有响应都要带
  static const Map<String, String> _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
  };

  // SSE 头：包含 CORS
  static final Map<String, String> _sseHeaders = {
    ..._corsHeaders,
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  };

  // JSON 头：包含 CORS
  static final Map<String, String> _jsonHeaders = {
    ..._corsHeaders,
    'Content-Type': 'application/json',
  };

  HttpServer? _server;
  int? _port;
  String? _token;

  int? get port => _port;

  /// 给 NextChat 注入用的根 URL（不带 /v1）。
  /// NextChat 会自己拼 rootUrl + '/v1/chat/completions'。
  String? get rootUrl => _port == null ? null : 'http://127.0.0.1:$_port';

  /// 内部/文档使用的 base URL（带 /v1）。
  String? get baseUrl => _port == null ? null : 'http://127.0.0.1:$_port/v1';

  String get token => _token ?? '';

  bool get isRunning => _server != null && _port != null;

  Future<String?> ensureStarted() async {
    if (isRunning) return rootUrl;

    _token = _generateToken();
    CapabilityBootstrap.initAll();

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_route);

    HttpServer? server;
    try {
      server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        _preferredPort,
        shared: false,
      );
    } catch (e) {
      debugPrint('[AgentLlmServer] 9978 被占用，切换随机端口: $e');
    }
    server ??= await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      0,
    );

    _server = server;
    _port = server.port;
    debugPrint('[AgentLlmServer] 已启动: $rootUrl (token=$_token)');
    return rootUrl;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _port = null;
    _token = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  // ============================================================
  // 路由
  // ============================================================

  Future<shelf.Response> _route(shelf.Request req) async {
    // 1. CORS 预检（必须在鉴权之前，OPTIONS 不带 Authorization）
    if (req.method == 'OPTIONS') {
      return shelf.Response.ok('', headers: _corsHeaders);
    }

    // 2. 鉴权
    if (!_isAuthorized(req)) {
      return shelf.Response.unauthorized(
        jsonEncode({'error': 'unauthorized'}),
        headers: _jsonHeaders,
      );
    }

    // 3. 路由（兼容单/双 v1）
    final path = req.url.path;
    try {
      if (path == 'v1/models' || path == 'v1/v1/models') {
        return await _handleModels(req);
      }
      if (path == 'v1/chat/completions' || path == 'v1/v1/chat/completions') {
        return await _handleChat(req);
      }
      return shelf.Response.notFound(
        jsonEncode({'error': 'not found', 'path': path}),
        headers: _jsonHeaders,
      );
    } catch (e, st) {
      debugPrint('[AgentLlmServer] handler 异常: $e\n$st');
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': 'internal: $e'}),
        headers: _jsonHeaders,
      );
    }
  }

  bool _isAuthorized(shelf.Request req) {
    final auth = req.headers['authorization'] ?? '';
    final t = _token;
    if (t == null || t.isEmpty) return false;
    return auth == 'Bearer $t';
  }

  // ============================================================
  // /v1/models
  // ============================================================

  Future<shelf.Response> _handleModels(shelf.Request req) async {
    final cfg = _readConfig();
    if (cfg.apiBaseUrl.isEmpty) {
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': 'AI 配置未填写'}),
        headers: _jsonHeaders,
      );
    }
    final upstream = _buildUpstreamUrl(cfg.apiBaseUrl, 'models');
    try {
      final resp = await http.get(
        Uri.parse(upstream),
        headers: {
          'Authorization': 'Bearer ${cfg.apiKey}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      return shelf.Response(
        resp.statusCode,
        body: resp.bodyBytes,
        headers: {
          ..._corsHeaders,
          'Content-Type':
              resp.headers['content-type'] ?? 'application/json',
        },
      );
    } catch (e) {
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _jsonHeaders,
      );
    }
  }

  // ============================================================
  // /v1/chat/completions
  // ============================================================

  Future<shelf.Response> _handleChat(shelf.Request req) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return shelf.Response.badRequest(
        body: jsonEncode({'error': 'invalid json: $e'}),
        headers: _jsonHeaders,
      );
    }

    // 记录客户端要流式还是非流式（NextChat 硬编码 stream=true）
    final clientWantsStream = body['stream'] == true;

    final cfg = _readConfig();
    if (cfg.apiBaseUrl.isEmpty || cfg.apiKey.isEmpty) {
      final err = {
        'error': 'AI 配置未填写（请在设置 → AI 助手中配置）'
      };
      if (clientWantsStream) {
        return _wrapAsSse(_buildErrorResponse(err['error']!), cfg.model);
      }
      return shelf.Response.internalServerError(
        body: jsonEncode(err),
        headers: _jsonHeaders,
      );
    }

    // 对上游：强制非流式
    body['stream'] = false;
    if (cfg.model.isNotEmpty) body['model'] = cfg.model;

    // 注入 tools + system prompt
    final toolDefs = AgentToolRegistry.instance.toolDefinitions;
    if (toolDefs.isNotEmpty) {
      body['tools'] = toolDefs;
      body['tool_choice'] = 'auto';
      _ensureSystemPrompt(body);
    }

    // 主循环（内部对上游都是非流式）
    final finalResponse = await _runToolLoop(cfg, body);
    if (finalResponse == null) {
      const errMsg = '上游请求失败，请检查 AI 配置';
      if (clientWantsStream) {
        return _wrapAsSse(_buildErrorResponse(errMsg), cfg.model);
      }
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': errMsg}),
        headers: _jsonHeaders,
      );
    }

    // 按客户端期望返回
    if (clientWantsStream) {
      return _wrapAsSse(finalResponse, cfg.model);
    }
    return shelf.Response.ok(
      jsonEncode(finalResponse),
      headers: _jsonHeaders,
    );
  }

  /// 工具调用主循环
  Future<Map<String, dynamic>?> _runToolLoop(
    _AiCfg cfg,
    Map<String, dynamic> body,
  ) async {
    var round = 0;
    while (round <= _maxToolRounds) {
      var resp = await _forwardOnce(cfg, body);
      if (resp == null && body['tool_choice'] is Map) {
        debugPrint('[AgentLlmServer] 具体 tool_choice 被拒，降级为 auto');
        body['tool_choice'] = 'auto';
        resp = await _forwardOnce(cfg, body);
      }
      if (resp == null) return null;

      final choices = resp['choices'];
      if (choices is! List || choices.isEmpty) return resp;
      final msg = (choices[0] as Map)['message'];
      final toolCalls = msg is Map ? msg['tool_calls'] : null;

      // 无 tool_calls
      if (toolCalls is! List || toolCalls.isEmpty) {
        if (round == 0) {
          final messages = _messagesOf(body);
          final matched = AgentToolRegistry.instance.matchFallback(messages);
          if (matched != null) {
            debugPrint('[AgentLlmServer] 兜底触发: '
                '${matched.tool.name} ${matched.args}');
            return await _executeForcedTool(
              cfg,
              messages,
              matched.tool.name,
              matched.args,
            );
          }
        }
        return resp;
      }

      // 达上限
      if (round == _maxToolRounds) {
        debugPrint('[AgentLlmServer] tool_calls 达上限，剥掉返回');
        final cleanedMsg = msg is Map
            ? (Map<String, dynamic>.from(msg)..remove('tool_calls'))
            : msg;
        final newChoice = Map<String, dynamic>.from(choices[0] as Map)
          ..['message'] = cleanedMsg;
        return Map<String, dynamic>.from(resp)
          ..['choices'] = [newChoice];
      }

      // 执行 tool_calls
      final messages = _messagesOf(body);
      messages.add(Map<String, dynamic>.from(msg as Map));
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final result =
            await ToolDispatcher.execute(Map<String, dynamic>.from(tc));
        messages.add({
          'role': 'tool',
          'tool_call_id': result['tool_call_id'],
          'content': result['content'],
        });
      }
      body['messages'] = messages;
      round++;
    }
    return null;
  }

  // ============================================================
  // SSE 包装
  // ============================================================

  /// 把完整 JSON 响应包装成 SSE 流。
  ///
  /// 策略：一次性把完整 content 放进一个 delta 事件，NextChat 内部
  /// 有 requestAnimationFrame 打字机，会自己逐帧显示。这样比拆分成
  /// 多个事件更稳定（避免切坏 UTF-8 字符）。
  shelf.Response _wrapAsSse(Map<String, dynamic> data, String model) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return shelf.Response.ok('data: [DONE]\n\n', headers: _sseHeaders);
    }

    final msg = (choices[0] as Map)['message'];
    final content = msg is Map ? (msg['content']?.toString() ?? '') : '';

    final id = data['id']?.toString() ??
        'chatcmpl-sse-${DateTime.now().millisecondsSinceEpoch}';
    final created = data['created'] ??
        (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final actualModel = data['model']?.toString() ?? model;

    final sb = StringBuffer();

    // 内容 chunk（一次性发送完整文本）
    if (content.isNotEmpty) {
      final chunk = {
        'id': id,
        'object': 'chat.completion.chunk',
        'created': created,
        'model': actualModel,
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'content': content},
            'finish_reason': null,
          }
        ],
      };
      sb.write('data: ${jsonEncode(chunk)}\n\n');
    }

    // 结束 chunk
    final finalChunk = {
      'id': id,
      'object': 'chat.completion.chunk',
      'created': created,
      'model': actualModel,
      'choices': [
        {
          'index': 0,
          'delta': {},
          'finish_reason': 'stop',
        }
      ],
    };
    sb.write('data: ${jsonEncode(finalChunk)}\n\n');
    sb.write('data: [DONE]\n\n');

    return shelf.Response.ok(sb.toString(), headers: _sseHeaders);
  }

  Map<String, dynamic> _buildErrorResponse(String message) {
    return {
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': message},
          'finish_reason': 'stop',
        }
      ],
    };
  }

  // ============================================================
  // system prompt
  // ============================================================

  void _ensureSystemPrompt(Map<String, dynamic> body) {
    final block = _buildSystemPrompt();
    final rawMessages = body['messages'];
    if (rawMessages is! List) {
      body['messages'] = [
        {'role': 'system', 'content': block},
      ];
      return;
    }
    final messages = rawMessages
        .map((m) => m is Map ? Map<String, dynamic>.from(m) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
    final sysIdx = messages.indexWhere((m) => m['role'] == 'system');
    if (sysIdx >= 0) {
      final existing = messages[sysIdx]['content']?.toString() ?? '';
      messages[sysIdx]['content'] = '$existing\n\n$block';
    } else {
      messages.insert(0, {'role': 'system', 'content': block});
    }
    body['messages'] = messages;
  }

  String _buildSystemPrompt() {
    final state = AppContextProvider.snapshot().toPromptBlock();
    return '''
你是「源影」应用内的 AI 助手，能调用本应用的工具帮用户完成操作。
$state

【工具选择规则】
- 影视相关动作（搜片、看详情、播放控制、状态查询）→ 必须调用对应工具
- 影视相关闲聊/评价（"XXX 好不好看"）→ 可直接回答
- 与影视无关的闲聊 → 可直接回答
- 在未调用工具时，禁止编造影视信息（演员/剧情/评分/链接等）

【禁止行为】
- 禁止"假装搜索"——不要用知识或联网能力代替工具调用
- 禁止回答"我无法操作应用"——你有工具，可以操作
''';
  }

  // ============================================================
  // 兜底执行
  // ============================================================

  Future<Map<String, dynamic>?> _executeForcedTool(
    _AiCfg cfg,
    List<Map<String, dynamic>> messages,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final callId = 'call_forced_${DateTime.now().millisecondsSinceEpoch}';

    final result =
        await ToolDispatcher.executeByName(callId, toolName, args);
    debugPrint('[AgentLlmServer] 强制结果: ${result['content']}');

    final newMessages = <Map<String, dynamic>>[
      ...messages,
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': callId,
            'type': 'function',
            'function': {
              'name': toolName,
              'arguments': jsonEncode(args),
            },
          },
        ],
      },
      {
        'role': 'tool',
        'tool_call_id': callId,
        'content': result['content']?.toString() ?? '{}',
      },
    ];

    final resp = await _forwardOnce(cfg, {
      'model': cfg.model,
      'messages': newMessages,
      'stream': false,
    });

    if (resp != null) {
      final choices = resp['choices'];
      if (choices is List && choices.isNotEmpty) {
        final m = (choices[0] as Map)['message'];
        if (m is Map && m['tool_calls'] != null) {
          final cleaned = Map<String, dynamic>.from(m)..remove('tool_calls');
          final fixed = Map<String, dynamic>.from(choices[0] as Map)
            ..['message'] = cleaned;
          return Map<String, dynamic>.from(resp)..['choices'] = [fixed];
        }
      }
      return resp;
    }
    return _buildFallbackResponse(cfg.model, toolName, args);
  }

  Map<String, dynamic> _buildFallbackResponse(
    String model,
    String toolName,
    Map<String, dynamic> args,
  ) {
    final content = switch (toolName) {
      'search_video' => '已为你打开搜索：${args['keyword'] ?? ''}',
      'open_video' => '已打开视频详情：${args['vodId'] ?? ''}',
      'get_player_state' => '已读取当前播放状态',
      'get_app_state' => '已读取壳子状态',
      _ => '已执行：$toolName',
    };
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'id': 'chatcmpl-fallback-$now',
      'object': 'chat.completion',
      'created': now,
      'model': model,
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': 'stop',
        }
      ],
    };
  }

  // ============================================================
  // 上游转发
  // ============================================================

  Future<Map<String, dynamic>?> _forwardOnce(
    _AiCfg cfg,
    Map<String, dynamic> body,
  ) async {
    final upstream = _buildUpstreamUrl(cfg.apiBaseUrl, 'chat/completions');
    try {
      debugPrint('[AgentLlmServer] → POST $upstream');
      final resp = await http.post(
        Uri.parse(upstream),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${cfg.apiKey}',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint(
          '[AgentLlmServer] ← HTTP ${resp.statusCode}: ${resp.body}',
        );
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      debugPrint('[AgentLlmServer] ← 上游请求异常: $e');
      return null;
    }
  }

  List<Map<String, dynamic>> _messagesOf(Map<String, dynamic> body) {
    final raw = body['messages'];
    if (raw is! List) return [];
    return raw
        .map((m) => m is Map ? Map<String, dynamic>.from(m) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  String _buildUpstreamUrl(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b/$path';
  }

  _AiCfg _readConfig() {
    if (Get.isRegistered<AiConfigController>()) {
      final c = Get.find<AiConfigController>().config.value;
      return _AiCfg(
        apiBaseUrl: c.apiBaseUrl.trim(),
        apiKey: c.apiKey.trim(),
        model: c.model.trim(),
      );
    }
    return const _AiCfg(apiBaseUrl: '', apiKey: '', model: '');
  }

  String _generateToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}

class _AiCfg {
  final String apiBaseUrl;
  final String apiKey;
  final String model;
  const _AiCfg({
    required this.apiBaseUrl,
    required this.apiKey,
    required this.model,
  });
}
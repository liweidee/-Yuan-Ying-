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

/// OpenAI 兼容网关。只做协议层职责：
///   1. 路由 / 鉴权
///   2. 组装 system prompt（引导词 + 状态块）
///   3. tool_calls 循环
///   4. 模型未返回 tool_calls 时调 registry.matchFallback（保险）
///
/// 不关心具体有哪些工具、也不关心工具怎么实现。工具的注册、
/// 描述、能力分类、兜底匹配都在 registry + capability 层。
///
/// 未来接 MCP：MCP loader 把工具注册进 registry 即可，本文件不改。
class AgentLlmServer {
  AgentLlmServer._();
  static final AgentLlmServer instance = AgentLlmServer._();

  static const int _preferredPort = 9978;
  static const int _maxToolRounds = 3;

  HttpServer? _server;
  int? _port;
  String? _token;

  int? get port => _port;
  String? get baseUrl => _port == null ? null : 'http://127.0.0.1:$_port/v1';
  String get token => _token ?? '';

  bool get isRunning => _server != null && _port != null;

  Future<String?> ensureStarted() async {
    if (isRunning) return baseUrl;

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
    debugPrint('[AgentLlmServer] 已启动: $baseUrl (token=$_token)');
    return baseUrl;
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
    if (!_isAuthorized(req)) {
      return shelf.Response.unauthorized(
        jsonEncode({'error': 'unauthorized'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final path = req.url.path;
    if (path == 'v1/models') return _handleModels(req);
    if (path == 'v1/chat/completions') return _handleChat(req);
    return shelf.Response.notFound(
      jsonEncode({'error': 'not found'}),
      headers: {'Content-Type': 'application/json'},
    );
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
          'Content-Type':
              resp.headers['content-type'] ?? 'application/json',
        },
      );
    } catch (e) {
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
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
        body: jsonEncode({'error': 'invalid json'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final cfg = _readConfig();
    if (cfg.apiBaseUrl.isEmpty || cfg.apiKey.isEmpty) {
      return shelf.Response.internalServerError(
        body: jsonEncode({'error': 'AI 配置未填写（请在设置 → AI 助手中配置）'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // 强制非流式（NextChat 非流式分支不发 tools，且只读 message.content）
    body['stream'] = false;
    // 强制用设置页的模型（NextChat 会话 mask 会残留旧值）
    if (cfg.model.isNotEmpty) body['model'] = cfg.model;

    // 注入 tools + system prompt（含状态块）
    final toolDefs = AgentToolRegistry.instance.toolDefinitions;
    if (toolDefs.isNotEmpty) {
      body['tools'] = toolDefs;
      body['tool_choice'] = 'auto';
      _ensureSystemPrompt(body);
    }

    // 主循环
    var round = 0;
    while (round <= _maxToolRounds) {
      var resp = await _forwardOnce(cfg, body);
      if (resp == null && body['tool_choice'] is Map) {
        // 降级重试
        debugPrint('[AgentLlmServer] 具体 tool_choice 被拒，降级为 auto');
        body['tool_choice'] = 'auto';
        resp = await _forwardOnce(cfg, body);
      }
      if (resp == null) {
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': '上游请求失败'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final choices = resp['choices'];
      if (choices is! List || choices.isEmpty) return _jsonResponse(resp);
      final msg = (choices[0] as Map)['message'];
      final toolCalls = msg is Map ? msg['tool_calls'] : null;

      // ===== 模型没返回 tool_calls =====
      if (toolCalls is! List || toolCalls.isEmpty) {
        if (round == 0) {
          // 唯一兜底入口：registry.matchFallback
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
        return _jsonResponse(resp);
      }

      // ===== 达上限 =====
      if (round == _maxToolRounds) {
        debugPrint('[AgentLlmServer] tool_calls 达上限，剥掉返回');
        final cleanedMsg = msg is Map
            ? (Map<String, dynamic>.from(msg)..remove('tool_calls'))
            : msg;
        final newChoice = Map<String, dynamic>.from(choices[0] as Map)
          ..['message'] = cleanedMsg;
        final patched = Map<String, dynamic>.from(resp)
          ..['choices'] = [newChoice];
        return _jsonResponse(patched);
      }

      // ===== 执行 tool_calls =====
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

    return shelf.Response.internalServerError(
      body: jsonEncode({'error': 'tool loop overflow'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ============================================================
  // 内部：system prompt
  // ============================================================

  /// 组装 system prompt：
  ///   - 角色定位
  ///   - 当前状态块（AppContextProvider 提供）
  ///   - 工具选择规则
  ///
  /// 如果已有 system message，追加；否则插入到最前。
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
  // 内部：兜底执行
  // ============================================================

  Future<shelf.Response> _executeForcedTool(
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

    // 二次请求上游拿最终文本（不传 tools，避免模型又调一次）
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
          final patched = Map<String, dynamic>.from(resp)
            ..['choices'] = [fixed];
          return _jsonResponse(patched);
        }
      }
      return _jsonResponse(resp);
    }
    return _jsonResponse(_buildFallbackResponse(cfg.model, toolName, args));
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
        },
      ],
    };
  }

  // ============================================================
  // 内部：上游
  // ============================================================

  Future<Map<String, dynamic>?> _forwardOnce(
    _AiCfg cfg,
    Map<String, dynamic> body,
  ) async {
    final upstream = _buildUpstreamUrl(cfg.apiBaseUrl, 'chat/completions');
    try {
      final resp = await http.post(
        Uri.parse(upstream),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${cfg.apiKey}',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 60));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('[AgentLlmServer] 上游 HTTP ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      debugPrint('[AgentLlmServer] 上游请求异常: $e');
      return null;
    }
  }

  shelf.Response _jsonResponse(Map<String, dynamic> data) {
    return shelf.Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ============================================================
  // 内部：工具
  // ============================================================

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
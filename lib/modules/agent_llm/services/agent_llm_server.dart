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

import 'package:yuanying/modules/agent_llm/services/agent_tool_executor.dart';
import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';
import 'package:yuanying/modules/setting/controllers/ai_config_controller.dart';

class AgentLlmServer {
  AgentLlmServer._();
  static final AgentLlmServer instance = AgentLlmServer._();

  static const int _preferredPort = 9978;

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
    AgentToolExecutor.instance.init();

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_route);

    // 先试固定端口 9978，失败则随机
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
        headers: {'Content-Type': resp.headers['content-type'] ?? 'application/json'},
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

    // 强制非流式（tool_calls 拦截需要完整响应）
    body['stream'] = false;

    // 注入 tools 定义（如果注册表非空）
    final toolDefs = AgentToolRegistry.instance.toolDefinitions;
    if (toolDefs.isNotEmpty) {
      body['tools'] = toolDefs;
      body['tool_choice'] = 'auto';
    }

    // 当前轮已执行的 tool_calls 数量上限（防死循环）
    const maxToolRounds = 3;
    var round = 0;

    while (round <= maxToolRounds) {
      final resp = await _forwardOnce(cfg, body);
      if (resp == null) {
        return shelf.Response.internalServerError(
          body: jsonEncode({'error': '上游请求失败'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final choices = resp['choices'];
      if (choices is! List || choices.isEmpty) {
        return _jsonResponse(resp);
      }
      final msg = (choices[0] as Map)['message'];
      final toolCalls = msg is Map ? msg['tool_calls'] : null;
      if (toolCalls is! List || toolCalls.isEmpty) {
        // 无 tool_calls，直接返回
        return _jsonResponse(resp);
      }

      if (round == maxToolRounds) {
        // 达到上限仍要调用工具，放弃执行，原样返回
        debugPrint('[AgentLlmServer] tool_calls 超过上限，停止执行');
        return _jsonResponse(resp);
      }

      // 执行 tool_calls
      final messages = List<Map<String, dynamic>>.from(
        (body['messages'] as List).cast<Map<String, dynamic>>(),
      );
      messages.add(Map<String, dynamic>.from(msg as Map));

      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final result = await AgentToolExecutor.instance
            .executeToolCall(Map<String, dynamic>.from(tc));
        messages.add({
          'role': 'tool',
          'tool_call_id': result['tool_call_id'],
          'content': result['content'],
        });
      }

      // 构造下一轮请求
      body['messages'] = messages;
      // 清掉上一轮的 tools，因为已经追加了 tool 结果
      round++;
    }

    // 理论不会走到这（round == maxToolRounds 已返回）
    return shelf.Response.internalServerError(
      body: jsonEncode({'error': 'tool loop overflow'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// 转发一次上游请求，返回解析后的 JSON；失败返回 null
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
  // 工具
  // ============================================================

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
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
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
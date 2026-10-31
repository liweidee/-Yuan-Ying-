// lib/modules/agent_ui/services/agent_ui_gateway.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';

/// agent-ui 本地静态网关
///
/// 职责：把 `{support}/plugins/agent/` 以 `/agent-ui/` 前缀托管出去，
/// 给 WebView 加载 `http://127.0.0.1:<port>/agent-ui/index.html`。
///
/// 路径映射：
/// - `/agent-ui/index.html`                → `plugins/agent/index.html`
/// - `/agent-ui/_next/static/chunks/x.js`  → `plugins/agent/_next/static/chunks/x.js`
/// - `/agent-ui/`                          → `plugins/agent/index.html`（defaultDocument）
class AgentUiGateway {
  AgentUiGateway._();
  static final AgentUiGateway instance = AgentUiGateway._();

  HttpServer? _server;
  int? _port;
  String? _pluginRoot;

  int? get port => _port;

  /// 返回 agent-ui 入口 URL；未安装插件时返回 null。
  /// 重复调用会复用已启动的服务。
  Future<String?> ensureStarted() async {
    if (_server != null && _port != null && _pluginRoot != null) {
      return _entryUrl();
    }

    // 1. 定位插件安装目录
    final plugin = InstallManager.instance.findInstalled('agent');
    if (plugin == null || plugin.installPath.isEmpty) {
      debugPrint('[AgentUiGateway] agent 插件未安装');
      return null;
    }
    final root = Directory(plugin.installPath);
    if (!root.existsSync()) {
      debugPrint('[AgentUiGateway] 插件目录不存在: ${plugin.installPath}');
      return null;
    }
    final indexFile = File(p.join(root.path, 'index.html'));
    if (!indexFile.existsSync()) {
      debugPrint('[AgentUiGateway] index.html 不存在: ${indexFile.path}');
      return null;
    }

    // 2. 起 shelf 服务
    try {
      final staticHandler = createStaticHandler(
        root.path,
        defaultDocument: 'index.html',
        serveFilesOutsidePath: false,
        listDirectories: false,
      );

      // 把 /agent-ui/ 前缀剥掉再交给 staticHandler。
      //
      // 注意：shelf.Request.url 是只读的，change() 不接受 url 参数，
      // 所以必须用 Request 构造器重建一个 Request，
      // 且 url 必须是「相对路径」的 Uri（不能以 / 开头），
      // staticHandler 用它来定位文件。
      shelf.Handler handler = (shelf.Request request) {
        final path = request.url.path;
        if (path == 'agent-ui' || path.startsWith('agent-ui/')) {
          final stripped =
              path == 'agent-ui' ? '' : path.substring('agent-ui/'.length);
          final newPath = stripped.isEmpty ? '' : stripped;

          final newRequest = shelf.Request(
            request.method,
            request.requestedUri,
            protocolVersion: request.protocolVersion,
            headers: request.headers,
            body: request.read(),
            context: request.context,
            url: Uri.parse(newPath),
          );
          return staticHandler(newRequest);
        }
        return shelf.Response.notFound('not found');
      };

      final pipeline = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler(handler);

      final server = await shelf_io.serve(
        pipeline,
        InternetAddress.loopbackIPv4,
        0,
      );

      _server = server;
      _port = server.port;
      _pluginRoot = root.path;

      debugPrint('[AgentUiGateway] 已启动: http://127.0.0.1:$_port/');
      return _entryUrl();
    } catch (e) {
      debugPrint('[AgentUiGateway] 启动失败: $e');
      return null;
    }
  }

  String? _entryUrl() {
    final port = _port;
    if (port == null) return null;
    // agent-ui 的 index.html 里资源前缀是 /agent-ui/_next/...，
    // 与 assetPrefix: '/agent-ui' 对齐。
    return 'http://127.0.0.1:$port/agent-ui/index.html';
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    _pluginRoot = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }
}
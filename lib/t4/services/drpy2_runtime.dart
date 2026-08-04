import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:yuanying/services/debug_log_service.dart';

class Drpy2Runtime {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _ctrl;
  final Dio _dio = Dio();
  bool _ready = false;
  String? _extPath;
  String? _siteKey;

  bool get isInited => _ready;

  Future<void> init({
    required String siteKey,
    required String extPath,
  }) async {
    _siteKey = siteKey;
    _extPath = extPath;

    print('[drpy2][$siteKey] ===== WebView init start =====');

    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(tempDir.path, 'drpy2'));
    if (await workDir.exists()) await workDir.delete(recursive: true);
    await workDir.create(recursive: true);

    for (final name in ['drpy-core-lite.min.js', 'drpy2.min.js', 'drpy_host.html']) {
      final data = await rootBundle.load('assets/js/lib/$name');
      await File(p.join(workDir.path, name))
          .writeAsBytes(data.buffer.asUint8List());
      print('[drpy2][$siteKey] copied $name');
    }

    _headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useHybridComposition: true,
      ),
      onWebViewCreated: (ctrl) {
        _ctrl = ctrl;
        print('[drpy2][$siteKey] WebView created');
      },
      onLoadStart: (ctrl, url) {
        print('[drpy2][$siteKey] load start: $url');
      },
      onLoadStop: (ctrl, url) {
        print('[drpy2][$siteKey] load stop: $url');
      },
      onConsoleMessage: (ctrl, msg) {
        print('[drpy2][$siteKey] [console] ${msg.message}');
      },
    );

    await _headless!.run();

    _ctrl!.addJavaScriptHandler(
      handlerName: 'drpy_ready',
      callback: (args) {
        _ready = true;
        print('[drpy2][$siteKey] WebView ready');
        return 'ok';
      },
    );
    _ctrl!.addJavaScriptHandler(
      handlerName: 'drpy_log',
      callback: (args) {
        print('[drpy2][$siteKey] js_log: ${args.first}');
        return 'ok';
      },
    );

    // ===== 关键修正：用 Uri.file() 生成正确格式的 file:///C:/... =====
    final htmlFile = File(p.join(workDir.path, 'drpy_host.html'));
    final fileUri = Uri.file(htmlFile.path).toString();
    print('[drpy2][$siteKey] loading: $fileUri');
    await _ctrl!.loadUrl(
      urlRequest: URLRequest(url: WebUri(fileUri)),
    );

    for (var i = 0; i < 100 && !_ready; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!_ready) {
      throw Exception('drpy2 WebView init timeout');
    }

    print('[drpy2][$siteKey] loading rule: $_extPath');
    String ruleJs;
    if (_extPath!.startsWith('http')) {
      // 记录请求
      DebugLogService.instance.logRequest(
        method: 'GET',
        url: _extPath!,
        source: 'drpy2',
      );
      
      final startTime = DateTime.now();
      ruleJs = (await _dio.get(
        _extPath!,
        options: Options(responseType: ResponseType.plain),
      )).data;
      
      DebugLogService.instance.logResponse(
        url: _extPath!,
        method: 'GET',
        statusCode: 200,
        responseBody: ruleJs.length > 2048 
            ? '${ruleJs.substring(0, 2048)}... (truncated, total ${ruleJs.length} chars)'
            : ruleJs,
        responseSize: ruleJs.length,
        source: 'drpy2',
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } else {
      ruleJs = await rootBundle.loadString(_extPath!);
    }
    await _ctrl!.evaluateJavascript(source: ruleJs);
    await _ctrl!.evaluateJavascript(source: "init('$_extPath')");
    print('[drpy2][$siteKey] init ok');
  }

  Future<Map<String, dynamic>> _call(String fn,
      [List<String> args = const []]) async {
    if (!_ready) throw Exception('not ready');
    final argStr = args.map((a) => "'${a.replaceAll("'", "\\'")}'").join(',');
    final raw = await _ctrl!.evaluateJavascript(
      source: "(JSON.stringify(window['$fn']($argStr)))",
    );
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> home() => _call('home');
  Future<Map<String, dynamic>> category(String tid, String pg) =>
      _call('category', [tid, pg]);
  Future<Map<String, dynamic>> detail(String ids) => _call('detail', [ids]);
  Future<Map<String, dynamic>> search(String wd) => _call('search', [wd]);

  Future<Map<String, dynamic>> play(String flag, String id) async {
    try {
      return await _call('play', [flag, id]);
    } catch (_) {
      return await _call('player', [flag, id]);
    }
  }

  void dispose() {
    _headless?.dispose();
    _ready = false;
  }
}
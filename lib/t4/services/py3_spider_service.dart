// lib/t4/services/py3_spider_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/python_runtime.dart';
import 'package:yuanying/utils/error_formatter.dart';
import 'package:yuanying/utils/business_exception.dart';

/// py3 爬虫服务
/// - Android：走 DsPlayer-Python-plugin APK（AIDL）
/// - 桌面端：走插件中心 python-win 插件（常驻 HTTP worker）
class Py3SpiderService implements ISpiderService {
  final String _siteKey;
  String? _apiUrl;
  dynamic _ext;

  /// Android：APK 内加载后的 key（loadSource 返回）
  String? _androidKey;

  Py3SpiderService(this._siteKey) {
    print('[Py3SpiderService][$_siteKey] 实例创建');
  }

  @override
  Future<void> switchSite(String apiUrl, String siteKey, {dynamic ext}) async {
    print('[Py3SpiderService][$siteKey] 切换站点: $apiUrl');
    _apiUrl = apiUrl;
    _ext = ext;
    _androidKey = null;
  }

  @override
  String? get currentKey => _siteKey;

  @override
  void setBaseUrl(String url) {}

  String get _extendStr {
    if (_ext is String) return _ext as String;
    if (_ext is Map) return json.encode(_ext);
    return _ext?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _call(String method, List<dynamic> args) async {
    if (_apiUrl == null || _apiUrl!.isEmpty) {
      throw const BusinessException('py 源路径未设置');
    }

    // Android：检测 py 插件
    if (PythonRuntime.isAndroid) {
      await _ensureAndroidPyPlugin();
      return _callAndroid(method, args);
    }

    // 桌面端：检测 python-win 插件
    if (PythonRuntime.isDesktopPlatform) {
      await _ensureDesktopPythonWin();
      return _callDesktop(method, args);
    }

    throw const BusinessException('py 源仅支持 Android / 桌面端');
  }

  /// Android 端检测 py 插件
  Future<void> _ensureAndroidPyPlugin() async {
    final reg = InstallManager.instance.findInstalled('py');
    if (reg == null) {
      throw const BusinessException(
        '未安装 Python 爬虫引擎。请前往「插件中心 → 市场」安装 py 插件后再使用 py 源。',
      );
    }
    final installed = await InstallManager.instance.isInstalledById('py');
    if (!installed) {
      throw const BusinessException(
        'Python 爬虫引擎未正确安装（可能已被系统卸载）。请前往「插件中心」重新安装 py 插件。',
      );
    }
  }

  /// 桌面端检测 python-win 插件
  Future<void> _ensureDesktopPythonWin() async {
    final reg = InstallManager.instance.findInstalled('python-win');
    if (reg == null) {
      throw const BusinessException(
        '未安装 Python 运行时（python-win）。请前往「插件中心 → 市场」安装 python-win 插件后再使用 py 源。',
      );
    }
    if (!PythonRuntime.isDesktopRuntimeAvailable()) {
      throw const BusinessException(
        'python-win 插件缺少 bin/python.exe 或 bin/py_worker_server.py，请重新安装 python-win 插件。',
      );
    }
  }

  Future<Map<String, dynamic>> _callAndroid(String method, List<dynamic> args) async {
    if (_androidKey == null) {
      // 归一化为本地路径：支持 http(s) 远程 URL（自动下载到临时目录）
      final localPath = await PythonRuntime.resolveSourcePath(_apiUrl!);
      final file = File(localPath);
      if (!await file.exists()) {
        throw BusinessException('py 源文件不存在: $_apiUrl');
      }
      final bytes = await file.readAsBytes();
      // name 用 URL 的最后一段（去掉 query），避免非法字符
      String baseName;
      final uri = Uri.tryParse(_apiUrl!);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        baseName = uri.pathSegments.last;
      } else {
        baseName = _apiUrl!.split('/').last.split('?').first;
      }
      _androidKey = await PythonRuntime.androidLoadSource(bytes, baseName);
      if (_androidKey == null) {
        throw const BusinessException('py 源加载失败（请确认已安装 DsPlayer-Python-plugin）');
      }
      debugPrint('[PY-PERF] loadSource 完成 key=$_androidKey '
          '本地路径=$localPath name=$baseName');
    }

    final raw = await PythonRuntime.androidCall(
      key: _androidKey!,
      method: method,
      proxyUrl: _extendStr,
      args: args,
    );

    // ========== 诊断日志 ==========
    debugPrint('[PY-CALL] method=$method raw_len=${raw.length}');
    debugPrint('[PY-CALL] raw_head=${raw.length > 300 ? "${raw.substring(0, 300)}..." : raw}');

    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[PY-CALL] ✗ raw 不是合法 JSON');
      throw Exception('py 返回非 JSON: $raw');
    }

    // ========== 诊断日志：result 的真实类型 ==========
    final dynamic r = envelope['result'];
    debugPrint('[PY-CALL] success=${envelope["success"]} result_type=${r.runtimeType}');
    final rStr = r?.toString() ?? 'null';
    debugPrint('[PY-CALL] result_head=${rStr.length > 400 ? "${rStr.substring(0, 400)}..." : rStr}');

    if (envelope['success'] != true) {
      throw Exception(
        ErrorFormatter.formatScriptError(envelope['error'] ?? envelope),
      );
    }

    // ========== 核心修复：处理 result 是 String / Map / List / null ==========
    final dynamic result = envelope['result'];

    // 情况 1：String（Python 侧 json.dumps 了一层，需二次解码）
    if (result is String) {
      if (result.isEmpty || result == 'null' || result == 'None') {
        debugPrint('[PY-CALL] result 是空字符串，返回空 Map');
        return {};
      }
      try {
        final decoded = jsonDecode(result);
        if (decoded is Map) {
          debugPrint('[PY-CALL] ✓ String 二次解码成功（Map），字段数=${decoded.length}');
          return Map<String, dynamic>.from(decoded);
        }
        if (decoded is List) {
          debugPrint('[PY-CALL] ✓ String 二次解码成功（List），条数=${decoded.length}');
          return {'list': decoded};
        }
        debugPrint('[PY-CALL] String 二次解码结果既非 Map 也非 List：${decoded.runtimeType}');
        return {};
      } catch (e) {
        debugPrint('[PY-CALL] ✗ result 二次 jsonDecode 失败: $e');
        // 兜底：Python dict 的 str() 用单引号，粗转换为 JSON
        try {
          final normalized = result
              .replaceAll("'", '"')
              .replaceAll('True', 'true')
              .replaceAll('False', 'false')
              .replaceAll('None', 'null');
          final decoded = jsonDecode(normalized);
          if (decoded is Map) {
            debugPrint('[PY-CALL] ✓ 粗转换成功（Map），字段数=${decoded.length}');
            return Map<String, dynamic>.from(decoded);
          }
          if (decoded is List) {
            debugPrint('[PY-CALL] ✓ 粗转换成功（List），条数=${decoded.length}');
            return {'list': decoded};
          }
        } catch (e2) {
          debugPrint('[PY-CALL] ✗ 粗转换也失败: $e2');
        }
        return {};
      }
    }

    // 情况 2：Map（旧逻辑，直接返回）
    if (result is Map) {
      debugPrint('[PY-CALL] ✓ result 直接是 Map，字段数=${result.length}');
      return Map<String, dynamic>.from(result);
    }

    // 情况 3：List（包一层 list 字段）
    if (result is List) {
      debugPrint('[PY-CALL] ✓ result 直接是 List，条数=${result.length}');
      return {'list': result};
    }

    // 情况 4：null / 其他类型
    debugPrint('[PY-CALL] result 类型未知：${result.runtimeType}，返回空 Map');
    return {};
  }

  Future<Map<String, dynamic>> _callDesktop(String method, List<dynamic> args) async {
    final params = {
      'method': method,
      'apiUrl': _apiUrl,
      'extend': _extendStr,
      'args': args,
    };
    final resultStr = await PythonRuntime.desktopRunSpiderMethod(params);
    if (resultStr.isEmpty) throw Exception('Python 返回空结果');
    final Map<String, dynamic> wrapper = jsonDecode(resultStr) as Map<String, dynamic>;
    if (wrapper['success'] == true) {
      final data = wrapper['result'];
      if (data is String) {
        try {
          return jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          return {'list': []};
        }
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      return {};
    }
    throw Exception(
      ErrorFormatter.formatScriptError(wrapper['error'] ?? '未知错误'),
    );
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return await _call('home', [filter != 0]);
  }

  @override
  Future<Map<String, dynamic>> fetchCate(String cateId, int page, {String? ext}) async {
    final extend = <String, dynamic>{};
    if (ext != null && ext.isNotEmpty) {
      try { extend.addAll(jsonDecode(ext) as Map<String, dynamic>); } catch (_) {}
    }
    return await _call('category', [cateId, page, false, extend]);
  }

  @override
  Future<Map<String, dynamic>> search(String wd, int page, {int quick = 0}) async {
    return await _call('search', [wd, quick == 1, page]);
  }

  @override
  Future<VideoDetail?> getDetail({required String vodId, required String pwd}) async {
    final result = await _call('detail', [[vodId]]);
    final list = result['list'];
    if (list is List && list.isNotEmpty) {
      return VideoDetail.fromJson(Map<String, dynamic>.from(list[0] as Map));
    }
    return null;
  }

  @override
  Future<PlayUrl?> getPlayUrl({required String playParams, required String flag, required String pwd}) async {
    final result = await _call('play', [flag, playParams, []]);
    if (result.isEmpty) return null;
    return PlayUrl.fromJson(result);
  }

  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return await _call('detail', [[ids]]);
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    return await _call('play', [flag ?? '', play, []]);
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    return await _call('search', [wd, quick == 1, page]);
  }

  Future<void> unload() async {
    if (PythonRuntime.isAndroid) {
      if (_androidKey != null) {
        await PythonRuntime.androidUnload(_androidKey!);
      }
    } else if (PythonRuntime.isDesktopPlatform) {
      if (_apiUrl != null && _apiUrl!.isNotEmpty) {
        await PythonRuntime.desktopUnloadSource(_apiUrl!);
      }
    }
    _androidKey = null;
    print('[Py3SpiderService][$_siteKey] unload');
  }
}
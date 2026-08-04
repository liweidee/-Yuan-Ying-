import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/t4/services/python_runtime.dart';

/// py3 爬虫服务实现类
/// 通过调用 PythonRuntime 启动子进程执行爬虫脚本
/// 注意：仅在桌面端有效，移动端会抛出异常
class Py3SpiderService implements ISpiderService {
  final String _siteKey;
  String? _apiUrl;
  dynamic _ext;

  Py3SpiderService(this._siteKey) {
    print('[Py3SpiderService][$_siteKey] 实例创建');
  }

  @override
  Future<void> switchSite(String apiUrl, String siteKey, {dynamic ext}) async {
    print('[Py3SpiderService][$siteKey] 切换站点');
    _apiUrl = apiUrl;
    _ext = ext;
  }

  @override
  String? get currentKey => _siteKey;

  @override
  void setBaseUrl(String url) {}

  /// 内部调用 Python 的通用方法
  /// 将方法名、API URL、扩展参数等封装为 Map，传递给 PythonRuntime
  Future<Map<String, dynamic>> _callPython(String method, {Map<String, dynamic>? args}) async {
    // 平台检查：移动端不支持，直接抛出异常
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw Exception('py3 爬虫仅支持桌面端（Windows / macOS / Linux）');
    }

    if (_apiUrl == null || _apiUrl!.isEmpty) {
      throw Exception('API URL 未设置');
    }

    // 将 extend 统一转换为 JSON 字符串（保证可哈希）
    String extendStr;
    if (_ext is String) {
      extendStr = _ext;
    } else if (_ext is Map) {
      extendStr = json.encode(_ext);
    } else {
      extendStr = _ext?.toString() ?? '';
    }

    final params = {
      'method': method,
      'apiUrl': _apiUrl,
      'extend': extendStr,
      'args': args ?? {},
    };

    // 调用 PythonRuntime 执行
    final resultStr = await PythonRuntime.runSpiderMethod(params);

    print('[Py3SpiderService] Python 原始返回长度: ${resultStr.length}');

    if (resultStr.isEmpty) {
      throw Exception('Python 返回空结果');
    }

    try {
      // 第一层解析：Python 返回的包装 JSON
      final Map<String, dynamic> result = json.decode(resultStr);
      if (result['success'] == true) {
        // 第二层解析：实际业务数据（存于 data 字段，为 JSON 字符串）
        final data = result['data'];
        if (data is String) {
          return json.decode(data);
        } else {
          return data ?? {};
        }
      } else {
        throw Exception(result['error'] ?? '未知错误');
      }
    } catch (e) {
      print('[Py3SpiderService] JSON 解析失败，完整内容: $resultStr');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchHome({int filter = 1}) async {
    return await _callPython('homeContent', args: {'filter': filter});
  }

  @override
  Future<Map<String, dynamic>> fetchCate(
    String cateId,
    int page, {
    String? ext,
  }) async {
    final args = {
      'tid': cateId,
      'pg': page.toString(),
      'filter': false,
      'extend': {},
    };
    if (ext != null && ext.isNotEmpty) {
      try {
        args['extend'] = json.decode(ext);
      } catch (_) {}
    }
    return await _callPython('categoryContent', args: args);
  }

  @override
  Future<Map<String, dynamic>> search(
    String wd,
    int page, {
    int quick = 0,
  }) async {
    return await _callPython('searchContent', args: {
      'key': wd,
      'pg': page.toString(),
    });
  }

  @override
  Future<VideoDetail?> getDetail({
    required String vodId,
    required String pwd,
  }) async {
    final result = await _callPython('detailContent', args: {
      'ids': [vodId],
    });
    final list = result['list'];
    if (list is List && list.isNotEmpty) {
      return VideoDetail.fromJson(list[0]);
    }
    return null;
  }

  @override
  Future<PlayUrl?> getPlayUrl({
    required String playParams,
    required String flag,
    required String pwd,
  }) async {
    final result = await _callPython('playerContent', args: {
      'flag': flag,
      'videoId': playParams,
      'vipFlags': [],
    });
    return PlayUrl.fromJson(result);
  }

  // ===== 以下为接口要求但实际未使用的额外方法 =====
  @override
  Future<Map<String, dynamic>> fetchDetail(String ids) async {
    return await _callPython('detailContent', args: {
      'ids': ids,
    });
  }

  @override
  Future<Map<String, dynamic>> fetchPlayUrl(String play, {String? flag}) async {
    return await _callPython('playerContent', args: {
      'flag': flag ?? '',
      'videoId': play,
      'vipFlags': [],
    });
  }

  @override
  Future<Map<String, dynamic>> searchDirect({
    required String baseUrl,
    required dynamic ext,
    required String wd,
    required int page,
    int quick = 0,
  }) async {
    // 直接使用 search 方法
    return await _callPython('searchContent', args: {
      'key': wd,
      'pg': page.toString(),
    });
  }

  /// 卸载方法（空实现）
  Future<void> unload() async {
    print('[Py3SpiderService][$_siteKey] unload 调用（无操作）');
  }
}
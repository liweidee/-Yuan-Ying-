// lib/modules/action/services/action_service.dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../../t4/services/source_manager.dart';
import '../../../t4/services/t4_api_service.dart';
import '../models/action_config.dart';
import '../models/action_result.dart';
import '../models/action_type.dart';

/// Action 服务
/// 对应 DrPlayer 的 module.js 中的 executeAction 函数
class ActionService extends GetxService {
  late final Dio _dio;
  final SourceManager _sourceManager = Get.find<SourceManager>();

  ActionService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json;charset=UTF-8',
      },
    ));
  }

  /// 执行 Action
  /// 对应 DrPlayer 的 executeAction(module, data)
  Future<dynamic> executeAction(
    String module,
    Map<String, dynamic> actionData,
  ) async {
    final action = actionData['action']?.toString() ?? '';
    final value = actionData['value'];
    final extend = actionData['extend'];
    final apiUrl = actionData['apiUrl']?.toString();

    final requestData = <String, dynamic>{
      'ac': 'action',
      'action': action,
    };

    if (value != null) {
      if (value is String) {
        // 如果已经是字符串，直接使用（可能已是 JSON）
        requestData['value'] = value;
      } else {
        // Map、List、基本类型都转为 JSON 字符串
        requestData['value'] = jsonEncode(value);
      }
    }

    // 添加 extend（如果有）
    final processedExtend = _processExtendParam(extend);
    if (processedExtend != null && processedExtend.isNotEmpty) {
      requestData['extend'] = processedExtend;
    }

    print('ActionService.executeAction 调用:');
    print('  module: $module');
    print('  requestData: $requestData');
    print('  apiUrl: $apiUrl');

    try {
      dynamic response;

      if (apiUrl != null && apiUrl.isNotEmpty) {
        // 直接调用 API
        if (apiUrl.endsWith('.json')) {
          final result = await _dio.get(
            apiUrl,
            options: Options(
              headers: {
                'Accept': 'application/json',
              },
            ),
          );
          response = result.data;
        } else {
          final result = await _dio.post(
            apiUrl,
            data: requestData,
          );
          response = result.data;
        }
      } else {
        // 使用代理方式：/api/:module
        final baseUrl = _getBaseUrl(module);
        final url = '$baseUrl';
        final result = await _dio.post(
          url,
          data: requestData,
        );
        response = result.data;
      }

      print('ActionService.executeAction 响应: $response');
      return response;
    } on DioException catch (e) {
      print('ActionService.executeAction DioException: ${e.message}');
      throw Exception(e.message ?? '网络请求失败');
    } catch (e) {
      print('ActionService.executeAction 异常: $e');
      rethrow;
    }
  }

  /// 获取基础 URL
  String _getBaseUrl(String module) {
    final site = _sourceManager.currentSite.value;
    if (site == null) {
      throw Exception('请先配置接口源');
    }

    final api = site['api']?.toString();
    if (api == null || api.isEmpty) {
      throw Exception('站点 API 地址为空');
    }

    final uri = Uri.parse(api);
    return uri.replace(queryParameters: {}).toString();
  }

  /// 处理 extend 参数
  String? _processExtendParam(dynamic extend) {
    if (extend == null) return null;

    if (extend is String) {
      return extend.isEmpty ? null : extend;
    }

    if (extend is Map) {
      try {
        return jsonEncode(extend);
      } catch (_) {
        return null;
      }
    }

    return extend.toString();
  }

  /// 解析 Action 响应
  ActionResult parseResponse(dynamic response) {
    if (response is String) {
      try {
        final decoded = jsonDecode(response);
        return ActionResult.fromJson(decoded);
      } catch (e) {
        return ActionResult(success: true, toast: response);
      }
    }
    return ActionResult.fromJson(response);
  }

  /// 快捷方法：执行 Action 并自动解析结果
  Future<ActionResult> executeAndParse(
    String module,
    Map<String, dynamic> actionData,
  ) async {
    try {
      final response = await executeAction(module, actionData);
      return parseResponse(response);
    } catch (e) {
      return ActionResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 获取首页数据（复用 T4ApiService）
  Future<Map<String, dynamic>> getHomeData({
    int filter = 1,
    String? extend,
    String? apiUrl,
  }) async {
    final t4ApiService = Get.find<T4ApiService>();
    return await t4ApiService.fetchHome(filter: filter);
  }

  /// 获取分类数据（复用 T4ApiService）
  Future<Map<String, dynamic>> getCategoryData({
    required String cateId,
    int page = 1,
    String? ext,
    String? extend,
    String? apiUrl,
  }) async {
    final t4ApiService = Get.find<T4ApiService>();
    return await t4ApiService.fetchCate(cateId, page, ext: ext);
  }

  /// 获取视频详情（复用 T4ApiService）
  Future<Map<String, dynamic>> getVideoDetail({
    required String ids,
    String? extend,
    String? apiUrl,
  }) async {
    final t4ApiService = Get.find<T4ApiService>();
    return await t4ApiService.fetchDetail(ids);
  }

  /// 搜索视频（复用 T4ApiService）
  Future<Map<String, dynamic>> searchVideos({
    required String wd,
    int page = 1,
    String? extend,
    String? apiUrl,
  }) async {
    final t4ApiService = Get.find<T4ApiService>();
    return await t4ApiService.search(wd, page);
  }

  /// 获取播放地址（复用 T4ApiService）
  Future<Map<String, dynamic>> getPlayUrl({
    required String play,
    String? flag,
    String? extend,
    String? apiUrl,
  }) async {
    final t4ApiService = Get.find<T4ApiService>();
    return await t4ApiService.fetchPlayUrl(play, flag: flag);
  }
}
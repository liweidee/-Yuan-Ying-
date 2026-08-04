// lib/modules/action/models/action_result.dart
import 'dart:convert';
import 'action_config.dart';

class ActionResult {
  final bool success;
  final dynamic data;
  final ActionConfig? nextAction;
  final String? toast;
  final Map<String, dynamic>? specialAction;
  final String? error;

  ActionResult({
    this.success = true,
    this.data,
    this.nextAction,
    this.toast,
    this.specialAction,
    this.error,
  });

  factory ActionResult.fromJson(dynamic json) {
    if (json is String) {
      return ActionResult(success: true, toast: json);
    }

    if (json is Map<String, dynamic>) {
      if (json.containsKey('action')) {
        dynamic actionData = json['action'];
        final toast = json['toast']?.toString();

        if (actionData is String) {
          try {
            actionData = jsonDecode(actionData);
          } catch (_) {
            // 核心修复：非 JSON 字符串，包装为标准 specialAction 结构
            return ActionResult(
              success: true,
              specialAction: {'actionId': actionData},
            );
          }
        }

        if (actionData is Map<String, dynamic>) {
          final actionId = actionData['actionId']?.toString() ?? '';
          if (_isReservedSpecialAction(actionId)) {
            return ActionResult(
              success: true,
              specialAction: actionData,
              toast: toast,
            );
          } else {
            try {
              final config = ActionConfig.fromJson(actionData);
              if (config.actionId.isNotEmpty) {
                return ActionResult(
                  success: true,
                  nextAction: config,
                  toast: toast,
                );
              }
            } catch (e) {
              return ActionResult(success: true, data: actionData, toast: toast);
            }
          }
        }
      }

      if (json.containsKey('code') && json['code'] != 200 && json['code'] != 0) {
        return ActionResult(
          success: false,
          error: json['msg']?.toString() ?? json['message']?.toString() ?? '操作失败',
        );
      }

      final data = json['data'] ?? json;
      return ActionResult(
        success: true,
        data: data,
        toast: json['toast']?.toString() ?? json['msg']?.toString(),
      );
    }

    return ActionResult(success: true, data: json);
  }

  static bool _isReservedSpecialAction(String actionId) {
    const reserved = [
      '__keep__',
      '__close__',
      '__detail__',
      '__copy__',
      '__self_search__',
      '__refresh_list__',
      '__ktvplayer__',
    ];
    return reserved.contains(actionId);
  }
}
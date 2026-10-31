// lib/modules/agent_llm/services/tool_dispatcher.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';

/// 工具调度器：把 OpenAI 格式的 tool_call 转成执行 + tool message。
///
/// 职责单一：解析 tool_call → 查 registry → 执行 → 包装成 OpenAI
/// 的 tool message 格式（带 tool_call_id / content）。
///
/// 不关心工具内部实现，也不知道有哪些工具——全部通过 registry。
abstract final class ToolDispatcher {
  /// 执行单个 tool_call，返回 OpenAI 的 tool message 结构：
  /// {tool_call_id: ..., content: '<json string>'}
  static Future<Map<String, dynamic>> execute(
    Map<String, dynamic> toolCall,
  ) async {
    final id = toolCall['id']?.toString() ?? '';
    final name = _extractName(toolCall);
    final args = _extractArgs(toolCall);

    final tool = AgentToolRegistry.instance.find(name);
    if (tool == null) {
      return _errorMessage(id, 'unknown tool: $name');
    }

    try {
      final result = await tool.execute(args);
      return {
        'tool_call_id': id,
        'content': jsonEncode(result),
      };
    } catch (e, st) {
      debugPrint('[ToolDispatcher] $name 执行异常: $e\n$st');
      return _errorMessage(id, e.toString());
    }
  }

  /// 直接按 name + args 执行（供网关兜底路径使用）
  static Future<Map<String, dynamic>> executeByName(
    String id,
    String name,
    Map<String, dynamic> args,
  ) async {
    final tool = AgentToolRegistry.instance.find(name);
    if (tool == null) {
      return _errorMessage(id, 'unknown tool: $name');
    }
    try {
      final result = await tool.execute(args);
      return {
        'tool_call_id': id,
        'content': jsonEncode(result),
      };
    } catch (e, st) {
      debugPrint('[ToolDispatcher] $name 执行异常: $e\n$st');
      return _errorMessage(id, e.toString());
    }
  }

  static String _extractName(Map<String, dynamic> toolCall) {
    final fn = toolCall['function'];
    if (fn is Map) return fn['name']?.toString() ?? '';
    return '';
  }

  static Map<String, dynamic> _extractArgs(Map<String, dynamic> toolCall) {
    final fn = toolCall['function'];
    if (fn is! Map) return {};
    final rawArgs = fn['arguments'];
    if (rawArgs is Map) return Map<String, dynamic>.from(rawArgs);
    if (rawArgs is String && rawArgs.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (e) {
        debugPrint('[ToolDispatcher] args 解析失败: $e');
      }
    }
    return {};
  }

  static Map<String, dynamic> _errorMessage(String id, String error) {
    return {
      'tool_call_id': id,
      'content': jsonEncode({'ok': false, 'error': error}),
    };
  }
}
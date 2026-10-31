// lib/modules/agent_llm/services/agent_tool_registry.dart

import 'package:flutter/foundation.dart';

/// 工具兜底意图匹配器。
///
/// 当模型未返回 tool_calls 时，网关按注册顺序调用各工具的 matcher，
/// 第一个返回非 null 的即命中，网关强制触发该工具。
///
/// - 返回 Map 表示命中，Map 是执行该工具需要的参数；
/// - 返回 null 表示不命中，由下一个工具继续匹配。
///
/// 【定位】这是"模型犯傻"时的保险，不是主路径。对齐 DsPlayer 的做法
/// 是信任模型（好描述 + 好状态），matcher 只给最高频的 2-3 个工具用，
/// 其他工具一律 null。
typedef ToolFallbackMatcher = Map<String, dynamic>? Function(
  List<Map<String, dynamic>> messages,
);

class AgentTool {
  /// 工具唯一名（模型调用时用）
  final String name;

  /// 一句话描述
  final String description;

  /// 使用指南（when / when not / examples），会被拼到模型看到的 description 里。
  /// 对齐 DsPlayer：模型靠这个判断"什么时候该调我"。
  final String? usageGuide;

  /// JSON Schema 参数定义
  final Map<String, dynamic> parameters;

  /// 执行函数
  final Future<dynamic> Function(Map<String, dynamic> args) execute;

  /// 兜底意图匹配器。null 表示不支持兜底（纯靠模型主动调用）。
  final ToolFallbackMatcher? fallbackIntentMatcher;

  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
    this.usageGuide,
    this.fallbackIntentMatcher,
  });

  /// 拼给模型看的完整 description
  String get fullDescription {
    if (usageGuide == null || usageGuide!.isEmpty) return description;
    return '$description\n\n$usageGuide';
  }
}

class AgentToolRegistry {
  AgentToolRegistry._();
  static final AgentToolRegistry instance = AgentToolRegistry._();

  final Map<String, AgentTool> _tools = {};
  final List<AgentTool> _ordered = [];

  void register(AgentTool tool) {
    if (_tools.containsKey(tool.name)) {
      _ordered.removeWhere((t) => t.name == tool.name);
    }
    _tools[tool.name] = tool;
    _ordered.add(tool);
  }

  void clear() {
    _tools.clear();
    _ordered.clear();
  }

  bool get isEmpty => _tools.isEmpty;

  int get toolCount => _tools.length;

  List<String> get toolNames => _ordered.map((t) => t.name).toList();

  /// 生成给上游的 toolDefinitions
  List<Map<String, dynamic>> get toolDefinitions => _ordered
      .map((t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.fullDescription,
              'parameters': t.parameters,
            },
          })
      .toList();

  AgentTool? find(String name) => _tools[name];

  /// 遍历所有工具的 fallbackIntentMatcher，第一个命中的返回。
  ///
  /// 这是网关"模型没调工具时"的唯一兜底入口——注册表不关心具体有哪些
  /// 工具、也不关心每个工具怎么匹配，全部由工具自己的 matcher 决定。
  /// 未来加 MCP 工具时不带 matcher，就不会被兜底触发。
  ({AgentTool tool, Map<String, dynamic> args})? matchFallback(
    List<Map<String, dynamic>> messages,
  ) {
    for (final tool in _ordered) {
      final matcher = tool.fallbackIntentMatcher;
      if (matcher == null) continue;
      try {
        final args = matcher(messages);
        if (args != null) {
          return (tool: tool, args: args);
        }
      } catch (e) {
        debugPrint('[AgentToolRegistry] matcher ${tool.name} 异常: $e');
      }
    }
    return null;
  }
}
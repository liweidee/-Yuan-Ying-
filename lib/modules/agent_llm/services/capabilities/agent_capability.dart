// lib/modules/agent_llm/services/capabilities/agent_capability.dart

import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';

/// 能力抽象。对应 DsPlayer 的六大类（点播 / 源管理 / 源开发 /
/// 直播音乐书架 / 调试 / 遥控）。
///
/// 加新能力的步骤：
///   1. 新建 XxxCapability extends AgentCapability
///   2. 实现 register() 把工具注册到 registry
///   3. 在 CapabilityBootstrap.initAll() 里加一行
///
/// agent_llm_server.dart 一行不改。
abstract class AgentCapability {
  /// 能力标识（如 'playback' / 'source' / 'live'）
  /// 用于日志、诊断、未来的 UI 分组
  String get id;

  /// 展示名称（如 '点播' / '源管理'）
  String get displayName;

  /// 一句话描述（用于 system prompt 中列出可用能力）
  String get summary;

  /// 注册本能力下所有工具
  void register(AgentToolRegistry registry);
}
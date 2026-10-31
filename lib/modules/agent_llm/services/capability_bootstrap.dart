// lib/modules/agent_llm/services/capability_bootstrap.dart

import 'package:flutter/foundation.dart';

import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';
import 'package:yuanying/modules/agent_llm/services/capabilities/agent_capability.dart';
import 'package:yuanying/modules/agent_llm/services/capabilities/playback_capability.dart';

/// 能力编排入口。启动时注册所有能力下的工具。
///
/// 对齐 DsPlayer 六大类：
///   点播（PlaybackCapability）           ✅ 已实现
///   源管理（SourceCapability）           🚧 待实现
///   源开发（SourceDevCapability）        🚧 待实现
///   直播                                 🚧 待实现
///   调试（DebugCapability）              🚧 待实现
///
/// 加新能力：新建 XxxCapability，然后在 initAll 里加一行。
/// agent_llm_server.dart 不改。
abstract final class CapabilityBootstrap {
  static bool _initialized = false;

  static void initAll() {
    if (_initialized) return;
    _initialized = true;

    final registry = AgentToolRegistry.instance;
    registry.clear();

    final capabilities = <AgentCapability>[
      PlaybackCapability(),
      // SourceCapability(),
      // SourceDevCapability(),
      // LiveCapability(),
      // DebugCapability(),
      // RemoteCapability(),
    ];

    for (final cap in capabilities) {
      cap.register(registry);
      debugPrint(
        '[CapabilityBootstrap] 已注册能力 ${cap.displayName}(${cap.id})',
      );
    }

    debugPrint(
      '[CapabilityBootstrap] 共注册 ${registry.toolCount} 个工具: '
      '${registry.toolNames.join(", ")}',
    );
  }
}
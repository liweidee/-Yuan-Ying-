// lib/modules/agent_llm/services/app_context_provider.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/agent_llm/models/app_context.dart';
import 'package:yuanying/modules/agent_llm/models/playback_context.dart';
import 'package:yuanying/t4/services/source_manager.dart';

/// 应用状态探测。每轮对话前由 AgentLlmServer 调用，生成状态块注入
/// system prompt，让模型能理解"下一集"、"切源"这类隐含上下文的指令。
///
/// 设计原则：
///   - 只读，不触发任何副作用（不会去请求网络 / 启动服务）
///   - 拿不到的字段就不写（不用默认值糊弄模型）
///   - 各能力如果需要 dump 更多信息，可以扩展 AppContext.extras
abstract final class AppContextProvider {
  static AppContext snapshot() {
    final route = Get.currentRoute;
    return AppContext(
      route: route,
      routeLabel: _routeLabel(route),
      playback: PlaybackContextRegistry.instance.current,
      extras: _collectExtras(),
    );
  }

  static String _routeLabel(String route) {
    const map = {
      '/': '首页',
      '/home': '首页',
      '/search': '搜索页',
      '/searchResult': '搜索结果页',
      '/detail': '详情页',
      '/video': '播放页',
      '/live': '直播页',
      '/favorite': '收藏页',
      '/history': '历史页',
      '/agentUi': 'AI 助手',
      '/setting': '设置页',
    };
    return map[route] ?? route;
  }

  static Map<String, dynamic> _collectExtras() {
    final extras = <String, dynamic>{};
    try {
      final sites = _readSourceSites();
      if (sites != null && sites.isNotEmpty) {
        extras['源数量'] = sites.length;
      }
    } catch (e) {
      debugPrint('[AppContextProvider] collectExtras 异常: $e');
    }
    return extras;
  }

  /// 通过 SourceManager 读取源列表（防御性：拿不到返回 null）
  static List<dynamic>? _readSourceSites() {
    try {
      if (!Get.isRegistered<SourceManager>()) return null;
      final sm = Get.find<SourceManager>();
      final sites = sm.sites;
      if (sites is List) return sites;
      return null;
    } catch (e) {
      debugPrint('[AppContextProvider] readSourceSites 异常: $e');
      return null;
    }
  }
}
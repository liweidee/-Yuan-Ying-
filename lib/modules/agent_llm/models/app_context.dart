// lib/modules/agent_llm/models/app_context.dart

import 'package:yuanying/modules/agent_llm/models/playback_context.dart';

/// 应用状态快照，每轮对话前由 AppContextProvider 生成，
/// 注入 system prompt 让模型知道"用户现在在哪、在干什么"。
///
/// 当前你的壳子状态：
///   - 在点播页，当前源 abts(PY)，加载了 9 个分类、17 条影片列表
///   - 在播放页，正在播放《XXX》第 N 集
class AppContext {
  /// 当前路由（如 '/detail' / '/video' / '/'）
  final String route;

  /// 路由的人类可读名（如 '详情页' / '播放页'）
  final String routeLabel;

  /// 正在播放的上下文，null 表示未在播放
  final PlaybackContext? playback;

  /// 附加信息（未来扩展：当前源名、分类列表、影片数量……）
  /// 各 Capability 可以往这里写自己关心的字段，Prompt 生成时统一拼。
  final Map<String, dynamic> extras;

  const AppContext({
    required this.route,
    required this.routeLabel,
    this.playback,
    this.extras = const {},
  });

  /// 生成注入 system prompt 的状态文本块
  String toPromptBlock() {
    final sb = StringBuffer();
    sb.writeln();
    sb.writeln('【当前壳子状态】');
    sb.writeln('- 页面：$routeLabel');

    if (playback != null) {
      final p = playback!;
      sb.writeln('- 正在播放：${p.vodName} · ${p.episodeName}'
          '（来源 ${p.siteName}）');
    } else {
      sb.writeln('- 播放状态：未在播放');
    }

    for (final e in extras.entries) {
      sb.writeln('- ${e.key}：${e.value}');
    }
    return sb.toString();
  }
}
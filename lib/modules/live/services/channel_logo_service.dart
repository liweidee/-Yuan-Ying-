// lib/modules/live/services/channel_logo_service.dart

import 'package:yuanying/utils/channel_name_utils.dart';

/// 频道 Logo URL 解析服务
class ChannelLogoService {
  /// 根据配置的 logo 模板和频道名，解析出实际 URL
  ///
  /// [template] 例如：
  ///   https://raw.githubusercontent.com/CCSH/IPTV/refs/heads/main/logo/{频道名}.png
  ///
  /// [channelName] 例如：CCTV1综合 / 东方卫视
  ///
  /// 返回 null 表示无法解析（模板为空）
  static String? resolve({
    required String? template,
    required String channelName,
  }) {
    if (template == null || template.isEmpty) return null;

    // 没有占位符 → 原样返回（用户可能直接配了一个固定 URL）
    final hasPlaceholder =
        template.contains('{频道名}') || template.contains('{name}');
    if (!hasPlaceholder) return template;

    final normalized = ChannelNameUtils.normalize(channelName);
    // URL 编码：中文频道名必须编码，ASCII 频道名编码后不变
    final encoded = Uri.encodeComponent(normalized);

    return template
        .replaceAll('{频道名}', encoded)
        .replaceAll('{name}', encoded);
  }
}
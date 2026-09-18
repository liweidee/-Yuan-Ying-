// lib/utils/channel_name_utils.dart

/// 频道名归一化工具
///
/// 用于把直播源里的频道名转成 Logo 仓库使用的文件名格式。
///
/// 规则：
///   - CCTV1综合 / cctv1综合 / CCTV-1 / CCTV1  → CCTV1
///   - CCTV5+ / cctv5+                          → CCTV5+
///   - CCTV4K / cctv4k                          → CCTV4K
///   - 东方卫视 / 湖南卫视                       → 东方卫视 / 湖南卫视（不变）
///   - 北京卫视高清                              → 北京卫视
class ChannelNameUtils {
  /// 归一化频道名
  static String normalize(String name) {
    if (name.isEmpty) return name;

    // 1. 转大写 + 去所有空白
    var s = name.toUpperCase().replaceAll(RegExp(r'\s+'), '');

    // 2. 去掉 CCTV 后面的分隔符：CCTV-1 → CCTV1，CCTV_1 → CCTV1
    s = s.replaceAll(RegExp(r'CCTV[-_·]'), 'CCTV');

    // 3. 匹配 CCTV + 数字(+可选) 开头
    //    分组：数字 / 可选加号 / 后缀
    final cctvMatch = RegExp(r'^CCTV(\d+)(\+?)(.*)$').firstMatch(s);
    if (cctvMatch != null) {
      final num = cctvMatch.group(1)!;
      final plus = cctvMatch.group(2) ?? '';
      final suffix = cctvMatch.group(3) ?? '';
      final cleaned = _stripSuffix(suffix);
      return 'CCTV$num$plus$cleaned';
    }

    // 4. 非 CCTV 频道：只去掉常见后缀
    return _stripSuffix(s);
  }

  /// 去掉频道名后缀
  ///
  /// 注意：
  ///   - 顺序重要，长的先匹配（"高清频道" 要在 "高清" 之前）
  ///   - 只去掉"明确不属于频道名本身"的后缀
  ///   - 不去 "卫视"、"体育"、"新闻" 等属于频道名一部分的词
  static String _stripSuffix(String s) {
    if (s.isEmpty) return s;

    const suffixes = <String>[
      // 画质后缀（长 → 短）
      '在线直播',
      '高清频道', '超清频道', '标清频道',
      '高清', '超清', '标清', '蓝光',
      '4K', '8K', 'HD',
      // 频道后缀
      '频道',
      // 央视频道套数后缀（CCTV1综合 → CCTV1）
      '综合',
      '一套', '二套', '三套', '四套', '五套',
      '六套', '七套', '八套', '九套', '十套',
      '十一套', '十二套', '十三套', '十四套', '十五套',
      '十六套', '十七套',
    ];

    var r = s;
    // 循环去尾，处理 "CCTV1综合高清" 这种叠加后缀
    var changed = true;
    while (changed) {
      changed = false;
      for (final suffix in suffixes) {
        if (r.endsWith(suffix) && r.length > suffix.length) {
          r = r.substring(0, r.length - suffix.length);
          changed = true;
        }
      }
    }
    return r;
  }
}
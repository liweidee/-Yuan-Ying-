// lib/modules/live/services/live_parser_service.dart
import 'package:yuanying/modules/live/models/live_channel.dart';

class LiveParserService {
  /// 解析 TVBox 标准 .txt 格式
  static List<LiveChannel> parseTvBoxTxt(String content) {
    final lines = content.split('\n');
    final channels = <LiveChannel>[];
    String? currentGroup;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // 分组定义：#genre#央视
      if (line.startsWith('#genre#')) {
        currentGroup = line.substring(7).trim();
        continue;
      }

      // 频道行：名称,url
      if (line.contains(',')) {
        final parts = line.split(',');
        if (parts.length >= 2) {
          final name = parts[0].trim();
          final url = parts.sublist(1).join(',').trim();
          if (url.isNotEmpty && (url.startsWith('http') || url.startsWith('rtmp') || url.startsWith('https'))) {
            channels.add(LiveChannel(
              name: name,
              url: url,
              group: currentGroup ?? '未分组',
            ));
          }
        }
      }
    }
    return channels;
  }

  /// 解析标准 M3U 格式
  static List<LiveChannel> parseM3U(String content) {
    final lines = content.split('\n');
    final channels = <LiveChannel>[];
    String? currentName;
    String? currentGroup;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // 示例：#EXTINF:-1 tvg-logo="logo.png" group-title="央视",CCTV-1
        final nameMatch = RegExp(r',([^,]+)$').firstMatch(line);
        currentName = nameMatch?.group(1)?.trim() ?? '未知频道';

        // 提取 group-title
        final groupMatch = RegExp(r'group-title="([^"]+)"').firstMatch(line);
        currentGroup = groupMatch?.group(1)?.trim() ?? '未分组';
      } else if (line.startsWith('http') || line.startsWith('rtmp')) {
        // 遇到 URL，如果前面有 #EXTINF 则配对
        if (currentName != null) {
          channels.add(LiveChannel(
            name: currentName!,
            url: line,
            group: currentGroup ?? '未分组',
          ));
          currentName = null;
          currentGroup = null;
        }
      }
    }
    return channels;
  }

  /// 自动检测格式（根据内容特征）
  static String detectFormat(String content) {
    if (content.contains('#EXTM3U') || content.contains('#EXTINF:')) {
      return 'm3u';
    }
    // 默认按 txt 处理
    return 'txt';
  }

  /// 统一解析入口
  static List<LiveChannel> parse(String content, {String? format}) {
    format ??= detectFormat(content);
    if (format == 'm3u') {
      return parseM3U(content);
    } else {
      return parseTvBoxTxt(content);
    }
  }
}
// lib/modules/live/services/live_epg_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../models/epg_channel.dart';
import '../models/epg_programme.dart';
import '../models/live_channel.dart';

class LiveEpgService {
  /// 缓存目录名
  static const String _cacheDirName = 'live_epg';

  /// 缓存有效期（天）
  static const int _cacheDays = 7;

  /// 加载 EPG（带本地缓存）
  ///
  /// [configKey] 用于区分不同配置的缓存
  /// [url] EPG 地址，支持 .xml 和 .xml.gz
  static Future<Map<String, EpgChannel>> load({
    required String configKey,
    required String url,
    Dio? dio,
  }) async {
    if (url.isEmpty) return {};

    final client = dio ?? Dio();
    final cacheFile = await _cacheFile(configKey, url);

    try {
      String xmlContent;

      // 1. 检查缓存（当天有效）
      if (cacheFile != null && await cacheFile.exists()) {
        final stat = await cacheFile.stat();
        final now = DateTime.now();
        final cacheDate = DateTime(
          stat.modified.year,
          stat.modified.month,
          stat.modified.day,
        );
        final today = DateTime(now.year, now.month, now.day);
        if (cacheDate == today) {
          xmlContent = await cacheFile.readAsString();
          return _parseInIsolate(xmlContent);
        }
      }

      // 2. 下载
      final response = await client.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      final bytes = response.data ?? [];
      if (bytes.isEmpty) return {};

      // 3. 解压（如果是 .gz 或 gzip 头）
      if (url.toLowerCase().endsWith('.gz') || _isGzip(bytes)) {
        final decoded = GZipDecoder().decodeBytes(bytes);
        xmlContent = utf8.decode(decoded, allowMalformed: true);
      } else {
        xmlContent = utf8.decode(bytes, allowMalformed: true);
      }

      // 4. 写缓存
      if (cacheFile != null) {
        try {
          await cacheFile.parent.create(recursive: true);
          await cacheFile.writeAsString(xmlContent);
        } catch (_) {}
      }

      // 5. 解析
      return _parseInIsolate(xmlContent);
    } catch (e) {
      // 加载失败：如果缓存存在，降级用缓存
      if (cacheFile != null && await cacheFile.exists()) {
        try {
          final xmlContent = await cacheFile.readAsString();
          return _parseInIsolate(xmlContent);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 解析 XML（在 Isolate 中执行）
  static Future<Map<String, EpgChannel>> _parseInIsolate(String xmlContent) async {
    return await Isolate.run(() => parseXml(xmlContent));
  }

  /// 解析 XML 字符串（纯函数，可测试）
  static Map<String, EpgChannel> parseXml(String xmlContent) {
    final result = <String, EpgChannel>{};

    try {
      final document = XmlDocument.parse(xmlContent);

      // 1. 先收集所有 channel
      final channelMap = <String, String>{}; // id -> displayName
      for (final node in document.findAllElements('channel')) {
        final id = node.getAttribute('id') ?? '';
        if (id.isEmpty) continue;
        final displayName = node
                .findAllElements('display-name')
                .firstOrNull
                ?.innerText
                .trim() ??
            id;
        channelMap[id] = displayName;
      }

      // 2. 收集 programme
      final programmeMap = <String, List<EpgProgramme>>{};
      for (final node in document.findAllElements('programme')) {
        final channelId = node.getAttribute('channel') ?? '';
        if (channelId.isEmpty) continue;

        final startStr = node.getAttribute('start') ?? '';
        final stopStr = node.getAttribute('stop') ?? '';
        final start = _parseEpgTime(startStr);
        final stop = _parseEpgTime(stopStr);
        if (start == null || stop == null) continue;

        final title = node
                .findAllElements('title')
                .firstOrNull
                ?.innerText
                .trim() ??
            '';

        programmeMap.putIfAbsent(channelId, () => []).add(EpgProgramme(
              start: start,
              stop: stop,
              title: title.isEmpty ? '未知节目' : title,
            ));
      }

      // 3. 组装
      for (final entry in channelMap.entries) {
        final programmes = programmeMap[entry.key] ?? [];
        programmes.sort((a, b) => a.start.compareTo(b.start));
        result[entry.key] = EpgChannel(
          id: entry.key,
          displayName: entry.value,
          programmes: programmes,
        );
      }

      // 4. 补漏：有些 EPG 没有 <channel> 定义，但有 <programme>
      for (final entry in programmeMap.entries) {
        if (!result.containsKey(entry.key)) {
          entry.value.sort((a, b) => a.start.compareTo(b.start));
          result[entry.key] = EpgChannel(
            id: entry.key,
            displayName: entry.key,
            programmes: entry.value,
          );
        }
      }
    } catch (_) {
      // 解析失败返回空
    }

    return result;
  }

  /// 解析 EPG 时间：20260918043200 +0800
  ///
  /// 说明：
  ///   EPG 时间字符串里的 HHmmss 是"目标时区的墙上时间"。
  ///   对于国内 EPG（+0800），墙上时间就是北京时间。
  ///   这里直接构造本地 DateTime，使 startLabel / stopLabel
  ///   显示的时间与节目单一致。
  ///
  /// 注意：
  ///   如果将来要支持与用户本地时区不一致的 EPG 源，
  ///   需要改为解析成 UTC（DateTime.utc(...).subtract(offset)），
  ///   并在 EpgProgramme 的 startLabel / stopLabel 中调用 .toLocal()。
  static DateTime? _parseEpgTime(String s) {
    if (s.length < 14) return null;
    try {
      final parts = s.split(' ');
      final dt = parts[0];
      final year = int.parse(dt.substring(0, 4));
      final month = int.parse(dt.substring(4, 6));
      final day = int.parse(dt.substring(6, 8));
      final hour = int.parse(dt.substring(8, 10));
      final minute = int.parse(dt.substring(10, 12));
      final second = int.parse(dt.substring(12, 14));

      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  /// 判断是否 gzip 头（0x1f 0x8b）
  static bool _isGzip(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }

  /// 缓存文件路径
  static Future<File?> _cacheFile(String configKey, String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final epgDir = Directory(p.join(dir.path, _cacheDirName));
      // 用 url 的 hash 作为文件名，避免特殊字符
      final hash = url.hashCode.abs();
      final date = _formatDate(DateTime.now());
      return File(p.join(epgDir.path, '${configKey}_${hash}_$date.xml'));
    } catch (_) {
      return null;
    }
  }

  /// 清理旧缓存
  static Future<void> clearOldCache() async {
    try {
      final dir = await getTemporaryDirectory();
      final epgDir = Directory(p.join(dir.path, _cacheDirName));
      if (!await epgDir.exists()) return;
      final now = DateTime.now();
      await for (final entity in epgDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (now.difference(stat.modified).inDays > _cacheDays) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static String _formatDate(DateTime d) {
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }
}

/// ============================================================
/// EPG 频道匹配器（增强版）
/// ============================================================
class EpgMatcher {
  /// 根据 LiveChannel 在 epgMap 中查找
  static EpgChannel? match(LiveChannel channel, Map<String, EpgChannel> epgMap) {
    if (epgMap.isEmpty) return null;

    // ===== 1. 精确匹配 =====
    // 1.1 tvgId
    if (channel.tvgId != null && channel.tvgId!.isNotEmpty) {
      final r = epgMap[channel.tvgId!];
      if (r != null) return r;
    }

    // 1.2 tvgName -> id
    if (channel.tvgName != null && channel.tvgName!.isNotEmpty) {
      final r = epgMap[channel.tvgName!];
      if (r != null) return r;
      // tvgName -> displayName
      for (final c in epgMap.values) {
        if (c.displayName == channel.tvgName) return c;
      }
    }

    // 1.3 name -> id
    final name = channel.name;
    if (epgMap.containsKey(name)) return epgMap[name];

    // 1.4 name -> displayName
    for (final c in epgMap.values) {
      if (c.displayName == name) return c;
    }

    // ===== 2. 归一化匹配 =====
    final normName = _normalize(name);
    if (normName.isEmpty) return null;

    // 2.1 归一化精确匹配
    for (final c in epgMap.values) {
      if (_normalize(c.id) == normName) return c;
      if (_normalize(c.displayName) == normName) return c;
    }

    // ===== 3. 数字匹配（带前缀校验，避免 CCTV1 匹配到 CCTV11） =====
    final nameNum = _extractNumber(name);
    if (nameNum != null) {
      for (final c in epgMap.values) {
        final cidNum = _extractNumber(c.id);
        final cdnNum = _extractNumber(c.displayName);
        if (cidNum == nameNum || cdnNum == nameNum) {
          // 前缀校验：CCTV1 与 CCTV1综合 归一化后共同前缀长
          if (_prefixMatch(name, c.id) || _prefixMatch(name, c.displayName)) {
            return c;
          }
        }
      }
    }

    // ===== 4. 模糊包含匹配（长度差 <= 3） =====
    for (final c in epgMap.values) {
      final normId = _normalize(c.id);
      final normDn = _normalize(c.displayName);
      if (normId.isEmpty && normDn.isEmpty) continue;
      if (_fuzzyContains(normName, normId)) return c;
      if (_fuzzyContains(normName, normDn)) return c;
    }

    return null;
  }

  /// 归一化：去后缀、去空格、去标点、转小写
  static String _normalize(String s) {
    var r = s.toLowerCase();
    // 去掉常见后缀（顺序重要，先长后短）
    r = r.replaceAll(
      RegExp(
        r'(高清频道|超清频道|标清频道|在线直播|高清|超清|标清|蓝光|hd|4k|8k|频道|综合|tv)',
      ),
      '',
    );
    // 去掉所有非字母数字汉字
    r = r.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
    return r.trim();
  }

  /// 提取字符串中的第一个数字序列
  static String? _extractNumber(String s) {
    final m = RegExp(r'(\d+)').firstMatch(s);
    return m?.group(1);
  }

  /// 前缀匹配：两个字符串归一化后，共同前缀长度 >= 较短者长度 - 1
  static bool _prefixMatch(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    final minLen = na.length < nb.length ? na.length : nb.length;
    if (minLen == 0) return false;
    // 取共同前缀
    int i = 0;
    while (i < minLen && na[i] == nb[i]) {
      i++;
    }
    // 共同前缀至少覆盖较短字符串的 80%
    return i >= minLen - 1;
  }

  /// 模糊包含：a 包含 b 或 b 包含 a，且长度差 <= 3
  static bool _fuzzyContains(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.length > b.length) {
      return a.contains(b) && (a.length - b.length) <= 3;
    } else {
      return b.contains(a) && (b.length - a.length) <= 3;
    }
  }
}
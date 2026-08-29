// lib/modules/novel/services/novel_font_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';

// 注意：这里需要引用 NovelReaderSettings，但为了避免循环依赖，
// 我们使用字符串键来获取字体设置，实际应用时在 reader page 中设置。
// 本服务只负责下载和加载，不直接操作设置。

/// 可下载字体定义
class DownloadableFont {
  final String key;
  final String label;
  final String family;
  final String sizeHint;
  final List<String> urls;

  const DownloadableFont({
    required this.key,
    required this.label,
    required this.family,
    required this.sizeHint,
    required this.urls,
  });
}

/// 预定义可下载字体列表
const List<DownloadableFont> kDownloadableFonts = [
  DownloadableFont(
    key: 'wenkai',
    label: '霞鹜文楷 Lite',
    family: 'WenKai',
    sizeHint: '约 13MB',
    urls: [
      'https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.522/LXGWWenKaiLite-Regular.ttf',
      'https://mirror.ghproxy.com/https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.522/LXGWWenKaiLite-Regular.ttf',
    ],
  ),
  DownloadableFont(
    key: 'noto',
    label: '思源宋体',
    family: 'NotoSerifSC',
    sizeHint: '约 25MB',
    urls: [
      'https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf',
      'https://mirror.ghproxy.com/https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf',
    ],
  ),
];

/// 字体下载服务（纯静态类）
class NovelFontService {
  NovelFontService._();

  static final Set<String> _downloaded = {};
  static final Set<String> _loaded = {};

  /// 初始化：扫描已下载字体，并加载当前选中的字体
  static Future<void> init() async {
    for (final font in kDownloadableFonts) {
      final f = await _fileOf(font);
      if (await f.exists() && await f.length() > 100000) {
        _downloaded.add(font.key);
      }
    }
    // 加载当前选中的字体（需要从 StorageManager 读取）
    final fontKey = StorageManager.getSetting<String>(SettingBoxKey.novelFontKey) ?? 'system';
    if (_downloaded.contains(fontKey)) {
      await load(fontKey);
    }
  }

  static bool isDownloaded(String key) => _downloaded.contains(key);
  static bool isLoaded(String key) => _loaded.contains(key);

  static DownloadableFont? byKey(String key) {
    for (final f in kDownloadableFonts) {
      if (f.key == key) return f;
    }
    return null;
  }

  static Future<Directory> _fontsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'fonts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _fileOf(DownloadableFont font) async {
    final dir = await _fontsDir();
    return File(p.join(dir.path, '${font.key}.ttf'));
  }

  /// 加载字体到运行时（FontLoader）
  static Future<bool> load(String key) async {
    if (_loaded.contains(key)) return true;
    final font = byKey(key);
    if (font == null) return false;
    try {
      final f = await _fileOf(font);
      if (!await f.exists()) return false;
      final bytes = await f.readAsBytes();
      final loader = FontLoader(font.family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _loaded.add(key);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 下载字体（带进度回调）
  static Future<void> download(
    String key, {
    void Function(double progress)? onProgress,
  }) async {
    final font = byKey(key);
    if (font == null) throw '未知字体';
    Object? lastError;
    for (final url in font.urls) {
      try {
        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(url));
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw 'HTTP ${response.statusCode}';
          }
          final total = response.contentLength ?? 0;
          final builder = BytesBuilder(copy: false);
          var received = 0;
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 60),
          )) {
            builder.add(chunk);
            received += chunk.length;
            if (total > 0) onProgress?.call(received / total);
          }
          final bytes = builder.takeBytes();
          if (bytes.length < 100000) throw '文件不完整';
          final f = await _fileOf(font);
          await f.writeAsBytes(bytes, flush: true);
          _downloaded.add(key);
          onProgress?.call(1);
          await load(key);
          return;
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? '下载失败';
  }

  /// 删除已下载字体
  static Future<void> remove(String key) async {
    final font = byKey(key);
    if (font == null) return;
    final f = await _fileOf(font);
    if (await f.exists()) await f.delete();
    _downloaded.remove(key);
    _loaded.remove(key);
    // 如果当前正在使用，回退到系统字体
    final currentKey = StorageManager.getSetting<String>(SettingBoxKey.novelFontKey) ?? 'system';
    if (currentKey == key) {
      await StorageManager.setSetting(SettingBoxKey.novelFontKey, 'system');
    }
  }
}
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/utils/business_exception.dart';

/// qjs_ultra 插件运行时解析。
///
/// QJS 由插件中心提供、在宿主进程内通过 Dart FFI 加载：
///   - Android: qjs / qjs-arm32 -> libquickjs_bridge.so
///   - Windows: qjs-win -> quickjs_bridge.dll
///   - iOS: 不使用 QJS，继续走既有 legacy 实现
class QjsPlatformHelper {
  static const _androidPluginIds = ['qjs', 'qjs-arm32'];
  static const _windowsPluginId = 'qjs-win';
  static const _androidLibraryName = 'libquickjs_bridge.so';
  static const _windowsLibraryName = 'quickjs_bridge.dll';
  static final Lock _windowsCacheLock = Lock();

  static bool get isSupported => Platform.isAndroid || Platform.isWindows;

  static String get engineName => isSupported ? 'qjs_ultra' : 'legacy';

  static String get _libraryName =>
      Platform.isWindows ? _windowsLibraryName : _androidLibraryName;

  static List<String> get _pluginIds =>
      Platform.isWindows ? const [_windowsPluginId] : _androidPluginIds;

  static InstalledPlugin? _installedPlugin() {
    for (final id in _pluginIds) {
      final plugin = InstallManager.instance.findInstalled(id);
      if (plugin != null && plugin.enabled) return plugin;
    }
    return null;
  }

  /// 返回 null 表示插件可用，否则返回业务错误文案。
  static String? checkPluginUsable() {
    if (!isSupported) return null;

    final plugin = _installedPlugin();
    if (plugin != null) return null;

    final installed = _pluginIds
        .map(InstallManager.instance.findInstalled)
        .whereType<InstalledPlugin>()
        .toList();
    if (installed.isEmpty) {
      return '未安装 QJS 爬虫引擎插件，请前往「插件中心 → 市场」安装后重试。';
    }
    return 'QJS 爬虫引擎插件已关闭，请前往「插件中心 → 插件」开启后重试。';
  }

  /// 动态解析当前启用插件中的 QJS 动态库绝对路径。
  ///
  /// 每次 worker 冷启动都会重新解析，不缓存插件路径。
  static Future<String> requireLibraryPath() async {
    if (!isSupported) {
      throw const BusinessException('当前平台不支持 QJS 插件运行时');
    }

    final pluginError = checkPluginUsable();
    if (pluginError != null) throw BusinessException(pluginError);

    final plugin = _installedPlugin()!;
    final root = plugin.installPath;
    final candidates = <String>[];

    final pluginJson = File(p.join(root, 'plugin.json'));
    if (pluginJson.existsSync()) {
      try {
        final json = jsonDecode(await pluginJson.readAsString());
        if (json is Map) {
          final binaries = json['binaries'];
          if (binaries is Map) {
            final key = Platform.isWindows ? 'win32' : 'android';
            final rel = binaries[key]?.toString();
            if (rel != null && rel.isNotEmpty) {
              final normalized = rel.replaceAll('\\', '/');
              candidates.addAll([
                p.join(root, normalized),
                p.join(root, 'bin', normalized),
                p.join(root, p.basename(normalized)),
                p.join(root, 'bin', p.basename(normalized)),
              ]);
            }
          }
        }
      } catch (_) {}
    }

    candidates.addAll([
      p.join(root, _libraryName),
      p.join(root, 'bin', _libraryName),
    ]);
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return _prepareLibraryPath(plugin, candidate);
      }
    }

    try {
      final entities = Directory(root).listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File &&
            p.basename(entity.path).toLowerCase() ==
                _libraryName.toLowerCase()) {
          return _prepareLibraryPath(plugin, entity.path);
        }
      }
    } catch (_) {}

    throw BusinessException('QJS 爬虫引擎插件文件不完整：缺少 $_libraryName');
  }

  /// Windows 不能在 DLL 已加载时可靠替换/删除插件目录中的原文件。
  /// 按文件 MD5 缓存一份运行时 DLL，卸载插件时不再占用插件目录文件。
  static Future<String> _prepareLibraryPath(
    InstalledPlugin plugin,
    String sourcePath,
  ) async {
    final source = File(sourcePath);
    if (!Platform.isWindows) return p.normalize(source.path);

    return _windowsCacheLock.synchronized(() async {
      try {
        final bytes = await source.readAsBytes();
        final hash = crypto.md5.convert(bytes).toString();
        final cacheRoot = await getApplicationCacheDirectory();
        final runtimeDir = Directory(
          p.join(cacheRoot.path, 'qjs-runtime', hash),
        );
        await runtimeDir.create(recursive: true);
        final target = File(p.join(runtimeDir.path, _windowsLibraryName));
        if (!await target.exists() || await target.length() != bytes.length) {
          final temp = File(
            '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
          );
          await temp.writeAsBytes(bytes, flush: true);
          if (await target.exists()) await target.delete();
          await temp.rename(target.path);
        }
        return p.normalize(target.path);
      } catch (e) {
        throw BusinessException(
          'QJS 爬虫引擎插件（${plugin.id}）运行时准备失败：$e',
        );
      }
    });
  }
}

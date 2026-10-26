// lib/modules/plugin_center/widgets/import_package_dialog.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/utils/storage_manager.dart';

Future<void> showImportPackageDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _ImportPackageDialog(),
  );
}

class _ImportPackageDialog extends StatefulWidget {
  const _ImportPackageDialog();

  @override
  State<_ImportPackageDialog> createState() => _ImportPackageDialogState();
}

class _ImportPackageDialogState extends State<_ImportPackageDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: const Text(
        '导入插件包（.apk / .zip / .json）',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '按包内容自动识别类型，安装到对应位置（与市场安装同语义）。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              _section('组件包（zip 带 plugin.json）', colorScheme, [
                '运行时 / 引擎 / 内核 / 二进制服务',
                '读 plugin.json 的 binaries.win32 判断平台',
              ]),
              _section('服务包（zip 带 server.json）', colorScheme, [
                '自动创建服务（启动需对应运行时）',
              ]),
              _section('源码包（zip 带 source.json）', colorScheme, [
                '解压到 plugins 同级目录',
              ]),
              _section('直播源包（.json，含 lives）', colorScheme, [
                '直接追加到直播配置',
              ]),
              _section('APK 直装型', colorScheme, [
                'Python 爬虫引擎 / IJK 内核 / FFmpeg 软解',
                '导入即拉起系统安装器',
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Text(
                  '同名组件包导入前询问是否覆盖；'
                  'Windows 平台仅支持 import / server / source / live 四种类型。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _pickAndImport,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('选择文件导入'),
        ),
      ],
    );
  }

  Widget _section(String title, ColorScheme colorScheme, List<String> bullets) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          ...bullets.map((b) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  '· $b',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _pickAndImport() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip', 'apk', 'json'],
      );
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final path = picked.path;
      if (path == null || path.isEmpty) {
        SmartDialog.showToast('无法获取文件路径');
        if (mounted) setState(() => _busy = false);
        return;
      }
      final name = p.basename(path).toLowerCase();

      if (name.endsWith('.apk')) {
        SmartDialog.showToast('APK 请直接双击安装');
        return;
      }
      if (name.endsWith('.json')) {
        await _importLiveJson(path);
        return;
      }
      if (name.endsWith('.zip')) {
        await _importZip(path);
      }
    } catch (e) {
      SmartDialog.showToast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ============================================================
  // 直播源 JSON
  // ============================================================

  Future<void> _importLiveJson(String path) async {
    final content = await File(path).readAsString();
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      SmartDialog.showToast('JSON 解析失败：$e');
      return;
    }
    final lives = decoded['lives'];
    if (lives is! List || lives.isEmpty) {
      SmartDialog.showToast('不是有效的直播源包（缺少 lives 数组）');
      return;
    }

    final added = await _appendLives(lives);
    if (added > 0) {
      SmartDialog.showToast('直播配置导入成功，共新增 $added 个');
      if (mounted) Navigator.pop(context);
    } else {
      SmartDialog.showToast('没有新增直播源（可能已存在）');
    }
  }

  Future<int> _appendLives(List<dynamic> lives) async {
    final existingRaw =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ??
            [];
    final existing = existingRaw
        .map((e) => LiveConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final existingNames = existing.map((c) => c.name).toSet();
    int added = 0;
    for (final item in lives) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      if (existingNames.contains(name)) continue;
      final newConfig = LiveConfig(
        key: _generateLiveKey(name, existing),
        name: name,
        url: item['url']?.toString() ?? '',
        ua: item['ua']?.toString(),
        epg: item['epg']?.toString(),
        logo: item['logo']?.toString(),
      );
      existing.add(newConfig);
      existingNames.add(name);
      added++;
    }
    if (added > 0) {
      await StorageManager.setSetting(
        SettingBoxKey.liveConfigs,
        existing.map((c) => c.toJson()).toList(),
      );
    }
    return added;
  }

  String _generateLiveKey(String name, List<LiveConfig> existing) {
    String base = name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w]'), '');
    if (base.isEmpty) base = 'live';
    String key = base;
    int index = 1;
    final keys = existing.map((c) => c.key).toSet();
    while (keys.contains(key)) {
      key = '${base}_$index';
      index++;
    }
    return key;
  }

  // ============================================================
  // ZIP 导入（临时目录 → 判断 → 移动）
  // ============================================================

  Future<void> _importZip(String path) async {
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('plugin_import_');
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        if (!f.isFile) continue;
        // H1：Zip Slip 防护——与 InstallManager._isSafeArchivePath 同语义
        final out = File(p.join(tempDir.path, f.name));
        final safe = _isSafeImportPath(tempDir.path, f.name);
        if (!safe) {
          debugPrint('[ImportPackageDialog] 跳过非法 entry: ${f.name}');
          continue;
        }
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: true);
      }

      final pluginJson = File(p.join(tempDir.path, 'plugin.json'));
      final serverJson = File(p.join(tempDir.path, 'server.json'));
      final sourceJson = File(p.join(tempDir.path, 'source.json'));

      if (serverJson.existsSync()) {
        await _importServerPackage(tempDir, path);
        return;
      }
      if (sourceJson.existsSync()) {
        await _importSourcePackage(tempDir, sourceJson, path);
        return;
      }
      if (pluginJson.existsSync()) {
        await _importComponentPackage(tempDir, pluginJson, path);
        return;
      }
      SmartDialog.showToast('包内未找到 plugin.json / server.json / source.json，不支持此类型');
    } catch (e) {
      SmartDialog.showToast('导入失败：$e');
    } finally {
      try {
        if (tempDir != null && tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// H1：Zip Slip 防护，与 InstallManager._isSafeArchivePath 同语义。
  bool _isSafeImportPath(String targetDir, String entryName) {
    try {
      final normalizedTarget = p.normalize(p.absolute(targetDir));
      final normalizedOut =
          p.normalize(p.absolute(p.join(targetDir, entryName)));
      return p.isWithin(normalizedTarget, normalizedOut) ||
          normalizedOut == normalizedTarget;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 源码包
  // ============================================================

  Future<void> _importSourcePackage(
    Directory tempDir,
    File sourceJson,
    String path,
  ) async {
    String? target;
    try {
      final content = await sourceJson.readAsString();
      final j = jsonDecode(content) as Map;
      target = j['target']?.toString();
    } catch (_) {}

    final dataRoot = await PluginPaths.dataRoot();
    await _copyDirContents(tempDir, dataRoot);

    // 删掉 source.json（不保留）
    final targetSourceJson = File(p.join(dataRoot.path, 'source.json'));
    if (targetSourceJson.existsSync()) {
      await targetSourceJson.delete();
    }

    final id = p.basenameWithoutExtension(path).toLowerCase();
    final installed = InstalledPlugin(
      id: id,
      version: '1.0.0',
      source: '手动导入',
      installPath: dataRoot.path,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: 'source',
      extras: {
        if (target != null) 'sourceTarget': target,
      },
    );
    await InstallManager.instance.register(installed);

    SmartDialog.showToast('源码包导入成功');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _copyDirContents(Directory src, Directory dst) async {
    await for (final entity in src.list(recursive: false)) {
      final name = p.basename(entity.path);
      final newPath = p.join(dst.path, name);
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        final newDir = Directory(newPath);
        await newDir.create(recursive: true);
        await _copyDirContents(entity, newDir);
      }
    }
  }

  // ============================================================
  // 服务包
  // ============================================================

  Future<void> _importServerPackage(Directory tempDir, String path) async {
    final id = p.basenameWithoutExtension(path).toLowerCase();
    final serviceId = 'svc-mkt-$id';

    final servicesRoot = await PluginPaths.servicesRoot();
    final baseDir = Directory(p.join(servicesRoot.path, serviceId));
    if (baseDir.existsSync()) {
      await baseDir.delete(recursive: true);
    }
    await _copyDirContents(tempDir, baseDir);

    final serverJsonFile = File(p.join(baseDir.path, 'server.json'));
    if (!serverJsonFile.existsSync()) {
      throw Exception('包内未找到 server.json');
    }
    final manifest = jsonDecode(await serverJsonFile.readAsString()) as Map;
    final workDir = manifest['workDir']?.toString() ?? '';
    final entryFile = manifest['entry']?.toString() ?? '';
    final port = (manifest['port'] is num)
        ? (manifest['port'] as num).toInt()
        : null;
    final cwd =
        workDir.isNotEmpty ? p.join(baseDir.path, workDir) : baseDir.path;

    // C7：与 InstallManager._createServiceFromManifest 共用同一推断逻辑。
    // 原实现硬编码 `-win` 后缀，Android 上手动导入 server 包会创建指向
    // 不存在的运行时（如 nodejs-win）的服务，启动必然失败。
    final runtime = InstallManager.resolveRuntimeForEntryFile(
      entryFile,
      isWindows: Platform.isWindows,
    );

    final config = ServiceConfig(
      id: serviceId,
      name: manifest['serviceName']?.toString() ?? id,
      port: port,
      runtime: runtime,
      args: [entryFile],
      cwd: cwd,
      autostart: false,
      keepForeground: false,
    );
    await ServiceManager.instance.addOrUpdate(config);

    final installed = InstalledPlugin(
      id: id,
      version: manifest['version']?.toString() ?? '0.0.0',
      source: '手动导入',
      installPath: baseDir.path,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: 'server',
    );
    await InstallManager.instance.register(installed);

    SmartDialog.showToast('服务包导入成功');
    if (mounted) Navigator.pop(context);
  }

  // ============================================================
  // 组件包
  // ============================================================

  Future<void> _importComponentPackage(
    Directory tempDir,
    File pluginJson,
    String path,
  ) async {
    Map<String, dynamic> j;
    try {
      final content = await pluginJson.readAsString();
      j = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      SmartDialog.showToast('plugin.json 解析失败：$e');
      return;
    }

    final id = j['name']?.toString() ?? p.basenameWithoutExtension(path);
    final version = j['version']?.toString() ?? '0.0.0';
    final binaries = j['binaries'];
    final runtime = j['runtime']?.toString() ?? '';
    final binariesKey = Platform.isWindows ? 'win32' : 'android';
    final platformLabel = Platform.isWindows ? 'Windows' : 'Android';

    if (binaries is! Map || !(binaries[binariesKey] is String)) {
      SmartDialog.showToast('该包不支持 $platformLabel 平台');
      return;
    }

    // 验证当前平台的二进制文件存在
    // 兼容两种写法：
    //   1. "bin/node.exe"（带 bin/ 前缀）
    //   2. "quickjs_bridge.dll"（不带前缀，但实际在 bin/ 下）
    final rel = (binaries[binariesKey] as String).replaceAll('\\', '/');
    final candidates = <String>[
      p.join(tempDir.path, rel),                    // tempDir/bin/node.exe
      p.join(tempDir.path, 'bin', rel),             // tempDir/bin/quickjs_bridge.dll
      p.join(tempDir.path, p.basename(rel)),        // tempDir/quickjs_bridge.dll
    ];
    bool found = false;
    for (final c in candidates) {
      if (File(c).existsSync()) {
        found = true;
        break;
      }
    }
    if (!found) {
      final label = Platform.isWindows ? 'Windows' : 'Android';
      SmartDialog.showToast('该包缺少 $label 二进制文件：$rel');
      return;
    }

    if (runtime.isEmpty) {
      SmartDialog.showToast('插件缺少 runtime 字段，不支持');
      return;
    }

    final existing = InstallManager.instance.findInstalled(id);
    if (existing != null) {
      final ok = await _confirmOverwrite(id);
      if (ok != true) return;
    }

    final targetDir = await PluginPaths.pluginDir(id, version);
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }
    await _copyDirContents(tempDir, targetDir);

    final installed = InstalledPlugin(
      id: id,
      version: version,
      source: '手动导入',
      installPath: targetDir.path,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: 'import',
    );
    await InstallManager.instance.register(installed);

    SmartDialog.showToast('组件包导入成功');
    if (mounted) Navigator.pop(context);
  }

  Future<bool?> _confirmOverwrite(String id) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('覆盖安装'),
        content: Text('「$id」已安装，是否覆盖？运行中的服务会先停止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
  }
}
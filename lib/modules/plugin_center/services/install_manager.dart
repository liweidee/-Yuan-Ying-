// lib/modules/plugin_center/services/install_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';
import 'package:install_plugin_v3/install_plugin_v3.dart';

import 'package:yuanying/core/constants/plugin_storage_keys.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/models/live/live_config.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/market_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/t4/services/python_runtime.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';

/// 安装阶段枚举
enum InstallStage {
  idle,
  downloading,
  verifying,
  extracting,
  registering,
  done,
  failed,
}

extension InstallStageLabel on InstallStage {
  String get label {
    switch (this) {
      case InstallStage.idle:
        return '准备中';
      case InstallStage.downloading:
        return '正在下载…';
      case InstallStage.verifying:
        return '校验中…';
      case InstallStage.extracting:
        return '解压中…';
      case InstallStage.registering:
        return '登记中…';
      case InstallStage.done:
        return '安装完成';
      case InstallStage.failed:
        return '安装失败';
    }
  }
}

class InstallProgress {
  final InstallStage stage;
  final int received;
  final int total;

  const InstallProgress({
    required this.stage,
    this.received = 0,
    this.total = 0,
  });

  double get percent {
    if (total <= 0) return 0;
    return (received / total).clamp(0.0, 1.0);
  }
}

class InstallCancelToken {
  bool _cancelled = false;
  CancelToken _dioToken = CancelToken();

  bool get isCancelled => _cancelled;
  CancelToken get dioToken => _dioToken;

  void cancel() {
    _cancelled = true;
    if (!_dioToken.isCancelled) {
      _dioToken.cancel('用户取消');
    }
  }

  void reset() {
    _cancelled = false;
    _dioToken = CancelToken();
  }
}

/// 系统安装的直装型插件信息
class SystemInstalledPlugin {
  final String packageName;
  final String pluginId;
  final String title;
  final String version;

  const SystemInstalledPlugin({
    required this.packageName,
    required this.pluginId,
    required this.title,
    required this.version,
  });
}

class InstallManager {
  InstallManager._();
  static final InstallManager instance = InstallManager._();

  static const _pkgChannel = MethodChannel('com.example.yuanying/storage');

  /// 读-改-写 installedList 的串行锁，防并发丢数据
  final Lock _regLock = Lock();

  /// 已知的直装型包名清单
  static const knownImportPackages = <String>[
    'com.dsplayer.plugin.qjs',
    'com.dsplayer.plugin.agent',
  ];

  /// 已知的系统安装型包名清单（installMode=apk，market.json 可能未声明 pkg）
  static const knownApkPackages = <String>[
    'com.dsplayer.plugin.python',
  ];

  /// id → 系统安装型包名映射（market.json 无 pkg 时兜底）
  static const _idToApkPackage = <String, String>{
    'py': 'com.dsplayer.plugin.python',
  };

  String? _knownApkPackageFor(String id) => _idToApkPackage[id];

  static const _pkgToId = <String, String>{
    'com.dsplayer.plugin.qjs': 'qjs',
    'com.dsplayer.plugin.agent': 'agent',
    'com.dsplayer.plugin.python': 'py',
  };

  static const _pkgToTitle = <String, String>{
    'com.dsplayer.plugin.qjs': 'QJS 爬虫引擎插件',
    'com.dsplayer.plugin.agent': 'AI 助手界面插件',
    'com.dsplayer.plugin.python': 'Python 爬虫引擎插件',
  };

  Box get _box => Hive.box(PluginStorageKeys.installedBox);

  // ============================================================
  // 已装登记
  // ============================================================

  List<InstalledPlugin> getAllInstalled() {
    final raw = _box.get(PluginStorageKeys.installedList);
    if (raw is! List) return [];
    return raw
        .map((e) =>
            InstalledPlugin.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  InstalledPlugin? findInstalled(String id) {
    for (final plugin in getAllInstalled()) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  /// 内部写盘：只被加锁的 register/unregister/setEnabled/setPinned/updateExtras/backfillFromMarket 调用
  Future<void> _saveAll(List<InstalledPlugin> list) async {
    await _box.put(
      PluginStorageKeys.installedList,
      list.map((e) => e.toJson()).toList(),
    );
  }

  Future<void> register(InstalledPlugin plugin) async {
    await _regLock.synchronized(() async {
      final list = getAllInstalled();
      final idx = list.indexWhere((e) => e.id == plugin.id);
      if (idx >= 0) {
        list[idx] = plugin;
      } else {
        list.add(plugin);
      }
      await _saveAll(list);
    });
  }

  Future<void> unregister(String id) async {
    await _regLock.synchronized(() async {
      final list = getAllInstalled();
      list.removeWhere((e) => e.id == id);
      await _saveAll(list);
    });
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _regLock.synchronized(() async {
      final list = getAllInstalled();
      final idx = list.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(enabled: enabled);
        await _saveAll(list);
      }
    });
  }

  Future<void> setPinned(String id, bool pinned) async {
    await _regLock.synchronized(() async {
      final list = getAllInstalled();
      final idx = list.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final updated = list[idx].copyWith(
          pinned: pinned,
          pinnedAtMs:
              pinned ? DateTime.now().millisecondsSinceEpoch : null,
          clearPinnedAt: !pinned,
        );
        list[idx] = updated;
        await _saveAll(list);
      }
    });
  }

  Future<void> updateExtras(String id, Map<String, dynamic> extras) async {
    await _regLock.synchronized(() async {
      final list = getAllInstalled();
      final idx = list.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(extras: extras);
        await _saveAll(list);
      }
    });
  }

  Future<void> backfillFromMarket(List<MarketEntry> marketEntries) async {
    if (marketEntries.isEmpty) return;
    await _regLock.synchronized(() async {
      final list = getAllInstalled();
      bool changed = false;
      for (int i = 0; i < list.length; i++) {
        final plugin = list[i];
        if (plugin.desc != null &&
            plugin.changelog != null &&
            plugin.icon != null) {
          continue;
        }
        MarketEntry? matched;
        for (final m in marketEntries) {
          if (m.id == plugin.id) {
            matched = m;
            break;
          }
        }
        if (matched == null) continue;
        list[i] = plugin.copyWith(
          desc: plugin.desc ?? matched.desc,
          changelog: plugin.changelog ?? matched.changelog,
          icon: plugin.icon ?? matched.icon,
        );
        changed = true;
      }
      if (changed) await _saveAll(list);
    });
  }

  // ============================================================
  // 已装判定
  // ============================================================

  Future<bool> isInstalled(MarketEntry entry) async {
    final reg = findInstalled(entry.id);
    if (reg == null) return false;

    // type=server：查服务是否还在（不比对版本，服务覆盖安装后版本可能不同）
    if (entry.type == 'server') {
      final serviceId = 'svc-mkt-${entry.id}';
      final exists = ServiceManager.instance.find(serviceId) != null;
      if (!exists) return false;
      return reg.version == entry.version;
    }

    // type=live / source：登记表有记录即视为已装
    if (entry.type == 'live' || entry.type == 'source') {
      return reg.version == entry.version;
    }

    // type=apk / import：先比版本
    if (reg.version != entry.version) return false;

    // installMode=apk：查 PackageManager
    final installMode = reg.extras['installMode']?.toString();
    if (installMode == 'apk') {
      if (!Platform.isAndroid) return false;
      String? pkg = reg.extras['apkPackage']?.toString() ?? entry.pkg;
      // 兜底：market.json 未声明 pkg 时，按 id 匹配已知系统包
      if (pkg == null || pkg.isEmpty) {
        pkg = _knownApkPackageFor(entry.id);
      }
      if (pkg == null || pkg.isEmpty) return false;
      return _isPackageInstalled(pkg);
    }

    // installMode=import：查目录
    return PluginPaths.isPluginInstalled(entry.id, entry.version);
  }

  /// 按 id 异步判已装（供 UI 层 FutureBuilder 使用，不校验版本）
  Future<bool> isInstalledById(String id) async {
    final reg = findInstalled(id);
    if (reg == null) return false;
    final installMode = reg.extras['installMode']?.toString();
    if (installMode == 'apk') {
      if (!Platform.isAndroid) return false;
      final pkg = reg.extras['apkPackage']?.toString();
      if (pkg == null || pkg.isEmpty) return false;
      return _isPackageInstalled(pkg);
    }
    final dir = Directory(reg.installPath);
    return dir.existsSync();
  }

  Future<bool> hasUpdate(MarketEntry entry) async {
    final reg = findInstalled(entry.id);
    if (reg == null) return false;
    return reg.version != entry.version;
  }

  Future<bool> _isPackageInstalled(String pkgName) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _pkgChannel.invokeMethod<bool>(
        'isPackageInstalled',
        {'packageName': pkgName},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getPackageVersion(String pkgName) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _pkgChannel.invokeMethod<String>(
        'getPackageVersion',
        {'packageName': pkgName},
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getApkPath(String pkgName) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _pkgChannel.invokeMethod<String>(
        'getApkPath',
        {'packageName': pkgName},
      );
    } catch (_) {
      return null;
    }
  }

  /// 拉起系统卸载 Intent
  Future<void> uninstallSystemPackage(String pkgName) async {
    if (!Platform.isAndroid) return;
    try {
      await _pkgChannel.invokeMethod('uninstallPackage', {
        'packageName': pkgName,
      });
    } catch (e) {
      debugPrint('[InstallManager] uninstallSystemPackage failed: $e');
    }
  }

  // ============================================================
  // 系统安装的直装型插件：扫描 + 固化
  // ============================================================

  Future<List<SystemInstalledPlugin>> scanSystemImportPlugins() async {
    if (!Platform.isAndroid) return [];
    final result = <SystemInstalledPlugin>[];

    // 合并 import 型（qjs/agent）和 apk 型（python）所有已知包
    final allPackages = <String>[
      ...knownImportPackages,
      ...knownApkPackages,
    ];

    for (final pkg in allPackages) {
      final installed = await _isPackageInstalled(pkg);
      if (!installed) continue;
      final id = _pkgToId[pkg] ?? pkg;
      if (findInstalled(id) != null) continue;
      final version = await _getPackageVersion(pkg) ?? '';
      result.add(SystemInstalledPlugin(
        packageName: pkg,
        pluginId: id,
        title: _pkgToTitle[pkg] ?? id,
        version: version,
      ));
    }
    return result;
  }

  Future<bool> solidifySystemPlugin(SystemInstalledPlugin info) async {
    if (!Platform.isAndroid) return false;
    try {
      final apkPath = await _getApkPath(info.packageName);
      if (apkPath == null || apkPath.isEmpty) return false;
      final apkFile = File(apkPath);
      if (!apkFile.existsSync()) return false;

      final bytes = await apkFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? pluginJsonFile;
      for (final f in archive) {
        if (f.isFile && f.name == 'assets/plugin.json') {
          pluginJsonFile = f;
          break;
        }
      }
      if (pluginJsonFile == null) return false;

      Map<String, dynamic> pluginJson;
      try {
        final raw = utf8.decode(pluginJsonFile.content as List<int>);
        pluginJson = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return false;
      }
      final installMode = pluginJson['installMode']?.toString();

      // ===== installMode = apk：系统安装型插件（如 python）=====
      // 这类插件必须保持 APK 系统安装形态（需要 AIDL / Service 桥接），
      // 无法固化到应用内。这里只做"登记"，让插件中心能识别到；
      // 卸载时必须走系统卸载（ACTION_UNINSTALL_PACKAGE）。
      if (installMode == 'apk') {
        await register(InstalledPlugin(
          id: info.pluginId,
          version: info.version.isEmpty ? '0.0.0' : info.version,
          source: '系统应用',
          installPath: '',
          enabled: true,
          pinned: false,
          installedAtMs: DateTime.now().millisecondsSinceEpoch,
          type: 'apk',
          desc: pluginJson['desc']?.toString() ??
              '系统安装型插件（通过 APK 安装，卸载需走系统卸载）',
          extras: {
            'platform': 'android',
            'installMode': 'apk',
            'apkPackage': info.packageName,
          },
        ));
        debugPrint('[InstallManager] 已登记系统安装型插件：${info.pluginId} '
            '(pkg=${info.packageName}, v=${info.version})');
        return true;
      }

      // ===== installMode = import：可固化的插件（qjs/agent）=====
      if (installMode != 'import') return false;

      final fakeEntry = MarketEntry(
        id: info.pluginId,
        name: info.title,
        version: info.version.isEmpty ? '0.0.0' : info.version,
        url: '',
        sizeBytes: 0,
        type: 'apk',
        platforms: const ['android'],
      );
      await _installApkAsImport(fakeEntry, archive, pluginJson, '系统应用固化');
      return true;
    } catch (e) {
      debugPrint('[InstallManager] solidifySystemPlugin failed: $e');
      return false;
    }
  }

  // ============================================================
  // 安装主流程
  // ============================================================

  Future<void> install(
    MarketEntry entry, {
    required String indexBaseUrl,
    required String marketName,
    InstallCancelToken? cancelToken,
    void Function(InstallProgress)? onProgress,
  }) async {
    final token = cancelToken ?? InstallCancelToken();
    token.reset();

    void emit(InstallStage stage, {int r = 0, int t = 0}) {
      onProgress?.call(InstallProgress(stage: stage, received: r, total: t));
    }

    // ===== type=apk 分支（仅 Android） =====
    if (entry.type == 'apk') {
      if (!Platform.isAndroid) {
        throw Exception('APK 仅支持 Android 平台');
      }
      emit(InstallStage.downloading, r: 0, t: entry.sizeBytes);
      await _installApkPackage(
        entry,
        indexBaseUrl: indexBaseUrl,
        marketName: marketName,
        cancelToken: token,
        onProgress: (r, t) => emit(InstallStage.downloading, r: r, t: t),
      );
      emit(InstallStage.done);
      return;
    }

    // ===== type=live 分支 =====
    if (entry.type == 'live') {
      emit(InstallStage.downloading, r: 0, t: entry.sizeBytes);
      await _installLivePackage(
        entry,
        indexBaseUrl: indexBaseUrl,
        marketName: marketName,
        cancelToken: token,
        onProgress: (r, t) => emit(InstallStage.downloading, r: r, t: t),
      );
      emit(InstallStage.done);
      return;
    }

    final downloadUrl = MarketManager.resolveUrl(entry.url, indexBaseUrl);
    final finalUrl = _applyGithubProxyIfNeeded(downloadUrl);

    final tempPath =
        await PluginPaths.downloadFilePath(entry.id, entry.version);
    emit(InstallStage.downloading, r: 0, t: entry.sizeBytes);

    try {
      await _download(finalUrl, tempPath, token, (received, total) {
        emit(InstallStage.downloading, r: received, t: total);
      });
    } on _CancelledException {
      await _safeDeleteFile(tempPath);
      emit(InstallStage.failed);
      rethrow;
    } catch (e) {
      await _safeDeleteFile(tempPath);
      emit(InstallStage.failed);
      throw Exception('下载失败：$e');
    }

    if (token.isCancelled) {
      await _safeDeleteFile(tempPath);
      emit(InstallStage.failed);
      throw Exception('已取消');
    }

    emit(InstallStage.verifying);
    if (entry.md5 != null && entry.md5!.isNotEmpty) {
      try {
        final actual = await _md5OfFile(tempPath);
        if (actual.toLowerCase() != entry.md5!.toLowerCase()) {
          await _safeDeleteFile(tempPath);
          emit(InstallStage.failed);
          throw Exception(
            'md5 校验不符（可能是代理/CDN 缓存脏数据）\n'
            '期望：${entry.md5}\n实际：$actual',
          );
        }
      } catch (e) {
        await _safeDeleteFile(tempPath);
        emit(InstallStage.failed);
        rethrow;
      }
    }

    // ===== type=server 分支 =====
    if (entry.type == 'server') {
      emit(InstallStage.extracting);
      await _installServerPackage(
        entry,
        tempPath,
        marketName: marketName,
      );
      await _safeDeleteFile(tempPath);
      emit(InstallStage.done);
      return;
    }

    // ===== type=source 分支 =====
    if (entry.type == 'source') {
      emit(InstallStage.extracting);
      await _installSourcePackage(
        entry,
        tempPath,
        marketName: marketName,
      );
      await _safeDeleteFile(tempPath);
      emit(InstallStage.done);
      return;
    }

    // ===== type=import 默认分支 =====
    //
    // C2 修复：先解压到同卷临时目录，成功后再清理旧目录并原子 rename。
    // 原流程是「先删旧目录 → 解压到最终路径」，解压失败会留下
    // 「注册表还指向旧路径，但旧目录已被删」的脏状态，用户必须手动
    // 卸载重装才能恢复。新流程下解压失败时旧目录与注册表均保持原样。
    emit(InstallStage.extracting);

    final root = await PluginPaths.root();
    final finalDir = p.join(root.path, entry.id);
    final tmpDir = Directory(
      p.join(root.path, '.tmp-${entry.id}-${entry.version}-'
          '${DateTime.now().millisecondsSinceEpoch}'),
    );

    try {
      if (!tmpDir.existsSync()) {
        await tmpDir.create(recursive: true);
      }
      await _extractZip(tempPath, tmpDir.path);
    } catch (e) {
      await _safeDeleteDir(tmpDir.path);
      await _safeDeleteFile(tempPath);
      emit(InstallStage.failed);
      throw Exception('解压失败：$e');
    }
    await _safeDeleteFile(tempPath);

    // 解压成功，开始替换旧目录
    try {
      await _cleanupOldVersions(entry.id, entry.version);
      final finalDirObj = Directory(finalDir);
      if (finalDirObj.existsSync()) {
        // _cleanupOldVersions 已删除同路径，这里理论上不会存在；
        // 若存在（并发/异常），先删掉再 rename，保证 rename 成功。
        await finalDirObj.delete(recursive: true);
      }
      try {
        await tmpDir.rename(finalDir);
      } on FileSystemException {
        // 跨卷 fallback：理论上同卷不会走到这里
        await finalDirObj.create(recursive: true);
        await _copyDirContents(tmpDir, finalDirObj);
        await _safeDeleteDir(tmpDir.path);
      }
    } catch (e) {
      await _safeDeleteDir(tmpDir.path);
      emit(InstallStage.failed);
      throw Exception('替换目录失败：$e');
    }

    emit(InstallStage.registering);
    final installed = InstalledPlugin(
      id: entry.id,
      version: entry.version,
      source: marketName,
      installPath: finalDir,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: entry.type,
      desc: entry.desc,
      changelog: entry.changelog,
      icon: entry.icon,
      extras: {
        'platform': Platform.isWindows ? 'win32' : 'android',
      },
    );
    await register(installed);
    emit(InstallStage.done);
  }

  /// C7：按入口文件推断运行时（Windows / Android 分别映射到带/不带 `-win` 后缀的 id）。
  /// 供 `_createServiceFromManifest` 与 `ImportPackageDialog` 共用，
  /// 消除两处硬编码不一致（原来 Android 上手动导入 server 包会错误指向 `*-win`）。
  static String resolveRuntimeForEntryFile(
    String entryFile, {
    required bool isWindows,
  }) {
    if (entryFile.endsWith('.js')) {
      return isWindows ? 'nodejs-win' : 'nodejs';
    }
    if (entryFile.endsWith('.php')) {
      return isWindows ? 'php-win' : 'php';
    }
    if (entryFile.endsWith('.py')) {
      return isWindows ? 'python-win' : 'python';
    }
    return isWindows ? 'nodejs-win' : 'nodejs';
  }

  /// type=apk：下载 APK → 读 assets/plugin.json 分流
  Future<void> _installApkPackage(
    MarketEntry entry, {
    required String indexBaseUrl,
    required String marketName,
    required InstallCancelToken cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final downloadUrl = MarketManager.resolveUrl(entry.url, indexBaseUrl);
    final finalUrl = _applyGithubProxyIfNeeded(downloadUrl);

    final tempPath =
        (await PluginPaths.downloadFilePath(entry.id, entry.version))
            .replaceAll('.zip', '.apk');
    final file = File(tempPath);
    if (file.existsSync()) await file.delete();

    // C3：失败路径（下载中断 / APK 损坏 / 解析异常 / 安装失败）
    // 原来残留临时文件，多次重试会在 cache/download 目录累积垃圾。
    try {
      final dio = HttpClientFactory.dio;
      final response = await dio.get<ResponseBody>(
        finalUrl,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 400,
        ),
        cancelToken: cancelToken.dioToken,
      );
      if (response.statusCode != 200) {
        throw Exception('APK 下载失败：HTTP ${response.statusCode}');
      }
      final sink = file.openWrite();
      int received = 0;
      try {
        await for (final chunk in response.data!.stream) {
          if (cancelToken.isCancelled) throw _CancelledException();
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, entry.sizeBytes);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (cancelToken.isCancelled) {
        throw _CancelledException();
      }

      final bytes = await File(tempPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? pluginJsonFile;
      for (final f in archive) {
        if (f.isFile && f.name == 'assets/plugin.json') {
          pluginJsonFile = f;
          break;
        }
      }

      Map<String, dynamic>? pluginJson;
      if (pluginJsonFile != null) {
        try {
          final raw = utf8.decode(pluginJsonFile.content as List<int>);
          pluginJson = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          pluginJson = null;
        }
      }

      final installMode = pluginJson?['installMode']?.toString() ?? 'apk';

      if (installMode == 'import') {
        await _installApkAsImport(entry, archive, pluginJson!, marketName);
        return;
      }

      final res = await InstallPlugin.install(tempPath);
      if (res['isSuccess'] != true) {
        throw Exception('安装失败：${res['errorMessage'] ?? ''}');
      }

      final apkPackage = entry.pkg ?? _knownApkPackageFor(entry.id);
      await register(InstalledPlugin(
        id: entry.id,
        version: entry.version,
        source: marketName,
        installPath: tempPath,
        enabled: true,
        pinned: false,
        installedAtMs: DateTime.now().millisecondsSinceEpoch,
        type: 'apk',
        desc: entry.desc,
        changelog: entry.changelog,
        icon: entry.icon,
        extras: {
          'platform': 'android',
          'installMode': 'apk',
          if (apkPackage != null) 'apkPackage': apkPackage,
        },
      ));
    } finally {
      await _safeDeleteFile(tempPath);
    }
  }

  /// installMode == 'import'：按 kind 定制提取到私有目录
  Future<void> _installApkAsImport(
    MarketEntry entry,
    Archive archive,
    Map<String, dynamic> pluginJson,
    String marketName,
  ) async {
    final kind = pluginJson['kind']?.toString() ?? '';

    final targetDir = await PluginPaths.pluginDir(entry.id, entry.version);
    if (targetDir.existsSync()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    String? abiDir;
    if (Platform.isAndroid) {
      final abi = Abi.current();
      if (abi == Abi.androidArm64) {
        abiDir = 'arm64-v8a';
      } else if (abi == Abi.androidArm) {
        abiDir = 'armeabi-v7a';
      } else if (abi == Abi.androidX64) {
        abiDir = 'x86_64';
      } else if (abi == Abi.androidIA32) {
        abiDir = 'x86';
      }
    }

    for (final f in archive) {
      if (!f.isFile) continue;

      // H1：Zip Slip 防护——目标路径必须落在 targetDir 内
      if (!_isSafeArchivePath(targetDir.path, f.name)) {
        debugPrint('[InstallManager] 跳过非法 entry: ${f.name}');
        continue;
      }

      if (f.name.startsWith('META-INF/')) continue;
      if (f.name == 'AndroidManifest.xml') continue;
      if (f.name == 'resources.arsc') continue;
      if (f.name.startsWith('kotlin/')) continue;
      if (f.name == 'classes.dex') continue;
      if (f.name.startsWith('classes') && f.name.endsWith('.dex')) continue;

      if (kind == 'qjs-engine') {
        if (f.name == 'assets/plugin.json') {
          await _writeArchiveFile(f, targetDir.path, 'plugin.json');
          continue;
        }
        if (abiDir != null && f.name.startsWith('lib/$abiDir/')) {
          final fileName = p.basename(f.name);
          await _writeArchiveFile(f, targetDir.path, fileName);
        }
        continue;
      }

      if (kind == 'agent-ui') {
        if (f.name == 'assets/plugin.json') {
          await _writeArchiveFile(f, targetDir.path, 'plugin.json');
          continue;
        }
        if (f.name.startsWith('assets/www/')) {
          final rel = f.name.substring('assets/www/'.length);
          if (rel.isEmpty) continue;
          await _writeArchiveFile(f, targetDir.path, rel);
        }
        continue;
      }

      if (f.name == 'assets/plugin.json') {
        await _writeArchiveFile(f, targetDir.path, 'plugin.json');
      } else if (f.name.startsWith('assets/')) {
        final rel = f.name.substring('assets/'.length);
        if (rel.isEmpty) continue;
        await _writeArchiveFile(f, targetDir.path, rel);
      } else if (abiDir != null && f.name.startsWith('lib/$abiDir/')) {
        final fileName = p.basename(f.name);
        await _writeArchiveFile(f, targetDir.path, fileName);
      }
    }

    await register(InstalledPlugin(
      id: entry.id,
      version: entry.version,
      source: marketName,
      installPath: targetDir.path,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: 'apk',
      desc: entry.desc,
      changelog: entry.changelog,
      icon: entry.icon,
      extras: {
        'platform': 'android',
        'installMode': 'import',
        if (kind.isNotEmpty) 'kind': kind,
      },
    ));
  }

  Future<void> _writeArchiveFile(
    ArchiveFile f,
    String targetDir,
    String relativePath,
  ) async {
    // H1：双重保险——_installApkAsImport 已在入口处检查，
    // 这里再检查一次，防止后续新增调用点漏检。
    if (!_isSafeArchivePath(targetDir, relativePath)) {
      debugPrint('[InstallManager] 跳过非法写入: $relativePath');
      return;
    }
    final outPath = p.join(targetDir, relativePath);
    final outFile = File(outPath);
    final parent = outFile.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    await outFile.writeAsBytes(f.content as List<int>, flush: true);
  }

  // ============================================================
  // type=live
  // ============================================================

  Future<void> _installLivePackage(
    MarketEntry entry, {
    required String indexBaseUrl,
    required String marketName,
    required InstallCancelToken cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final downloadUrl = MarketManager.resolveUrl(entry.url, indexBaseUrl);
    final finalUrl = _applyGithubProxyIfNeeded(downloadUrl);

    final dio = HttpClientFactory.dio;
    final response = await dio.get<String>(
      finalUrl,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 400,
      ),
      cancelToken: cancelToken.dioToken,
      onReceiveProgress: (r, t) => onProgress?.call(r, t),
    );

    if (response.statusCode != 200) {
      throw Exception('直播源下载失败：HTTP ${response.statusCode}');
    }

    if (entry.md5 != null && entry.md5!.isNotEmpty) {
      final bytes = utf8.encode(response.data ?? '');
      final actual = crypto.md5.convert(bytes).toString();
      if (actual.toLowerCase() != entry.md5!.toLowerCase()) {
        throw Exception(
          'md5 校验不符\n期望：${entry.md5}\n实际：$actual',
        );
      }
    }

    final rawText = response.data ?? '';
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(rawText) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('直播源 JSON 解析失败：$e');
    }

    final lives = decoded['lives'];
    if (lives is! List || lives.isEmpty) {
      throw Exception('直播源 JSON 缺少 lives 数组或为空');
    }

    final existingRaw =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ??
            [];
    final existing = existingRaw
        .map((e) => LiveConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final existingNames = existing.map((c) => c.name).toSet();
    final addedKeys = <String>[];
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
      addedKeys.add(newConfig.key);
    }

    if (addedKeys.isEmpty) {
      throw Exception('没有新增直播源（可能全部已存在）');
    }

    await StorageManager.setSetting(
      SettingBoxKey.liveConfigs,
      existing.map((c) => c.toJson()).toList(),
    );

    final installed = InstalledPlugin(
      id: entry.id,
      version: entry.version,
      source: marketName,
      installPath: '',
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: 'live',
      desc: entry.desc,
      changelog: entry.changelog,
      icon: entry.icon,
      extras: {'liveKeys': addedKeys},
    );
    await register(installed);
  }

  String _generateLiveKey(String name, List<LiveConfig> existing) {
    String base = name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w]'), '');
    if (base.isEmpty) base = 'live';
    String key = base;
    int index = 1;
    final existingKeys = existing.map((c) => c.key).toSet();
    while (existingKeys.contains(key)) {
      key = '${base}_$index';
      index++;
    }
    return key;
  }

  // ============================================================
  // type=source
  // ============================================================

  Future<void> _installSourcePackage(
    MarketEntry entry,
    String tempPath, {
    required String marketName,
  }) async {
    final tempDir =
        await Directory.systemTemp.createTemp('source_install_');
    try {
      await _extractZip(tempPath, tempDir.path);

      final sourceJsonFile = File(p.join(tempDir.path, 'source.json'));
      String? target;
      if (sourceJsonFile.existsSync()) {
        try {
          final raw = await sourceJsonFile.readAsString();
          final j = jsonDecode(raw) as Map;
          target = j['target']?.toString();
        } catch (_) {}
      }

      final dataRoot = await PluginPaths.dataRoot();
      final extractRoot = dataRoot.path;

      await _copyDirContents(tempDir, Directory(extractRoot));

      final targetSourceJson = File(p.join(extractRoot, 'source.json'));
      if (targetSourceJson.existsSync()) {
        await targetSourceJson.delete();
      }

      final installed = InstalledPlugin(
        id: entry.id,
        version: entry.version,
        source: marketName,
        installPath: extractRoot,
        enabled: true,
        pinned: false,
        installedAtMs: DateTime.now().millisecondsSinceEpoch,
        type: 'source',
        desc: entry.desc,
        changelog: entry.changelog,
        icon: entry.icon,
        extras: {
          if (target != null) 'sourceTarget': target,
        },
      );
      await register(installed);
    } finally {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  // ============================================================
  // 卸载
  // ============================================================

  Future<void> uninstall(InstalledPlugin plugin) async {
    // python-win 卸载：先杀掉 py worker（否则 python.exe 占用目录删不掉）
    if (plugin.id == 'python-win') {
      try {
        await PythonRuntime.shutdown();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[InstallManager] shutdown py worker failed: $e');
      }
    }

    // nodejs-win 卸载：先杀掉 NodeJSService 的猫影视 Node 进程
    // 否则 node.exe 占用插件目录，_safeDeleteDir 会静默失败留下残留
    if (plugin.id == 'nodejs-win') {
      try {
        await NodeJSService.instance.stopForPluginDisabled();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[InstallManager] stop nodejs service failed: $e');
      }
    }

    // type=live
    if (plugin.type == 'live') {
      final existingRaw =
          StorageManager.getSetting<List<dynamic>>(SettingBoxKey.liveConfigs) ??
              [];
      final existing = existingRaw
          .map((e) => LiveConfig.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final keys = plugin.extras['liveKeys'];
      if (keys is List) {
        existing.removeWhere((c) => keys.contains(c.key));
        await StorageManager.setSetting(
          SettingBoxKey.liveConfigs,
          existing.map((c) => c.toJson()).toList(),
        );
      }
      await unregister(plugin.id);
      return;
    }

    // type=server
    if (plugin.type == 'server') {
      final serviceId = 'svc-mkt-${plugin.id}';
      if (ServiceManager.instance.find(serviceId) != null) {
        await ServiceManager.instance.remove(serviceId);
      }
      await _safeDeleteDir(plugin.installPath);
      await unregister(plugin.id);
      return;
    }

    // type=source：只移除登记，不删文件
    if (plugin.type == 'source') {
      await unregister(plugin.id);
      return;
    }

    // type=apk：按 installMode 分流
    if (plugin.type == 'apk') {
      final installMode = plugin.extras['installMode']?.toString();
      if (installMode == 'apk') {
        // 系统安装型：仅清登记，系统卸载由 UI 层拉起
        await unregister(plugin.id);
        return;
      }
      // import 型：删私有目录 + 清登记
      await _safeDeleteDir(plugin.installPath);
      await unregister(plugin.id);
      return;
    }

    // type=import / 其他
    //
    // 改进点（相对原代码）：
    //   1. stop 失败不中断卸载（原代码抛异常会导致用户卡在"卸载失败"）
    //   2. Windows 上进程退出后加 500ms 延迟，避免文件句柄未释放
    //      → 目录残留（与 python-win / nodejs-win 的处理对齐）
    //
    // 注意：**无条件 stop**，不判断 status。
    // 原因：ServiceStatus.error 可能表示"进程还活着"（sigkill 失败保留引用），
    //      条件 stop 会漏掉这类残留进程。
    final services = ServiceManager.instance.getAll();
    bool stoppedAny = false;
    for (final svc in services) {
      if (svc.runtime != plugin.id) continue;
      try {
        await ServiceManager.instance.stop(svc.id);
        stoppedAny = true;
      } catch (e) {
        debugPrint('[InstallManager] stop ${svc.id} failed: $e');
      }
    }
    if (stoppedAny && Platform.isWindows) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await _safeDeleteDir(plugin.installPath);
    await unregister(plugin.id);
  }

  // ============================================================
  // server 包
  // ============================================================

  Future<void> _installServerPackage(
    MarketEntry entry,
    String tempPath, {
    required String marketName,
  }) async {
    final serviceId = 'svc-mkt-${entry.id}';
    final baseDir = await PluginPaths.serverDir(serviceId);
    await _extractZip(tempPath, baseDir.path);

    final serverJsonFile = File(p.join(baseDir.path, 'server.json'));
    if (serverJsonFile.existsSync()) {
      return _createServiceFromManifest(
          serverJsonFile, entry, baseDir, marketName);
    }
    final all = baseDir.listSync(recursive: true);
    for (final e in all) {
      if (e is File && p.basename(e.path) == 'server.json') {
        return _createServiceFromManifest(e, entry, baseDir, marketName);
      }
    }
    throw Exception('server 包内未找到 server.json');
  }

  /// 创建/更新服务配置
  /// 已存在时：保留用户自定义（autostart/keepForeground/env/maxRestart/pidFile/port），
  ///         更新 manifest 决定项（name/runtime/args/cwd/healthType/healthPath）
  Future<void> _createServiceFromManifest(
    File serverJsonFile,
    MarketEntry entry,
    Directory baseDir,
    String marketName,
  ) async {
    final raw = jsonDecode(await serverJsonFile.readAsString());
    final manifest = Map<String, dynamic>.from(raw as Map);

    final serviceName = manifest['serviceName']?.toString() ?? entry.name;
    final workDir = manifest['workDir']?.toString() ?? '';
    final entryFile = manifest['entry']?.toString() ?? '';
    final manifestPort = (manifest['port'] is num)
        ? (manifest['port'] as num).toInt()
        : null;

    // C7：runtime 推断抽到静态方法，与 ImportPackageDialog 共用同一逻辑，
    // 消除两处硬编码不一致（原来 Android 上会错误指向 *-win）。
    final runtime = resolveRuntimeForEntryFile(
      entryFile,
      isWindows: Platform.isWindows,
    );

    final cwd =
        workDir.isNotEmpty ? p.join(baseDir.path, workDir) : baseDir.path;

    final serviceId = 'svc-mkt-${entry.id}';

    // 已存在时保留用户自定义项
    final existing = ServiceManager.instance.find(serviceId);

    final config = ServiceConfig(
      id: serviceId,
      name: serviceName,
      port: existing?.port ?? manifestPort,
      runtime: runtime,
      args: [entryFile],
      cwd: cwd,
      autostart: existing?.autostart ?? false,
      keepForeground: existing?.keepForeground ?? false,
      env: existing?.env ?? const {},
      maxRestart: existing?.maxRestart ?? 1,
      executable: existing?.executable,
      healthType: 'process',
      healthPath: '/',
      pidFile: existing?.pidFile,
    );
    await ServiceManager.instance.addOrUpdate(config);

    final installed = InstalledPlugin(
      id: entry.id,
      version: entry.version,
      source: marketName,
      installPath: baseDir.path,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: 'server',
      desc: entry.desc,
      changelog: entry.changelog,
      icon: entry.icon,
    );
    await register(installed);
  }

  // ============================================================
  // 内部工具
  // ============================================================

  /// H1：Zip Slip 防护——entry 名解析后的绝对路径必须落在 targetDir 内。
  /// 合法包（市场包全部合法）行为完全不变；`../` 逃逸 entry 被跳过。
  bool _isSafeArchivePath(String targetDir, String entryName) {
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

  Future<void> _download(
    String url,
    String savePath,
    InstallCancelToken token,
    void Function(int received, int total) onProgress,
  ) async {
    final file = File(savePath);
    if (file.existsSync()) {
      await file.delete();
    }

    final dio = HttpClientFactory.dio;
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 400,
      ),
      cancelToken: token.dioToken,
    );

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final contentLength = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;

    final sink = file.openWrite();
    int received = 0;
    try {
      await for (final chunk in response.data!.stream) {
        if (token.isCancelled) {
          throw _CancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, contentLength);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<String> _md5OfFile(String path) async {
    final file = File(path);
    final stream = file.openRead();
    final digest = await crypto.md5.bind(stream).first;
    return digest.toString();
  }

  Future<void> _extractZip(String zipPath, String targetDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final baseDir = Directory(targetDir);
    if (!baseDir.existsSync()) {
      await baseDir.create(recursive: true);
    }
    for (final file in archive) {
      final name = file.name;

      // H1：Zip Slip 防护
      if (!_isSafeArchivePath(targetDir, name)) {
        debugPrint('[InstallManager] 跳过非法 entry: $name');
        continue;
      }

      if (file.isFile) {
        final outPath = p.join(targetDir, name);
        final outFile = File(outPath);
        final parent = outFile.parent;
        if (!parent.existsSync()) {
          await parent.create(recursive: true);
        }
        final data = file.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);
      } else {
        final dir = Directory(p.join(targetDir, name));
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
      }
    }
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

  Future<void> _safeDeleteFile(String path) async {
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      debugPrint('[InstallManager] delete file failed: $e');
    }
  }

  Future<void> _safeDeleteDir(String path) async {
    try {
      final d = Directory(path);
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('[InstallManager] delete dir failed: $e');
    }
  }

  Future<void> _cleanupOldVersions(String id, String keepVersion) async {
    try {
      final root = await PluginPaths.root();
      final dir = Directory(p.join(root.path, id));
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        debugPrint('[InstallManager] 已清理旧目录: $id');
      }
    } catch (e) {
      debugPrint('[InstallManager] _cleanupOldVersions failed: $e');
    }
  }

  String _applyGithubProxyIfNeeded(String url) {
    final sources = MarketManager.instance.getSources();
    if (sources.isEmpty) return url;
    final proxy = sources.first.proxy;
    if (proxy.isEmpty) return url;
    if (url.contains('github.com') ||
        url.contains('raw.githubusercontent.com')) {
      return '$proxy$url';
    }
    return url;
  }
}

class _CancelledException implements Exception {
  @override
  String toString() => '已取消';
}
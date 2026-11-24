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
import 'package:yuanying/modules/plugin_center/services/live_source_manager.dart';
import 'package:yuanying/modules/plugin_center/services/market_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/resource_install_transaction.dart';
import 'package:yuanying/modules/plugin_center/services/server_package_resolver.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/t4/services/python_runtime.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_service_manager.dart';

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
  bool _commitStarted = false;
  CancelToken _dioToken = CancelToken();

  bool get isCancelled => _cancelled;
  bool get isCommitStarted => _commitStarted;
  CancelToken get dioToken => _dioToken;

  bool beginCommit() {
    if (_cancelled) return false;
    _commitStarted = true;
    return true;
  }

  bool cancel() {
    if (_cancelled) return true;
    if (_commitStarted) return false;
    _cancelled = true;
    if (!_dioToken.isCancelled) {
      _dioToken.cancel('用户取消');
    }
    return true;
  }

  void reset() {
    _cancelled = false;
    _commitStarted = false;
    _dioToken = CancelToken();
  }
}

/// 系统安装的直装型插件信息
class SystemInstalledPlugin {
  final String packageName;
  final String pluginId;
  final String title;
  final String version;

  /// 'import' 或 'apk'：决定 UI 显示"固化"还是"登记"
  ///
  /// - `import`：解压型 APK 容器（qjs / agent / mpv），点按钮提取资源到应用内
  /// - `apk`：系统安装型（py / ijk / bundle / ffmpeg / 第三方应用），点按钮只登记
  ///
  /// 默认 `import`，保证未传此字段的旧调用行为不变。
  final String installMode;

  const SystemInstalledPlugin({
    required this.packageName,
    required this.pluginId,
    required this.title,
    required this.version,
    this.installMode = 'import',
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
    'com.dsplayer.plugin.mpv',
  ];

  /// 已知的系统安装型包名清单（installMode=apk，market.json 可能未声明 pkg）
  static const knownApkPackages = <String>[
    'com.dsplayer.plugin.python',
    'com.dsplayer.plugin.ijk',
    'com.dsplayer.plugin.bundle',
    'com.dsplayer.plugin.ffmpeg',
    'idm.internet.download.manager.plus',
    'bin.mt.plus.canary',
    'dev.aigw.app',
    'dev.raccoon2api',
    'dev.agentmore2api',
  ];

  /// 第三方应用包名（登记后仍可通过系统卸载）
  static const _thirdPartyPackages = <String>{
    'idm.internet.download.manager.plus',
    'bin.mt.plus.canary',
    'dev.aigw.app',
    'dev.raccoon2api',
    'dev.agentmore2api',
  };

  /// id → 系统安装型包名映射（market.json 无 pkg 时兜底）
  static const _idToApkPackage = <String, String>{
    'py': 'com.dsplayer.plugin.python',
    'ijk': 'com.dsplayer.plugin.ijk',
    'bundle': 'com.dsplayer.plugin.bundle',
    'ffmpeg': 'com.dsplayer.plugin.ffmpeg',
    'idmplus': 'idm.internet.download.manager.plus',
    'mtmanager': 'bin.mt.plus.canary',
    'aigw': 'dev.aigw.app',
    'raccoon': 'dev.raccoon2api',
    'zhipu-gw': 'dev.agentmore2api',
  };

  String? _knownApkPackageFor(String id) => _idToApkPackage[id];

  static const _pkgToId = <String, String>{
    'com.dsplayer.plugin.qjs': 'qjs',
    'com.dsplayer.plugin.agent': 'agent',
    'com.dsplayer.plugin.mpv': 'mpv',
    'com.dsplayer.plugin.python': 'py',
    'com.dsplayer.plugin.ijk': 'ijk',
    'com.dsplayer.plugin.bundle': 'bundle',
    'com.dsplayer.plugin.ffmpeg': 'ffmpeg',
    'idm.internet.download.manager.plus': 'idmplus',
    'bin.mt.plus.canary': 'mtmanager',
    'dev.aigw.app': 'aigw',
    'dev.raccoon2api': 'raccoon',
    'dev.agentmore2api': 'zhipu-gw',
  };

  static const _pkgToTitle = <String, String>{
    'com.dsplayer.plugin.qjs': 'QJS 爬虫引擎插件',
    'com.dsplayer.plugin.agent': 'AI 助手界面插件',
    'com.dsplayer.plugin.mpv': 'MPV 播放内核插件',
    'com.dsplayer.plugin.python': 'Python 爬虫引擎插件',
    'com.dsplayer.plugin.ijk': 'IJK 播放内核插件',
    'com.dsplayer.plugin.bundle': '插件整合包',
    'com.dsplayer.plugin.ffmpeg': 'FFmpeg 软解插件',
    'idm.internet.download.manager.plus': 'IDM+ 下载器',
    'bin.mt.plus.canary': 'MT管理器',
    'dev.aigw.app': 'AI 聚合网关',
    'dev.raccoon2api': '小浣熊',
    'dev.agentmore2api': '智谱清言网关',
  };

  Box get _box => Hive.box(PluginStorageKeys.installedBox);

  // ============================================================
  // 已装登记
  // ============================================================

  List<InstalledPlugin> getAllInstalled() {
    final raw = _box.get(PluginStorageKeys.installedList);
    if (raw is! List) return [];
    return raw
        .map(
          (e) => InstalledPlugin.fromJson(Map<String, dynamic>.from(e as Map)),
        )
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
        final previous = list[idx];
        list[idx] = InstalledPlugin(
          id: plugin.id,
          version: plugin.version,
          source: plugin.source,
          installPath: plugin.installPath,
          enabled: previous.enabled,
          pinned: previous.pinned,
          pinnedAtMs: previous.pinnedAtMs,
          installedAtMs: previous.installedAtMs,
          type: plugin.type,
          desc: plugin.desc ?? previous.desc,
          changelog: plugin.changelog ?? previous.changelog,
          icon: plugin.icon ?? previous.icon,
          extras: {
            ...previous.extras,
            ...plugin.extras,
          },
        );
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

  /// 停止指定运行时的所有消费者，供手动覆盖安装复用。
  Future<void> stopRuntimeConsumers(String runtimeId) async {
    if (runtimeId == 'python-win') {
      try {
        await PythonRuntime.shutdown();
      } catch (e) {
        debugPrint('[InstallManager] shutdown py worker failed: $e');
      }
    }
    if (runtimeId == 'nodejs-win' || runtimeId == 'nodejs') {
      try {
        await NodeJSService.instance.stopForPluginDisabled();
      } catch (e) {
        debugPrint('[InstallManager] stop nodejs worker failed: $e');
      }
    }
    if (runtimeId == 'proot') {
      try {
        await SandboxServiceManager.instance.stopAll();
      } catch (e) {
        debugPrint('[InstallManager] stop sandbox services failed: $e');
      }
    }
    for (final service in ServiceManager.instance.getAll()) {
      if (service.runtime != runtimeId) continue;
      await ServiceManager.instance.stop(service.id);
    }
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
          pinnedAtMs: pinned ? DateTime.now().millisecondsSinceEpoch : null,
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
        final iconIsAbsolute =
            plugin.icon?.startsWith('http://') == true ||
            plugin.icon?.startsWith('https://') == true;
        if (plugin.desc != null &&
            plugin.changelog != null &&
            plugin.icon != null &&
            iconIsAbsolute) {
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
        final resolvedIcon = _resolvedIcon(matched);
        final nextDesc = plugin.desc ?? matched.desc;
        final nextChangelog = plugin.changelog ?? matched.changelog;
        final nextIcon = iconIsAbsolute
            ? plugin.icon
            : resolvedIcon ?? plugin.icon;
        if (nextDesc == plugin.desc &&
            nextChangelog == plugin.changelog &&
            nextIcon == plugin.icon) {
          continue;
        }
        list[i] = plugin.copyWith(
          desc: nextDesc,
          changelog: nextChangelog,
          icon: nextIcon,
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

  /// 扫描系统安装的直装型插件。
  ///
  /// [marketEntries]：市场条目列表。传入后会从 market.json 的 `pkg` 字段
  /// 动态补充「包名 → 市场 id」映射。不传（null）时退化为纯硬编码，
  /// 与旧版行为完全一致。
  ///
  /// 返回项已排除「注册表里已登记」的条目。
  Future<List<SystemInstalledPlugin>> scanSystemImportPlugins({
    List<MarketEntry>? marketEntries,
  }) async {
    if (!Platform.isAndroid) return [];
    final result = <SystemInstalledPlugin>[];

    // 合并 import 型（qjs/agent/mpv）和 apk 型（python/ijk/bundle/ffmpeg 等）所有已知包
    final pkgToId = <String, String>{..._pkgToId};
    final pkgToTitle = <String, String>{..._pkgToTitle};
    // 包名 → installMode。来源优先级：硬编码清单 > market.json。
    // 两者冲突时硬编码优先（人工核对过的映射不被市场数据覆盖）。
    final pkgToMode = <String, String>{};
    final allPackages = <String>{};

    // 1. 硬编码兜底：import 型
    for (final pkg in knownImportPackages) {
      allPackages.add(pkg);
      pkgToMode[pkg] = 'import';
    }
    // 2. 硬编码兜底：apk 型
    for (final pkg in knownApkPackages) {
      allPackages.add(pkg);
      pkgToMode[pkg] = 'apk';
    }
    // 3. 市场数据：动态补充 pkg / id / title / mode（硬编码优先，不覆盖）
    if (marketEntries != null) {
      for (final entry in marketEntries) {
        final pkg = entry.pkg;
        if (pkg == null || pkg.isEmpty) continue;
        // 只关注可能以 APK 形态系统安装的条目：
        // type=apk，或 type=import 但下载物是 .apk（解压型 APK 容器）
        if (entry.type != 'apk' && !_isApkUrl(entry.url)) continue;
        allPackages.add(pkg);
        pkgToId.putIfAbsent(pkg, () => entry.id);
        pkgToTitle.putIfAbsent(pkg, () => entry.name);
        // installMode 从 market.json 的 type 推断；硬编码已存在的不覆盖
        pkgToMode.putIfAbsent(
          pkg,
          () => entry.type == 'apk' ? 'apk' : 'import',
        );
      }
    }

    for (final pkg in allPackages) {
      final installed = await _isPackageInstalled(pkg);
      if (!installed) continue;
      final id = pkgToId[pkg] ?? pkg;
      if (findInstalled(id) != null) continue;
      final version = await _getPackageVersion(pkg) ?? '';
      result.add(
        SystemInstalledPlugin(
          packageName: pkg,
          pluginId: id,
          title: pkgToTitle[pkg] ?? id,
          version: version,
          installMode: pkgToMode[pkg] ?? 'import',
        ),
      );
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
        await register(
          InstalledPlugin(
            id: info.pluginId,
            version: info.version.isEmpty ? '0.0.0' : info.version,
            source: '系统应用',
            installPath: '',
            enabled: true,
            pinned: false,
            installedAtMs: DateTime.now().millisecondsSinceEpoch,
            type: 'apk',
            desc:
                pluginJson['desc']?.toString() ?? '系统安装型插件（通过 APK 安装，卸载需走系统卸载）',
            extras: {
              'platform': 'android',
              'installMode': 'apk',
              'apkPackage': info.packageName,
            },
          ),
        );
        debugPrint(
          '[InstallManager] 已登记系统安装型插件：${info.pluginId} '
          '(pkg=${info.packageName}, v=${info.version})',
        );
        return true;
      }

      // ===== installMode = import：可固化的插件（qjs/agent/mpv）=====
      if (installMode != 'import') return false;

      // 版本来源优先级：plugin.json.pluginVersion > APK versionName > '0.0.0'
      // 原因：市场安装时登记的 version 取自 market.json 的 version 字段
      // （实际对应 plugin.json.pluginVersion）。固化时若用 APK 的 versionName，
      // 同一插件会出现「市场安装」与「系统固化」登记出不同 version，
      // 导致 installStateOf 误判为「可更新」或「未安装」。
      // 当前 qjs(1.0.5) / agent(1.1.0) / mpv(1.0.2) 三包两值恰好一致，
      // 此改动对现有场景零行为变化；仅在未来版本号分叉时防止错判。
      final pluginVersionInJson = pluginJson['pluginVersion']?.toString();
      final effectiveVersion =
          (pluginVersionInJson != null && pluginVersionInJson.isNotEmpty)
          ? pluginVersionInJson
          : (info.version.isEmpty ? '0.0.0' : info.version);

      final fakeEntry = MarketEntry(
        id: info.pluginId,
        name: info.title,
        version: effectiveVersion,
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

  /// 手动导入 APK：交给系统安装器，不在此时登记插件。
  /// 安装完成后由插件页扫描系统应用并通过“固化”提取资源。
  Future<void> installLocalApk(String apkPath) async {
    if (!Platform.isAndroid) {
      throw Exception('APK 仅支持 Android 平台');
    }
    final file = File(apkPath);
    if (!file.existsSync()) {
      throw Exception('APK 文件不存在');
    }
    final result = await InstallPlugin.install(file.path);
    if (result['isSuccess'] != true) {
      throw Exception('APK 安装失败：${result['errorMessage'] ?? ''}');
    }
  }

  Future<void> install(
    MarketEntry entry, {
    required String indexBaseUrl,
    required String marketName,
    InstallCancelToken? cancelToken,
    void Function(InstallProgress)? onProgress,
  }) async {
    PluginPaths.ensureSafePathSegment(entry.id, '插件 ID');
    PluginPaths.ensureSafePathSegment(entry.version, '插件版本');
    final token = cancelToken ?? InstallCancelToken();
    if (cancelToken == null) token.reset();

    void emit(InstallStage stage, {int r = 0, int t = 0}) {
      onProgress?.call(InstallProgress(stage: stage, received: r, total: t));
    }

    // 市场归并后，每个条目可能来自不同市场。优先使用条目自身携带的
    // 索引前缀和来源名称，参数仅作为旧调用方及手动构造条目的兜底。
    final effectiveIndexBaseUrl = entry.indexBaseUrl.isNotEmpty
        ? entry.indexBaseUrl
        : indexBaseUrl;
    final effectiveMarketName = entry.marketName.isNotEmpty
        ? entry.marketName
        : marketName;
    _throwIfCancelled(token);

    // ===== type=apk 分支（仅 Android） =====
    // 系统直装型 APK：跳系统安装器。_installApkPackage 内部还会按 APK 内
    // assets/plugin.json 的 installMode 再分流（import → 提取到私有目录，
    // apk → 系统安装）。
    if (entry.type == 'apk') {
      if (!Platform.isAndroid) {
        throw Exception('APK 仅支持 Android 平台');
      }
      emit(InstallStage.downloading, r: 0, t: entry.sizeBytes);
      await _installApkPackage(
        entry,
        indexBaseUrl: effectiveIndexBaseUrl,
        marketName: effectiveMarketName,
        cancelToken: token,
        onProgress: (r, t) => emit(InstallStage.downloading, r: r, t: t),
      );
      _throwIfCancelled(token);
      emit(InstallStage.done);
      return;
    }

    // ===== type=live 分支 =====
    if (entry.type == 'live') {
      emit(InstallStage.downloading, r: 0, t: entry.sizeBytes);
      await _installLivePackage(
        entry,
        indexBaseUrl: effectiveIndexBaseUrl,
        marketName: effectiveMarketName,
        cancelToken: token,
        onProgress: (r, t) => emit(InstallStage.downloading, r: r, t: t),
      );
      _throwIfCancelled(token);
      emit(InstallStage.done);
      return;
    }

    final downloadUrl = MarketManager.resolveUrl(
      entry.url,
      effectiveIndexBaseUrl,
    );
    final finalUrl = _applyGithubProxyIfNeeded(downloadUrl, entry);

    final tempPath = await PluginPaths.downloadFilePath(
      entry.id,
      entry.version,
    );
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
    if (token.isCancelled) {
      await _safeDeleteFile(tempPath);
      emit(InstallStage.failed);
      throw _CancelledException();
    }

    // ===== type=server 分支 =====
    if (entry.type == 'server') {
      emit(InstallStage.extracting);
      try {
        await _installServerPackage(
          entry,
          tempPath,
          marketName: effectiveMarketName,
          cancelToken: token,
        );
      } finally {
        await _safeDeleteFile(tempPath);
      }
      emit(InstallStage.done);
      return;
    }

    // ===== type=source 分支 =====
    if (entry.type == 'source') {
      emit(InstallStage.extracting);
      try {
        await _installSourcePackage(
          entry,
          tempPath,
          marketName: effectiveMarketName,
          cancelToken: token,
        );
      } finally {
        await _safeDeleteFile(tempPath);
      }
      emit(InstallStage.done);
      return;
    }

    // ===== type=import 分支 =====
    //
    // 按「下载 URL 后缀是否为 .apk」再分两路：
    //
    // 1. .apk 后缀 → 「解压型 APK」：包内是 APK 目录结构
    //    （assets/plugin.json + assets/www/ 或 lib/{abi}/），
    //    需按 plugin.json 的 kind 提取有效资源到 plugins/{id}/，
    //    APK 自身元数据（META-INF/classes.dex/等）丢弃。
    //    agent / qjs / mpv 均属此类型。
    //
    // 2. 非 .apk 后缀 → 「普通 zip」：包内根目录就是 plugin.json / bin/ 等
    //    应用数据，原样解压到 plugins/{id}/。nodejs / mediaProxy 属此类型。
    //
    // C2 修复（普通 zip 路径）：先解压到同卷临时目录，成功后再清理旧目录
    // 并原子 rename。原流程是「先删旧目录 → 解压到最终路径」，解压失败会
    // 留下「注册表还指向旧路径，但旧目录已被删」的脏状态，用户必须手动
    // 卸载重装才能恢复。新流程下解压失败时旧目录与注册表均保持原样。
    final isApkContainer = _isApkUrl(downloadUrl);

    final root = await PluginPaths.root();
    final finalDir = p.join(root.path, entry.id);
    final tmpDir = Directory(
      p.join(
        root.path,
        '.tmp-${entry.id}-${entry.version}-'
        '${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    emit(InstallStage.extracting);
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

    // ===== format:2 制品提取 =====
    // 只在包内 manifest 明确声明 format=2 时启用，旧包继续走原有分支。
    final format2Manifest = await _findFormat2Manifest(tmpDir.path);
    if (format2Manifest != null) {
      try {
        _throwIfCancelled(token);
        await _installFormat2Package(
          manifestFile: format2Manifest.file,
          manifest: format2Manifest.json,
          tmpDir: tmpDir,
          entry: entry,
          marketName: effectiveMarketName,
          root: root,
          finalDir: finalDir,
          cancelToken: token,
          onRegistering: () => emit(InstallStage.registering),
        );
      } catch (e) {
        await _safeDeleteDir(tmpDir.path);
        emit(InstallStage.failed);
        throw Exception('Format2 提取失败：$e');
      }
      emit(InstallStage.done);
      return;
    }

    // ===== 解压型 APK：按 kind 提取 =====
    if (isApkContainer) {
      final apkPluginJson = File(p.join(tmpDir.path, 'assets', 'plugin.json'));
      if (!apkPluginJson.existsSync()) {
        // .apk 后缀但内容不是 APK 结构 → 明确的打包错误，暴露而不是掩盖
        await _safeDeleteDir(tmpDir.path);
        emit(InstallStage.failed);
        throw Exception(
          'APK 容器缺少 assets/plugin.json（包结构不符合解压型 APK 约定）',
        );
      }

      Map<String, dynamic> pluginJson;
      try {
        pluginJson =
            jsonDecode(await apkPluginJson.readAsString())
                as Map<String, dynamic>;
      } catch (e) {
        await _safeDeleteDir(tmpDir.path);
        emit(InstallStage.failed);
        throw Exception('plugin.json 解析失败：$e');
      }

      // 防御：installMode=apk 说明市场把系统直装包错标成 type=import
      final installMode = pluginJson['installMode']?.toString() ?? '';
      if (installMode == 'apk') {
        await _safeDeleteDir(tmpDir.path);
        emit(InstallStage.failed);
        throw Exception(
          '该插件为系统直装型（installMode=apk），'
          '市场条目 type 应为 apk，当前为 import',
        );
      }

      final kind = pluginJson['kind']?.toString() ?? '';
      final apkStage = Directory(
        p.join(
          root.path,
          '.apk-stage-${entry.id}-'
          '${DateTime.now().microsecondsSinceEpoch}',
        ),
      );

      try {
        _throwIfCancelled(token);
        await apkStage.create(recursive: true);
        await _extractApkContainer(tmpDir.path, apkStage.path, kind);
        await _commitStagedDirectory(
          root: root,
          staging: apkStage,
          finalDir: finalDir,
          tag: 'apk-${entry.id}',
          writeRegistry: () => register(
            InstalledPlugin(
              id: entry.id,
              version: entry.version,
              source: effectiveMarketName,
              installPath: finalDir,
              enabled: true,
              pinned: false,
              installedAtMs: DateTime.now().millisecondsSinceEpoch,
              type: entry.type,
              desc: entry.desc,
              changelog: entry.changelog,
              icon: _resolvedIcon(entry),
              extras: {
                'platform': Platform.isWindows ? 'win32' : 'android',
                'installMode': 'import',
                if (kind.isNotEmpty) 'kind': kind,
              },
            ),
          ),
          onRegistering: () => emit(InstallStage.registering),
          isCancelled: () => token.isCancelled,
        );
      } catch (e) {
        await _safeDeleteDir(apkStage.path);
        await _safeDeleteDir(tmpDir.path);
        emit(InstallStage.failed);
        throw Exception('APK 容器提取失败：$e');
      }
      await _safeDeleteDir(tmpDir.path);

      emit(InstallStage.done);
      return;
    }

    // ===== 普通 zip：原样替换 =====
    final installed = InstalledPlugin(
      id: entry.id,
      version: entry.version,
      source: effectiveMarketName,
      installPath: finalDir,
      enabled: true,
      pinned: false,
      installedAtMs: DateTime.now().millisecondsSinceEpoch,
      type: entry.type,
      desc: entry.desc,
      changelog: entry.changelog,
      icon: _resolvedIcon(entry),
      extras: {
        'platform': Platform.isWindows ? 'win32' : 'android',
      },
    );
    try {
      _throwIfCancelled(token);
      await _commitStagedDirectory(
        root: root,
        staging: tmpDir,
        finalDir: finalDir,
        tag: 'zip-${entry.id}',
        writeRegistry: () => register(installed),
        onRegistering: () => emit(InstallStage.registering),
        isCancelled: () => token.isCancelled,
      );
    } catch (e) {
      await _safeDeleteDir(tmpDir.path);
      emit(InstallStage.failed);
      throw Exception('替换目录失败：$e');
    }

    emit(InstallStage.done);
  }

  /// 按入口文件推断运行时（Windows / Android 分别映射到带/不带 `-win` 后缀的 id）。
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
    final finalUrl = _applyGithubProxyIfNeeded(downloadUrl, entry);

    final tempPath = (await PluginPaths.downloadFilePath(
      entry.id,
      entry.version,
    )).replaceAll('.zip', '.apk');
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
        await _installApkAsImport(
          entry,
          archive,
          pluginJson!,
          marketName,
          cancelToken: cancelToken,
        );
        return;
      }

      _throwIfCancelled(cancelToken);
      final res = await InstallPlugin.install(tempPath);
      if (res['isSuccess'] != true) {
        throw Exception('安装失败：${res['errorMessage'] ?? ''}');
      }

      final apkPackage = entry.pkg ?? _knownApkPackageFor(entry.id);
      if (apkPackage == null || apkPackage.isEmpty) {
        // 数据缺陷告警：type=apk 但 pkg 缺失。
        // 不抛错（避免"系统已装但注册表无记录"导致市场反复拉起安装器，
        // 形成用户无法自愈的死循环）。
        // 不阻塞 register（保证插件 Tab 不显示固化卡片）。
        // 后果：isInstalled 因 pkg 缺失返回 false，市场卡片保持"安装"状态；
        // 用户可从插件 Tab 扫描 → 固化 → solidifySystemPlugin 的 apk 分支
        // 会用 info.packageName 正确登记 extras.apkPackage 而自愈。
        // 发现此日志时应：在 market.json 补 pkg，或在 _idToApkPackage 补兜底。
        debugPrint(
          '[InstallManager] WARN: 插件 ${entry.id} 缺少 pkg，'
          'apkPackage 将登记为空，isInstalled 判定会始终为 false',
        );
      }
      _throwIfCancelled(cancelToken);
      await register(
        InstalledPlugin(
          id: entry.id,
          version: entry.version,
          source: marketName,
          installPath: '',
          enabled: true,
          pinned: false,
          installedAtMs: DateTime.now().millisecondsSinceEpoch,
          type: 'apk',
          desc: entry.desc,
          changelog: entry.changelog,
          icon: _resolvedIcon(entry),
          extras: {
            'platform': 'android',
            'installMode': 'apk',
            if (apkPackage != null) 'apkPackage': apkPackage,
          },
        ),
      );
    } finally {
      await _safeDeleteFile(tempPath);
    }
  }

  /// installMode == 'import'：按 kind 定制提取到私有目录
  Future<void> _installApkAsImport(
    MarketEntry entry,
    Archive archive,
    Map<String, dynamic> pluginJson,
    String marketName, {
    InstallCancelToken? cancelToken,
  }) async {
    final kind = pluginJson['kind']?.toString() ?? '';

    final root = await PluginPaths.root();
    final targetDir = await PluginPaths.pluginDir(entry.id, entry.version);
    final staging = Directory(
      p.join(
        root.path,
        '.apk-import-stage-${entry.id}-'
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await staging.create(recursive: true);

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

    try {
      for (final f in archive) {
        if (!f.isFile) continue;

        // H1：Zip Slip 防护——目标路径必须落在 staging 内
        if (!_isSafeArchivePath(staging.path, f.name)) {
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
            await _writeArchiveFile(f, staging.path, 'plugin.json');
            continue;
          }
          if (abiDir != null && f.name.startsWith('lib/$abiDir/')) {
            final fileName = p.basename(f.name);
            await _writeArchiveFile(f, staging.path, fileName);
          }
          continue;
        }

        if (kind == 'agent-ui') {
          if (f.name == 'assets/plugin.json') {
            await _writeArchiveFile(f, staging.path, 'plugin.json');
            continue;
          }
          if (f.name.startsWith('assets/www/')) {
            final rel = f.name.substring('assets/www/'.length);
            if (rel.isEmpty) continue;
            await _writeArchiveFile(f, staging.path, rel);
          }
          continue;
        }

        if (f.name == 'assets/plugin.json') {
          await _writeArchiveFile(f, staging.path, 'plugin.json');
        } else if (f.name.startsWith('assets/')) {
          final rel = f.name.substring('assets/'.length);
          if (rel.isEmpty) continue;
          await _writeArchiveFile(f, staging.path, rel);
        } else if (abiDir != null && f.name.startsWith('lib/$abiDir/')) {
          final fileName = p.basename(f.name);
          await _writeArchiveFile(f, staging.path, fileName);
        }
      }

      await _commitStagedDirectory(
        root: root,
        staging: staging,
        finalDir: targetDir.path,
        tag: 'apk-import-${entry.id}',
        isCancelled: () => cancelToken?.isCancelled ?? false,
        writeRegistry: () => register(
          InstalledPlugin(
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
            icon: _resolvedIcon(entry),
            extras: {
              'platform': 'android',
              'installMode': 'import',
              if (kind.isNotEmpty) 'kind': kind,
            },
          ),
        ),
      );
    } catch (_) {
      await _safeDeleteDir(staging.path);
      rethrow;
    }
  }

  /// 判断下载 URL 是否为 .apk 后缀（忽略 query/fragment/代理前缀）。
  /// 用于 type=import 分支区分「解压型 APK」与「普通 zip」。
  bool _isApkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path.toLowerCase().endsWith('.apk');
    } catch (_) {
      return url.toLowerCase().endsWith('.apk');
    }
  }

  /// 从已解压的临时目录按 kind 提取 APK 容器内容到 targetDir。
  ///
  /// 仅处理 assets/ 与 lib/{abi}/ 下的内容；APK 自身元数据
  /// （META-INF / classes.dex / kotlin / resources.arsc /
  /// AndroidManifest.xml）一律丢弃。
  ///
  /// 与 [_installApkAsImport] 的差别：
  /// - 本方法输入是「已解压目录」，供 type=import + .apk 后缀的条目
  ///   （agent / qjs / mpv 等）使用；
  /// - [_installApkAsImport] 输入是 Archive，供 type=apk 分支中
  ///   installMode=import 的系统安装型 APK 使用。
  /// 两者对 kind → 落盘结构的映射保持一致，避免同一插件两种安装
  /// 路径产出不同目录布局。
  Future<void> _extractApkContainer(
    String srcDir,
    String targetDir,
    String kind,
  ) async {
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

    final srcRoot = Directory(srcDir);
    await for (final entity in srcRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: srcDir).replaceAll('\\', '/');

      // 统一过滤：APK 自身元数据一律丢弃
      if (rel.startsWith('META-INF/')) continue;
      if (rel == 'AndroidManifest.xml') continue;
      if (rel == 'resources.arsc') continue;
      if (rel.startsWith('kotlin/')) continue;
      if (rel == 'classes.dex') continue;
      if (rel.startsWith('classes') && rel.endsWith('.dex')) continue;

      String? outRel;
      if (kind == 'qjs-engine') {
        if (rel == 'assets/plugin.json') {
          outRel = 'plugin.json';
        } else if (abiDir != null && rel.startsWith('lib/$abiDir/')) {
          outRel = p.basename(rel);
        }
      } else if (kind == 'agent-ui') {
        if (rel == 'assets/plugin.json') {
          outRel = 'plugin.json';
        } else if (rel.startsWith('assets/www/')) {
          final sub = rel.substring('assets/www/'.length);
          if (sub.isNotEmpty) outRel = sub;
        }
      } else {
        // 通用：assets/ 全部内嵌；lib/{abi}/ 平铺到根
        if (rel == 'assets/plugin.json') {
          outRel = 'plugin.json';
        } else if (rel.startsWith('assets/')) {
          final sub = rel.substring('assets/'.length);
          if (sub.isNotEmpty) outRel = sub;
        } else if (abiDir != null && rel.startsWith('lib/$abiDir/')) {
          outRel = p.basename(rel);
        }
      }

      if (outRel == null) continue;
      // H1：Zip Slip 防护（与 _installApkAsImport 同语义）
      if (!_isSafeArchivePath(targetDir, outRel)) {
        debugPrint('[InstallManager] 跳过非法 entry: $rel');
        continue;
      }

      final outFile = File(p.join(targetDir, outRel));
      await outFile.parent.create(recursive: true);
      await entity.copy(outFile.path);
    }
  }

  /// 查找 format:2 manifest。根目录优先，其次兼容 APK/旧打包目录中的
  /// assets/plugin.json。解析失败或不是 format:2 时返回 null，由旧逻辑接手。
  Future<({File file, Map<String, dynamic> json})?> _findFormat2Manifest(
    String tmpDir,
  ) async {
    final candidates = [
      File(p.join(tmpDir, 'plugin.json')),
      File(p.join(tmpDir, 'assets', 'plugin.json')),
    ];
    for (final file in candidates) {
      if (!file.existsSync()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final json = Map<String, dynamic>.from(decoded);
        final format = json['format'];
        if (format == 2 || format?.toString() == '2') {
          return (file: file, json: json);
        }
      } catch (_) {
        // manifest 无法解析时不应改变旧包的安装行为。
      }
    }
    return null;
  }

  /// format:2 提取入口。
  ///
  /// 只提取 manifest、native.libs、dex.modules 和 dex.libs，使用 staging
  /// 目录完成校验后再替换正式目录。provides 等业务字段本阶段不消费。
  Future<void> _installFormat2Package({
    required File manifestFile,
    required Map<String, dynamic> manifest,
    required Directory tmpDir,
    required MarketEntry entry,
    required String marketName,
    required Directory root,
    required String finalDir,
    required InstallCancelToken cancelToken,
    required void Function() onRegistering,
  }) async {
    final platformKey = Platform.isWindows
        ? 'win32'
        : Platform.isAndroid
        ? 'android'
        : '';
    if (platformKey.isEmpty) {
      throw Exception('format:2 仅支持 Android / Windows');
    }

    final platforms = _format2StringList(manifest['platforms']);
    if (!platforms.contains(platformKey)) {
      throw Exception('format:2 包不支持当前平台：$platformKey');
    }

    final abi = Platform.isAndroid ? _currentAndroidAbiName() : null;
    final artifacts = _format2Map(manifest['artifacts']);
    if (artifacts == null) {
      throw Exception('format:2 包缺少 artifacts');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final staging = Directory(
      p.join(root.path, '.format2-stage-${entry.id}-$stamp'),
    );
    final usedTargets = <String>{};

    try {
      await staging.create(recursive: true);
      final manifestSourceRel = p
          .relative(manifestFile.path, from: tmpDir.path)
          .replaceAll('\\', '/');
      await _copyFormat2Artifact(
        sourceRoot: tmpDir.path,
        sourceRel: manifestSourceRel,
        targetRoot: staging.path,
        targetRel: 'plugin.json',
        usedTargets: usedTargets,
      );

      var extractedCount = 0;

      final native = _format2Map(artifacts['native']);
      final nativeLibs = _format2Map(native?['libs']);
      if (nativeLibs != null) {
        final sources = _selectFormat2Sources(
          nativeLibs,
          platformKey: platformKey,
          abi: abi,
        );
        if (sources.isEmpty &&
            _hasFormat2PlatformOrAbiKey(
              nativeLibs,
              platformKey: platformKey,
              abi: abi,
            )) {
          throw Exception('format:2 包缺少当前 ABI 的 native 制品');
        }
        for (final source in sources) {
          final sourceRel = _resolveFormat2AbiPath(source, abi);
          await _copyFormat2Artifact(
            sourceRoot: tmpDir.path,
            sourceRel: sourceRel,
            targetRoot: staging.path,
            targetRel: p.basename(sourceRel),
            usedTargets: usedTargets,
          );
          extractedCount++;
        }
      }

      final dex = _format2Map(artifacts['dex']);
      if (dex != null) {
        final modules = _format2StringList(dex['modules']);
        for (final source in modules) {
          final sourceRel = _resolveFormat2AbiPath(source, abi);
          await _copyFormat2Artifact(
            sourceRoot: tmpDir.path,
            sourceRel: sourceRel,
            targetRoot: staging.path,
            targetRel: p.basename(sourceRel),
            usedTargets: usedTargets,
          );
          extractedCount++;
        }

        final dexLibs = _format2Map(dex['libs']);
        if (dexLibs != null) {
          final sources = _selectFormat2Sources(
            dexLibs,
            platformKey: platformKey,
            abi: abi,
          );
          if (sources.isEmpty &&
              _hasFormat2PlatformOrAbiKey(
                dexLibs,
                platformKey: platformKey,
                abi: abi,
              )) {
            throw Exception('format:2 包缺少当前 ABI 的 dex 依赖库');
          }
          for (final source in sources) {
            final sourceRel = _resolveFormat2AbiPath(source, abi);
            await _copyFormat2Artifact(
              sourceRoot: tmpDir.path,
              sourceRel: sourceRel,
              targetRoot: staging.path,
              targetRel: p.join('libs', p.basename(sourceRel)),
              usedTargets: usedTargets,
            );
            extractedCount++;
          }
        }
      }

      if (extractedCount == 0) {
        throw Exception('format:2 包没有可提取的已知制品');
      }

      final kind = manifest['kind']?.toString() ?? '';
      await _commitStagedDirectory(
        root: root,
        staging: staging,
        finalDir: finalDir,
        tag: 'format2-${entry.id}',
        onRegistering: onRegistering,
        isCancelled: () => cancelToken.isCancelled,
        writeRegistry: () => register(
          InstalledPlugin(
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
            icon: _resolvedIcon(entry),
            extras: {
              'platform': platformKey,
              'installMode': 'import',
              if (kind.isNotEmpty) 'kind': kind,
            },
          ),
        ),
      );
    } finally {
      await _safeDeleteDir(staging.path);
      await _safeDeleteDir(tmpDir.path);
    }
  }

  String? _currentAndroidAbiName() {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'arm64-v8a';
    if (abi == Abi.androidArm) return 'armeabi-v7a';
    if (abi == Abi.androidX64) return 'x86_64';
    if (abi == Abi.androidIA32) return 'x86';
    return null;
  }

  Map<String, dynamic>? _format2Map(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  List<String> _format2StringList(dynamic value) {
    if (value is String) {
      return value.trim().isEmpty ? const [] : [value];
    }
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<String> _selectFormat2Sources(
    dynamic node, {
    required String platformKey,
    required String? abi,
  }) {
    if (node is Map) {
      final map = _format2Map(node)!;
      if (map.containsKey(platformKey)) {
        return _selectFormat2Sources(
          map[platformKey],
          platformKey: platformKey,
          abi: abi,
        );
      }
      if (abi != null && map.containsKey(abi)) {
        return _format2StringList(map[abi]);
      }
      if (abi != null && map.containsKey('*')) {
        return _format2StringList(map['*']);
      }
      return const [];
    }
    return _format2StringList(node);
  }

  bool _hasFormat2PlatformOrAbiKey(
    Map<String, dynamic> map, {
    required String platformKey,
    required String? abi,
  }) {
    if (map.containsKey(platformKey)) return true;
    if (abi != null && (map.containsKey(abi) || map.containsKey('*'))) {
      return true;
    }
    return false;
  }

  String _resolveFormat2AbiPath(String source, String? abi) {
    final normalized = source.replaceAll('\\', '/');
    if (!normalized.contains('<abi>')) return normalized;
    if (abi == null || abi.isEmpty) {
      throw Exception('format:2 制品需要 ABI，但无法识别当前宿主 ABI');
    }
    return normalized.replaceAll('<abi>', abi);
  }

  Future<void> _copyFormat2Artifact({
    required String sourceRoot,
    required String sourceRel,
    required String targetRoot,
    required String targetRel,
    required Set<String> usedTargets,
  }) async {
    if (!_isSafeArchivePath(sourceRoot, sourceRel)) {
      throw Exception('format:2 非法制品路径：$sourceRel');
    }
    if (!_isSafeArchivePath(targetRoot, targetRel)) {
      throw Exception('format:2 非法目标路径：$targetRel');
    }
    final normalizedTarget = p.normalize(targetRel);
    if (normalizedTarget == '.' || p.isAbsolute(normalizedTarget)) {
      throw Exception('format:2 非法目标路径：$targetRel');
    }
    if (!usedTargets.add(normalizedTarget)) {
      throw Exception('format:2 制品目标冲突：$normalizedTarget');
    }

    final source = File(p.join(sourceRoot, sourceRel));
    if (!source.existsSync()) {
      throw Exception('format:2 制品不存在：$sourceRel');
    }
    final target = File(p.join(targetRoot, normalizedTarget));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
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
    final finalUrl = _applyGithubProxyIfNeeded(downloadUrl, entry);

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
    _throwIfCancelled(cancelToken);

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

    final existingPlugin = findInstalled(entry.id);
    final previousKeys = <String>{
      if (existingPlugin?.extras['liveKeys'] is List)
        ...(existingPlugin!.extras['liveKeys'] as List).map(
          (key) => key.toString(),
        ),
    };
    _throwIfCancelled(cancelToken);
    final transaction = LiveConfigTransaction.capture();
    try {
      final result = await LiveSourceManager.applyPackage(
        lives: lives,
        previousManagedKeys: previousKeys,
        replaceManaged: existingPlugin != null,
        claimExistingNames: existingPlugin == null,
        overwriteExistingNames: true,
      );
      if (!result.hasChanges) {
        throw Exception('没有新增或需要更新的直播源');
      }
      if (!cancelToken.beginCommit()) {
        throw _CancelledException();
      }

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
        icon: _resolvedIcon(entry),
        extras: {'liveKeys': result.managedKeys},
      );
      await register(installed);
      transaction.commit();
    } catch (_) {
      await transaction.rollback();
      rethrow;
    }
  }

  // ============================================================
  // type=source
  // ============================================================

  Future<void> _installSourcePackage(
    MarketEntry entry,
    String tempPath, {
    required String marketName,
    required InstallCancelToken cancelToken,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('source_install_');
    try {
      _throwIfCancelled(cancelToken);
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
        icon: _resolvedIcon(entry),
        extras: {
          if (target != null) 'sourceTarget': target,
        },
      );
      await SourcePackageTransaction.run<void>(
        tag: 'market-${entry.id}',
        staging: tempDir,
        dataRoot: Directory(extractRoot),
        isCancelled: () => cancelToken.isCancelled,
        afterFilesCommitted: () async {
          if (!cancelToken.beginCommit()) {
            throw _CancelledException();
          }
          await register(installed);
        },
      );
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

    // Node.js 运行时卸载：先杀掉 NodeJSService 的猫影视外部进程。
    // Windows 下可释放 node.exe 文件占用；Android 同时解除前台保活。
    if (plugin.id == 'nodejs-win' || plugin.id == 'nodejs') {
      try {
        await NodeJSService.instance.stopForPluginDisabled();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[InstallManager] stop nodejs service failed: $e');
      }
    }

    // proot 卸载：先停所有沙盒服务
    if (plugin.id == 'proot') {
      try {
        await SandboxServiceManager.instance.stopAll();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[InstallManager] stop sandbox services failed: $e');
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
      await _deleteInstalledPath(plugin.installPath);
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
      await _deleteInstalledPath(plugin.installPath);
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
    await _deleteInstalledPath(plugin.installPath);
    await unregister(plugin.id);
  }

  // ============================================================
  // server 包
  // ============================================================

  Future<void> _installServerPackage(
    MarketEntry entry,
    String tempPath, {
    required String marketName,
    required InstallCancelToken cancelToken,
  }) async {
    final extractDir = await Directory.systemTemp.createTemp('server_install_');
    try {
      _throwIfCancelled(cancelToken);
      await _extractZip(tempPath, extractDir.path);
      final serverJson = File(p.join(extractDir.path, 'server.json'));
      if (!serverJson.existsSync()) {
        throw Exception('server 包根目录缺少 server.json');
      }
      final decoded = jsonDecode(await serverJson.readAsString());
      if (decoded is! Map) {
        throw Exception('server.json 不是有效对象');
      }
      final servicesRoot = await PluginPaths.servicesRoot();
      final plan = ServerPackageResolver.resolve(
        manifest: decoded,
        fileName: p.basename(entry.url),
        servicesRootPath: servicesRoot.path,
        marketEntry: entry,
      );
      await installServerPackagePlan(
        plan: plan,
        sourceDir: extractDir,
        marketName: marketName,
        cancelToken: cancelToken,
      );
    } finally {
      await _safeDeleteDir(extractDir.path);
    }
  }

  /// 统一安装/更新服务包。
  ///
  /// 市场和手动导入都先生成 [ServerPackagePlan]，避免两套身份推断。
  Future<void> installServerPackagePlan({
    required ServerPackagePlan plan,
    required Directory sourceDir,
    required String marketName,
    InstallCancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? InstallCancelToken();
    _throwIfCancelled(token);
    final servicesRoot = await PluginPaths.servicesRoot();
    if (!PluginPaths.isWithin(servicesRoot, plan.packageRoot) ||
        p.equals(plan.packageRoot, servicesRoot.path)) {
      throw FormatException('服务包根目录越界：${plan.packageRoot}');
    }

    final packageRoot = Directory(plan.packageRoot);
    final staging = Directory(
      p.join(
        servicesRoot.path,
        '.server-stage-${plan.pluginId}-'
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final existingConfig = ServiceManager.instance.find(plan.serviceId);
    final existingRegistry = findInstalled(plan.pluginId);

    try {
      await staging.create(recursive: true);
      await _copyDirContents(sourceDir, staging);
      _throwIfCancelled(token);

      await ServiceManager.instance.stop(plan.serviceId);
      final swap = await PluginPaths.swapInDirectory(
        staging: staging,
        finalDir: packageRoot,
        allowedRoot: servicesRoot,
        tag: 'server-${plan.pluginId}',
      );
      try {
        _throwIfCancelled(token);
        final cwd = plan.workDir.isEmpty
            ? packageRoot.path
            : p.join(packageRoot.path, plan.workDir);
        final config = ServiceConfig(
          id: plan.serviceId,
          name: plan.serviceName,
          port: existingConfig?.port ?? plan.port,
          runtime: plan.runtime,
          args: [plan.entry],
          cwd: cwd,
          autostart: existingConfig?.autostart ?? plan.autoStart,
          keepForeground: existingConfig?.keepForeground ?? false,
          env: existingConfig?.env ?? const {},
          maxRestart: existingConfig?.maxRestart ?? 1,
          executable: existingConfig?.executable,
          healthType: existingConfig?.healthType ?? plan.healthType,
          healthPath: existingConfig?.healthPath ?? plan.healthPath,
          pidFile: existingConfig?.pidFile,
          packageRoot: packageRoot.path,
          packagePluginId: plan.pluginId,
          packageVersion: plan.manifestVersion,
          packageIdentitySource: plan.identitySource,
        );
        final registryVersion = plan.registryVersion.isNotEmpty
            ? plan.registryVersion
            : existingRegistry?.version ?? '0.0.0';
        final installed = InstalledPlugin(
          id: plan.pluginId,
          version: registryVersion,
          source: marketName,
          installPath: packageRoot.path,
          enabled: true,
          pinned: false,
          installedAtMs: DateTime.now().millisecondsSinceEpoch,
          type: 'server',
          desc: plan.description,
          changelog: plan.marketEntry?.changelog,
          icon: _resolvedIconOrNull(plan.marketEntry),
          extras: {
            'serviceId': plan.serviceId,
            'packageRoot': packageRoot.path,
            'manifestVersion': plan.manifestVersion,
            'identitySource': plan.identitySource,
            'linkedToMarket': plan.linkedToMarket,
          },
        );

        await ServiceManager.instance.addOrUpdate(config);
        await register(installed);
        await swap.commit();
      } catch (_) {
        if (existingConfig == null) {
          if (ServiceManager.instance.find(plan.serviceId) != null) {
            await ServiceManager.instance.remove(plan.serviceId);
          }
        } else {
          await ServiceManager.instance.addOrUpdate(existingConfig);
        }
        if (existingRegistry == null) {
          await unregister(plan.pluginId);
        } else {
          await register(existingRegistry);
        }
        await swap.rollback();
        rethrow;
      }
    } finally {
      await _safeDeleteDir(staging.path);
    }
  }

  String? _resolvedIconOrNull(MarketEntry? entry) {
    return entry == null ? null : _resolvedIcon(entry);
  }

  // ============================================================
  // 内部工具
  // ============================================================

  void _throwIfCancelled(InstallCancelToken token) {
    if (token.isCancelled) throw _CancelledException();
  }

  Future<void> _commitStagedDirectory({
    required Directory root,
    required Directory staging,
    required String finalDir,
    required String tag,
    required Future<void> Function() writeRegistry,
    required bool Function() isCancelled,
    void Function()? onRegistering,
  }) async {
    if (isCancelled()) throw _CancelledException();
    final swap = await PluginPaths.swapInDirectory(
      staging: staging,
      finalDir: Directory(finalDir),
      allowedRoot: root,
      tag: tag,
    );
    try {
      if (isCancelled()) throw _CancelledException();
      onRegistering?.call();
      await writeRegistry();
      await swap.commit();
    } catch (_) {
      await swap.rollback();
      rethrow;
    }
  }

  /// H1：Zip Slip 防护——entry 名解析后的绝对路径必须落在 targetDir 内。
  /// 合法包（市场包全部合法）行为完全不变；`../` 逃逸 entry 被跳过。
  bool _isSafeArchivePath(String targetDir, String entryName) {
    try {
      final normalizedTarget = p.normalize(p.absolute(targetDir));
      final normalizedOut = p.normalize(
        p.absolute(p.join(targetDir, entryName)),
      );
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

    final contentLength =
        int.tryParse(
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

  Future<void> _deleteInstalledPath(String path) async {
    if (path.isEmpty) return;
    final pluginRoot = await PluginPaths.root();
    final serviceRoot = await PluginPaths.servicesRoot();
    if (!PluginPaths.isWithin(pluginRoot, path) &&
        !PluginPaths.isWithin(serviceRoot, path)) {
      debugPrint('[InstallManager] 拒绝删除越界目录: $path');
      return;
    }
    if (p.equals(path, pluginRoot.path) || p.equals(path, serviceRoot.path)) {
      debugPrint('[InstallManager] 拒绝删除根目录: $path');
      return;
    }
    await _safeDeleteDir(path);
  }

  String _applyGithubProxyIfNeeded(String url, MarketEntry entry) {
    // 条目来自已启用市场时，空 proxy 是明确的“直连”配置，
    // 不能再回退到第一个市场的代理。
    final proxy = entry.marketId.isNotEmpty
        ? entry.proxy
        : (MarketManager.instance.getSources().isEmpty
              ? ''
              : MarketManager.instance.getSources().first.proxy);
    if (proxy.isEmpty) return url;
    if (url.contains('github.com') ||
        url.contains('raw.githubusercontent.com')) {
      return '$proxy$url';
    }
    return url;
  }

  String? _resolvedIcon(MarketEntry entry) {
    final icon = entry.icon;
    if (icon == null || icon.isEmpty) return null;
    if (icon.startsWith('http://') || icon.startsWith('https://')) {
      return icon;
    }
    if (entry.indexBaseUrl.isEmpty) return icon;
    return MarketManager.resolveUrl(icon, entry.indexBaseUrl);
  }
}

class _CancelledException implements Exception {
  @override
  String toString() => '已取消';
}

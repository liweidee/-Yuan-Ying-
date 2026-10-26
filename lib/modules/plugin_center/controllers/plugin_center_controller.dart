// lib/modules/plugin_center/controllers/plugin_center_controller.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';

import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/models/market_source.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/market_manager.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';

enum MarketFilter { all, updatable, installed, notInstalled }

enum MarketCategory { all, env, app }

/// 市场卡片按钮的安装状态（同步派生，单一数据源 = installedList）
enum MarketInstallState {
  /// 未安装
  notInstalled,

  /// 已安装且版本一致
  installed,

  /// 已安装但版本落后，可更新
  updatable,

  /// 当前平台 / ABI 不支持，不可安装
  unsupported,
}

class PluginCenterController extends GetxController {
  final RxList<MarketEntry> marketEntries = <MarketEntry>[].obs;
  final RxBool marketLoading = false.obs;
  final RxString marketError = ''.obs;
  final Rx<MarketFilter> marketFilter = MarketFilter.all.obs;
  final Rx<MarketCategory> marketCategory = MarketCategory.all.obs;
  final RxString marketSearch = ''.obs;

  final RxList<InstalledPlugin> installedList = <InstalledPlugin>[].obs;

  /// 安装变更版本号。
  /// 任何会改变「已装注册表」的动作（安装/更新/卸载/启用/停用/回填）
  /// 都必须调用 reloadInstalled()，此处自增，市场卡片据此重建。
  final RxInt installRevision = 0.obs;

  final RxString pluginSearch = ''.obs;

  /// 不在服务 Tab 展示的内部服务 ID（由专用页面管理）
  ///
  /// - `svc-local-php-t4`：PHP-T4 本地服务，由「设置 → PHP-T4 本地服务」页
  ///   管理；不展示在服务 Tab，避免参数被误编辑（args/port 由代码生成）。
  ///   关闭/卸载 php 插件时，`_stopDependentServices` 仍会停掉它。
  static const Set<String> _hiddenServiceIds = {
    'svc-local-php-t4',
  };

  final RxList<String> serviceIds = <String>[].obs;

  final RxString serviceSearch = ''.obs;

  final RxString serviceTabFilterRuntime = ''.obs;
  final RxString serviceTabFilterLabel = ''.obs;

  void Function()? onJumpToServiceTab;

  @override
  void onInit() {
    super.onInit();
    reloadInstalled();
    reloadServices();
    ServiceManager.instance.onChange.listen((_) => reloadServices());
  }

  Future<void> loadMarket({bool forceRefresh = false}) async {
    marketLoading.value = true;
    marketError.value = '';
    try {
      final entries = await MarketManager.instance
          .fetchAll(forceRefresh: forceRefresh);
      marketEntries.assignAll(entries);
      await InstallManager.instance.backfillFromMarket(entries);
      reloadInstalled();
    } catch (e) {
      marketError.value = e.toString();
    } finally {
      marketLoading.value = false;
    }
  }

  /// 市场卡片同步判定安装状态。
  /// 以 installedList（Hive 注册表）为唯一依据，不查系统包、不查文件系统，
  /// 保证 build 期 O(1) 且与注册表严格一致。
  MarketInstallState installStateOf(MarketEntry entry) {
    if (!entry.supportsCurrentPlatform || !entry.supportsCurrentAbi) {
      return MarketInstallState.unsupported;
    }
    final reg = _findInstalledInMemory(entry.id);
    if (reg == null) return MarketInstallState.notInstalled;
    if (reg.version != entry.version) return MarketInstallState.updatable;
    return MarketInstallState.installed;
  }

  InstalledPlugin? _findInstalledInMemory(String id) {
    for (final p in installedList) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<MarketEntry> get filteredEntries {
    final entries = marketEntries;
    final filter = marketFilter.value;
    final category = marketCategory.value;
    final query = marketSearch.value.trim().toLowerCase();

    return entries.where((e) {
      if (category == MarketCategory.env && e.category != 'env') return false;
      if (category == MarketCategory.app && e.category != 'app') return false;

      if (!e.supportsCurrentPlatform) return false;
      if (!e.supportsCurrentAbi) return false;

      if (query.isNotEmpty) {
        final hay = '${e.name} ${e.id} ${e.author ?? ''}'.toLowerCase();
        if (!hay.contains(query)) return false;
      }

      final reg = _findInstalledInMemory(e.id);
      switch (filter) {
        case MarketFilter.all:
          return true;
        case MarketFilter.installed:
          return reg != null;
        case MarketFilter.notInstalled:
          return reg == null;
        case MarketFilter.updatable:
          return reg != null && reg.version != e.version;
      }
    }).toList();
  }

  int get installedCount => installedList.length;

  int get updatableCount {
    int n = 0;
    for (final e in marketEntries) {
      final reg = _findInstalledInMemory(e.id);
      if (reg != null && reg.version != e.version) n++;
    }
    return n;
  }

  String getCurrentIndexBaseUrl() {
    final sources = MarketManager.instance.getSources();
    if (sources.isEmpty) return '';
    return sources.first.url;
  }

  String getCurrentMarketName() {
    final sources = MarketManager.instance.getSources();
    if (sources.isEmpty) return '未知市场';
    return sources.first.name;
  }

  void reloadInstalled() {
    final list = InstallManager.instance.getAllInstalled();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.pinned && b.pinned) {
        final aTime = a.pinnedAtMs ?? 0;
        final bTime = b.pinnedAtMs ?? 0;
        return bTime.compareTo(aTime);
      }
      return b.installedAtMs.compareTo(a.installedAtMs);
    });
    installedList.assignAll(list);
    installRevision.value++;
  }

  List<InstalledPlugin> get filteredPlugins {
    final query = pluginSearch.value.trim().toLowerCase();
    return installedList.where((p) {
      if (p.type == 'live' || p.type == 'source' || p.type == 'server') {
        return false;
      }
      final plat = p.extras['platform'];
      if (plat is String && plat.isNotEmpty) {
        final current = Platform.isWindows ? 'win32' : 'android';
        if (plat != current) return false;
      }
      if (query.isNotEmpty) {
        final hay = '${p.id} ${p.desc ?? ''}'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> toggleEnabled(String id, bool enabled) async {
    await InstallManager.instance.setEnabled(id, enabled);

    if (!enabled) {
      // ===== 禁用 nodejs-win 时主动停 Node 进程 =====
      // 猫影视的 Node 进程由 NodeJSService 自己 spawn，不在 ServiceManager
      // 管理下，必须单独处理。仅桌面端生效。
      if (id == 'nodejs-win') {
        try {
          await NodeJSService.instance.stopForPluginDisabled();
        } catch (e) {
          debugPrint('[PluginCenterController] stop nodejs failed: $e');
        }
      }

      // ===== 通用：停掉所有依赖此运行时的服务 =====
      // 覆盖 php-win / php / python-win / qjs 等所有被 ServiceManager 管理的服务
      // （含隐藏的 svc-local-php-t4）。
      await _stopDependentServices(id);
    }

    reloadInstalled();
  }

  /// 停掉所有 `runtime == runtimeId` 的服务
  ///
  /// 关闭插件时调用，保证「插件状态」与「依赖它的服务」严格一致：
  ///   - 关闭 php-win / php → 停 php-t4、drpys（php）等所有 php 服务
  ///   - 关闭 python-win / python → 停 PyT4 服务
  ///   - 关闭 nodejs-win / nodejs → 停 drpys（node）、danmu-api 等服务
  ///
  /// 注意：**不判断服务状态，无条件 stop**。
  /// 原因：`ServiceStatus.error` 可能表示「sigkill 失败但进程还活着」，
  ///      条件 stop 会漏掉这类残留进程，导致关闭插件后进程仍占端口。
  ///      `ServiceManager.stop()` 对 `stopped` 状态是幂等的（立即 return），
  ///      无条件调用无额外开销。
  Future<void> _stopDependentServices(String runtimeId) async {
    final services = ServiceManager.instance.getAll();
    for (final svc in services) {
      if (svc.runtime != runtimeId) continue;
      try {
        await ServiceManager.instance.stop(svc.id);
        debugPrint(
          '[PluginCenterController] stopped ${svc.id} '
          '(runtime=$runtimeId) due to plugin disabled',
        );
      } catch (e) {
        debugPrint('[PluginCenterController] stop ${svc.id} failed: $e');
      }
    }
  }

  Future<void> togglePinned(String id, bool pinned) async {
    await InstallManager.instance.setPinned(id, pinned);
    reloadInstalled();
  }

  Future<void> uninstall(InstalledPlugin plugin) async {
    await InstallManager.instance.uninstall(plugin);
    reloadInstalled();
  }

  void reloadServices() {
    serviceIds.assignAll(ServiceManager.instance.getAll().map((e) => e.id));
  }

  int get serviceCount =>
    serviceIds.where((id) => !_hiddenServiceIds.contains(id)).length;

  int get runningServiceCount {
    int n = 0;
    for (final id in serviceIds) {
      if (_hiddenServiceIds.contains(id)) continue;
      if (ServiceManager.instance.getStatus(id) == ServiceStatus.running) {
        n++;
      }
    }
    return n;
  }

  List<String> get filteredServiceIds {
    final runtime = serviceTabFilterRuntime.value;
    final query = serviceSearch.value.trim().toLowerCase();

    return serviceIds.where((id) {
      // 隐藏内部服务（如 PHP-T4，由专用页面管理）
      if (_hiddenServiceIds.contains(id)) return false;

      final cfg = ServiceManager.instance.find(id);
      if (cfg == null) return false;

      final isWinRuntime = cfg.runtime.endsWith('-win');
      if (Platform.isWindows && !isWinRuntime) {
        if (cfg.runtime != 'custom') return false;
      }
      if (Platform.isAndroid && isWinRuntime) return false;

      if (runtime.isNotEmpty && cfg.runtime != runtime) return false;
      if (query.isNotEmpty) {
        final hay = '${cfg.name} ${cfg.runtime} ${cfg.port ?? ''}'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  void jumpToServiceTabFiltered(String runtimeId, String label) {
    serviceTabFilterRuntime.value = runtimeId;
    serviceTabFilterLabel.value = label;
    onJumpToServiceTab?.call();
  }

  void clearServiceTabFilter() {
    serviceTabFilterRuntime.value = '';
    serviceTabFilterLabel.value = '';
  }

  List<MarketSource> getSources() => MarketManager.instance.getSources();

  Future<void> saveSources(List<MarketSource> sources) async {
    await MarketManager.instance.saveSources(sources);
  }
}
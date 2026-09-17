import 'package:get/get.dart';

import '../models/smb_entry.dart';
import '../services/smb_service.dart';
import 'smb_server_controller.dart';

class SmbFileController extends GetxController {
  final serverCtl = Get.find<SmbServerController>();

  /// 当前共享名（空 = 显示共享列表）
  final RxString currentShare = ''.obs;

  /// 当前共享内的路径（'/' 或子目录）
  final RxString currentPath = '/'.obs;

  final RxList<SmbEntry> entries = <SmbEntry>[].obs;

  /// 导航级 loading：进入新目录且无缓存时为 true，页面显示全屏圆圈
  final RxBool isNavigating = false.obs;

  final RxString error = ''.obs;

  /// 目录缓存：key = "share|path"，value = 该目录的条目列表
  /// 用于面包屑/返回上级时秒开
  final Map<String, List<SmbEntry>> _dirCache = {};

  String _cacheKey(String share, String path) => '$share|$path';

  bool get atShareList => currentShare.value.isEmpty;

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  List<String> get breadcrumbs {
    if (atShareList) return const ['共享列表'];
    final parts = currentPath.value
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return [currentShare.value, if (parts.isEmpty) '根目录', ...parts];
  }

  bool get canGoUp => !atShareList;

  // ==================================================================
  // 刷新（清缓存 + 强制重新加载）
  // ==================================================================
  Future<void> refresh() async {
    if (atShareList) {
      await _loadShares();
    } else {
      // 清掉当前目录的缓存，强制重新拉取
      _dirCache.remove(_cacheKey(currentShare.value, currentPath.value));
      await _loadDirectory(currentPath.value, useCache: false);
    }
  }

  Future<void> _loadShares() async {
    final server = serverCtl.current;
    if (server == null) {
      error.value = '未选择服务器';
      return;
    }
    isNavigating.value = true;
    error.value = '';
    try {
      final list = await SmbService.instance.listShares(server);
      entries.value = list;
    } catch (e) {
      error.value = '$e';
    } finally {
      isNavigating.value = false;
    }
  }

  /// 加载目录
  /// - [useCache] = true：若有缓存，先显示缓存并后台刷新（不显示 loading）
  /// - [useCache] = false：强制重新拉取，显示全屏 loading
  Future<void> _loadDirectory(
    String path, {
    bool useCache = true,
  }) async {
    final server = serverCtl.current;
    if (server == null || atShareList) return;

    final cacheKey = _cacheKey(currentShare.value, path);

    // 有缓存 → 直接显示，不显示 loading
    if (useCache && _dirCache.containsKey(cacheKey)) {
      entries.value = _dirCache[cacheKey]!;
      currentPath.value = path;
      error.value = '';
      // 后台静默刷新（不打断用户）
      _backgroundRefresh(server, cacheKey, path);
      return;
    }

    // 无缓存 → 全屏 loading
    isNavigating.value = true;
    error.value = '';
    try {
      final list = await SmbService.instance.listDirectory(
        server,
        currentShare.value,
        path,
      );
      _dirCache[cacheKey] = list;
      entries.value = list;
      currentPath.value = path;
    } catch (e) {
      error.value = '$e';
    } finally {
      isNavigating.value = false;
    }
  }

  /// 后台静默刷新（不显示 loading，失败也不报错）
  Future<void> _backgroundRefresh(
    dynamic server,
    String cacheKey,
    String path,
  ) async {
    try {
      final list = await SmbService.instance.listDirectory(
        server,
        currentShare.value,
        path,
      );
      _dirCache[cacheKey] = list;
      // 只有当前仍展示这个目录时才更新 UI
      if (!atShareList && currentPath.value == path) {
        entries.value = list;
      }
    } catch (_) {
      // 静默失败，保留原缓存
    }
  }

  // ==================================================================
  // 导航
  // ==================================================================
  Future<void> openEntry(SmbEntry entry) async {
    if (entry.isShare) {
      currentShare.value = entry.path;
      currentPath.value = '/';
      await _loadDirectory('/');
      return;
    }
    if (entry.isDirectory) {
      await _loadDirectory(entry.path);
    }
  }

  Future<void> goUp() async {
    if (atShareList) return;

    // 从共享根返回共享列表
    if (currentPath.value == '/' || currentPath.value.isEmpty) {
      currentShare.value = '';
      currentPath.value = '/';
      await _loadShares();
      return;
    }

    // 从子目录返回父目录（默认走缓存，秒开）
    final cleaned = currentPath.value.endsWith('/')
        ? currentPath.value.substring(0, currentPath.value.length - 1)
        : currentPath.value;
    final idx = cleaned.lastIndexOf('/');
    await _loadDirectory(idx <= 0 ? '/' : cleaned.substring(0, idx));
  }

  Future<void> jumpTo(int crumbIndex) async {
    if (crumbIndex == 0) {
      currentShare.value = '';
      currentPath.value = '/';
      await _loadShares();
      return;
    }
    if (crumbIndex == 1) {
      await _loadDirectory('/');
      return;
    }
    final parts = currentPath.value
        .split('/')
        .where((s) => s.isNotEmpty)
        .take(crumbIndex - 1)
        .toList();
    await _loadDirectory('/${parts.join('/')}');
  }
}
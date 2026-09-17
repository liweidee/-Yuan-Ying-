import 'package:get/get.dart';

import '../models/ftp_entry.dart';
import '../services/ftp_service.dart';
import 'ftp_server_controller.dart';

class FtpFileController extends GetxController {
  final serverCtl = Get.find<FtpServerController>();

  final RxString currentPath = '/'.obs;
  final RxList<FtpEntry> entries = <FtpEntry>[].obs;

  /// 导航级 loading：进入新目录且无缓存时为 true，页面显示全屏圆圈
  final RxBool isNavigating = false.obs;

  final RxString error = ''.obs;

  /// 目录缓存：key = path，value = 该目录的条目列表
  final Map<String, List<FtpEntry>> _dirCache = {};

  @override
  void onInit() {
    super.onInit();
    final server = serverCtl.current;
    final startPath = server?.initialPath ?? '/';
    _loadDirectory(startPath);
  }

  List<String> get breadcrumbs {
    final path = currentPath.value;
    if (path == '/' || path.isEmpty) return const ['根目录'];
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return ['根目录', ...parts];
  }

  bool get canGoUp => currentPath.value != '/' && currentPath.value.isNotEmpty;

  // ==================================================================
  // 刷新（清当前目录缓存 + 强制重新加载）
  // ==================================================================
  Future<void> refresh() async {
    _dirCache.remove(currentPath.value);
    await _loadDirectory(currentPath.value, useCache: false);
  }

  /// 加载目录
  /// - [useCache] = true：若有缓存，先显示缓存并后台刷新（不显示 loading）
  /// - [useCache] = false：强制重新拉取，显示全屏 loading
  Future<void> _loadDirectory(
    String path, {
    bool useCache = true,
  }) async {
    final server = serverCtl.current;
    if (server == null) {
      error.value = '未选择服务器';
      return;
    }

    // 有缓存 → 立即显示，不显示 loading
    if (useCache && _dirCache.containsKey(path)) {
      entries.value = _dirCache[path]!;
      currentPath.value = path;
      error.value = '';
      // 后台静默刷新
      _backgroundRefresh(server, path);
      return;
    }

    // 无缓存 → 全屏 loading
    isNavigating.value = true;
    error.value = '';
    try {
      final list = await FtpService.instance.listDirectory(server, path);
      _dirCache[path] = list;
      entries.value = list;
      currentPath.value = path;
    } catch (e) {
      error.value = '$e';
    } finally {
      isNavigating.value = false;
    }
  }

  /// 后台静默刷新（不显示 loading，失败不报错）
  Future<void> _backgroundRefresh(dynamic server, String path) async {
    try {
      final list = await FtpService.instance.listDirectory(server, path);
      _dirCache[path] = list;
      // 只有当前仍展示这个目录时才更新 UI
      if (currentPath.value == path) {
        entries.value = list;
      }
    } catch (_) {
      // 静默失败，保留原缓存
    }
  }

  // ==================================================================
  // 导航
  // ==================================================================
  Future<void> openDirectory(FtpEntry entry) async {
    if (!entry.isDirectory) return;
    await _loadDirectory(entry.path);
  }

  Future<void> goUp() async {
    final path = currentPath.value;
    if (path == '/' || path.isEmpty) return;
    final cleaned =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idx = cleaned.lastIndexOf('/');
    await _loadDirectory(idx <= 0 ? '/' : cleaned.substring(0, idx));
  }

  Future<void> jumpTo(int crumbIndex) async {
    if (crumbIndex == 0) {
      await _loadDirectory('/');
      return;
    }
    final parts = currentPath.value
        .split('/')
        .where((s) => s.isNotEmpty)
        .take(crumbIndex)
        .toList();
    await _loadDirectory('/${parts.join('/')}');
  }
}
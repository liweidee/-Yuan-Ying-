// lib/modules/local_file/controllers/local_file_controller.dart
import 'dart:io';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/local_file/models/file_sort_type.dart';
import 'package:yuanying/modules/local_file/models/scan_path.dart';
import 'package:yuanying/modules/local_file/models/video_file.dart';
import 'package:yuanying/modules/local_file/services/file_scanner_service.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';        // 新增
import 'package:yuanying/utils/permission_handler.dart';    // 新增

/// 文件夹数据（用于混合列表）
class FolderItemData {
  final String path;
  final String name;
  final bool isFolder;
  const FolderItemData({required this.path, required this.name, this.isFolder = true});
}

/// 面包屑节点
class BreadcrumbItem {
  final String name;
  final String path;
  const BreadcrumbItem({required this.name, required this.path});
}

class LocalFileController extends GetxController {
  final FileScannerService _scanner = FileScannerService();

  final RxList<ScanPath> scanPaths = <ScanPath>[].obs;
  final RxList<VideoFile> videoFiles = <VideoFile>[].obs;
  final RxList<VideoFile> filteredFiles = <VideoFile>[].obs;

  final RxBool isLoading = false.obs;
  final RxBool isScanning = false.obs;
  final RxString searchKeyword = ''.obs;

  final Rx<FileSortType> sortBy = FileSortType.name.obs;
  final Rx<SortOrder> sortOrder = SortOrder.ascending.obs;
  final Rx<ViewMode> viewMode = ViewMode.list.obs;
  final RxBool isFolderMode = false.obs;

  final RxString selectedPathId = ''.obs;
  final RxString scanStatus = ''.obs;

  final RxString currentFolderPath = ''.obs;
  final RxList<dynamic> _mixedList = <dynamic>[].obs;

  // ===== Getters =====
  int get totalVideoCount => videoFiles.length;
  int get totalSize => videoFiles.fold<int>(0, (sum, f) => sum + f.size);
  String get totalSizeFormatted => _formatSize(totalSize);
  int get enabledPathCount => scanPaths.where((p) => p.enabled).length;
  List<dynamic> get mixedList => _mixedList;

  List<BreadcrumbItem> get breadcrumbs {
    if (currentFolderPath.value.isEmpty) return [];
    final rootPath = scanPaths.isNotEmpty
        ? scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first).path
        : '';
    if (rootPath.isEmpty || currentFolderPath.value == rootPath) return [];
    String relativePath = currentFolderPath.value;
    if (relativePath.startsWith(rootPath)) {
      var subPath = relativePath.substring(rootPath.length);
      while (subPath.startsWith(Platform.pathSeparator)) subPath = subPath.substring(1);
      if (subPath.isEmpty) return [];
      final parts = subPath.split(Platform.pathSeparator);
      final items = <BreadcrumbItem>[];
      String accumulated = rootPath;
      for (final part in parts) {
        if (part.isEmpty) continue;
        accumulated += Platform.pathSeparator + part;
        items.add(BreadcrumbItem(name: part, path: accumulated));
      }
      return items;
    }
    return [];
  }

  bool get isAtRootPath {
    if (currentFolderPath.value.isEmpty) return true;
    final rootPath = scanPaths.isNotEmpty
        ? scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first).path
        : '';
    return rootPath.isEmpty || currentFolderPath.value == rootPath;
  }

  // ===== 生命周期 =====
  @override
  void onInit() {
    super.onInit();
    _loadScanPaths();
    if (scanPaths.isNotEmpty) {
      final first = scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
      currentFolderPath.value = first.path;
      _ensurePermissionAndScan(first.path); // 替换原 scanDirectory
    }
  }

  // ===== 权限 + 扫描封装 =====
  Future<void> _ensurePermissionAndScan(String path) async {
    if (PlatformUtils.isMobile) {
      final status = await Permission.storage.request();
      if (status.isDenied) {
        SmartDialog.showToast('无法扫描，存储权限被拒绝');
        return;
      }
      if (status.isPermanentlyDenied) {
        SmartDialog.showToast('请在系统设置中授予存储权限后重试');
        await openAppSettings();
        return;
      }
      if (!status.isGranted) {
        SmartDialog.showToast('权限不足，无法扫描');
        return;
      }
    }
    await scanDirectory(path);
  }

  // ===== 路径管理 =====
  void _loadScanPaths() {
    final data = StorageManager.getSetting<List<dynamic>>(SettingBoxKey.localFileScanPaths);
    if (data != null && data.isNotEmpty) {
      final paths = data.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return ScanPath.fromJson(map);
      }).toList();
      scanPaths.value = paths;
    }
  }

  void _saveScanPaths() {
    final data = scanPaths.map((e) => e.toJson()).toList();
    StorageManager.setSetting(SettingBoxKey.localFileScanPaths, data);
  }

  void addScanPath(String path, {String? name}) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final scanPath = ScanPath(
      id: id,
      path: path,
      name: name ?? FileScannerService.getFileName(path),
      enabled: true,
    );
    scanPaths.add(scanPath);
    _saveScanPaths();
    currentFolderPath.value = path;
    _ensurePermissionAndScan(path); // 添加路径后扫描
  }

  void removeScanPath(String id) {
    scanPaths.removeWhere((p) => p.id == id);
    _saveScanPaths();
    if (selectedPathId.value == id) selectedPathId.value = '';
  }

  void toggleScanPath(String id) {
    final index = scanPaths.indexWhere((p) => p.id == id);
    if (index != -1) {
      final path = scanPaths[index];
      scanPaths[index] = path.copyWith(enabled: !path.enabled);
      _saveScanPaths();
    }
  }

  void clearAllPaths() {
    scanPaths.clear();
    videoFiles.clear();
    filteredFiles.clear();
    _mixedList.clear();
    currentFolderPath.value = '';
    _saveScanPaths();
  }

  // ===== 文件夹导航 =====
  void enterFolder(String folderPath) {
    if (folderPath.isEmpty) return;
    currentFolderPath.value = folderPath;
    _loadFolderContent(folderPath);
  }

  void goToPath(String path) {
    if (path.isEmpty || path == currentFolderPath.value) return;
    currentFolderPath.value = path;
    _loadFolderContent(path);
  }

  void goToParent() {
    if (currentFolderPath.value.isEmpty) return;
    final parts = currentFolderPath.value.split(Platform.pathSeparator);
    if (parts.length <= 1) return;
    parts.removeLast();
    final parentPath = parts.join(Platform.pathSeparator);
    final rootPath = scanPaths.isNotEmpty
        ? scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first).path
        : '';
    if (parentPath.isEmpty || parentPath == '/' || parentPath == rootPath) {
      currentFolderPath.value = rootPath;
      _loadFolderContent(rootPath);
      return;
    }
    currentFolderPath.value = parentPath;
    _loadFolderContent(parentPath);
  }

  Future<void> _loadFolderContent(String path) async {
    if (path.isEmpty || isLoading.value) return;
    isLoading.value = true;
    try {
      final subDirs = await _scanner.getSubDirectories(path);
      final files = await _scanner.scanDirectory(path, recursive: false);
      final mixedList = <dynamic>[];
      for (final dir in subDirs) {
        mixedList.add(FolderItemData(
          path: dir,
          name: dir.split(Platform.pathSeparator).last,
        ));
      }
      for (final file in files) mixedList.add(file);
      _mixedList.value = mixedList;
      videoFiles.value = files;
      _applyFilters();
    } catch (e) {
      SmartDialog.showToast('加载文件夹内容失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ===== 扫描（添加权限前置检查） =====
  Future<void> scanDirectory(String path, {bool silent = false}) async {
    if (path.isEmpty || isScanning.value) return;

    // 权限检查（防御）
    if (PlatformUtils.isMobile) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        SmartDialog.showToast('没有存储权限，请在设置中授予');
        return;
      }
    }

    isScanning.value = true;
    if (!silent) isLoading.value = true;

    try {
      if (isFolderMode.value) {
        await _loadFolderContent(path);
      } else {
        final files = await _scanner.scanDirectory(path);
        videoFiles.value = files;
        _applyFilters();
        _updatePathScanInfo(path, files.length, files.fold<int>(0, (sum, f) => sum + f.size));
      }
      scanStatus.value = '扫描完成，发现 ${videoFiles.length} 个视频';
      SmartDialog.showToast('扫描完成，发现 ${videoFiles.length} 个视频');
    } catch (e) {
      scanStatus.value = '扫描失败: $e';
      SmartDialog.showToast('扫描失败: $e');
    } finally {
      isScanning.value = false;
      if (!silent) isLoading.value = false;
    }
  }

  void _updatePathScanInfo(String path, int count, int size) {
    final index = scanPaths.indexWhere((p) => p.path == path);
    if (index != -1) {
      final p = scanPaths[index];
      scanPaths[index] = p.copyWith(
        lastScanTime: DateTime.now(),
        videoCount: count,
        totalSize: size,
      );
      _saveScanPaths();
    }
  }

  Future<void> scanAllPaths() async {
    if (isScanning.value) return;
    isScanning.value = true;
    isLoading.value = true;

    int totalCount = 0;
    for (final path in scanPaths.where((p) => p.enabled)) {
      try {
        final files = await _scanner.scanDirectory(path.path);
        totalCount += files.length;
        _updatePathScanInfo(
          path.path,
          files.length,
          files.fold<int>(0, (int sum, VideoFile f) => sum + f.size),
        );
      } catch (_) {}
    }
    if (scanPaths.isNotEmpty) {
      final first = scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
      currentFolderPath.value = first.path;
      await scanDirectory(first.path);
    }

    isScanning.value = false;
    isLoading.value = false;
    scanStatus.value = '全部扫描完成，共发现 $totalCount 个视频';
    SmartDialog.showToast('全部扫描完成，共发现 $totalCount 个视频');
  }

  // ===== 搜索 & 排序 & 过滤 =====
  void updateSearch(String keyword) {
    searchKeyword.value = keyword;
    _applyFilters();
  }

  void setSortBy(FileSortType type) {
    sortBy.value = type;
    _applyFilters();
  }

  void toggleSortOrder() {
    sortOrder.value = sortOrder.value == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    _applyFilters();
  }

  void toggleViewMode() {
    viewMode.value = viewMode.value == ViewMode.list ? ViewMode.grid : ViewMode.list;
  }

  void toggleFolderMode() {
    isFolderMode.value = !isFolderMode.value;
    if (isFolderMode.value) {
      if (currentFolderPath.value.isEmpty && scanPaths.isNotEmpty) {
        final first = scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
        currentFolderPath.value = first.path;
      }
      if (currentFolderPath.value.isNotEmpty) {
        _loadFolderContent(currentFolderPath.value);
      }
    } else {
      if (scanPaths.isNotEmpty) {
        final first = scanPaths.firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
        currentFolderPath.value = first.path;
        _ensurePermissionAndScan(first.path);
      }
    }
  }

  void _applyFilters() {
    var list = List<VideoFile>.from(videoFiles);
    if (searchKeyword.value.isNotEmpty) {
      final keyword = searchKeyword.value.toLowerCase();
      list = list.where((f) => f.name.toLowerCase().contains(keyword)).toList();
    }
    list.sort((a, b) {
      int result;
      switch (sortBy.value) {
        case FileSortType.name:
          result = a.name.compareTo(b.name);
          break;
        case FileSortType.size:
          result = a.size.compareTo(b.size);
          break;
        case FileSortType.modified:
          result = a.modifiedTime.compareTo(b.modifiedTime);
          break;
      }
      return sortOrder.value == SortOrder.ascending ? result : -result;
    });
    filteredFiles.value = list;
  }

  // ===== 播放 =====
  void playVideo(VideoFile video) {
    final file = File(video.path);
    if (!file.existsSync()) {
      SmartDialog.showToast('文件已移动或删除');
      return;
    }
    Get.toNamed('/detail', arguments: {
      'directUrl': video.path,
      'directTitle': video.name,
      'isPush': true,
    });
  }

  // ===== 工具方法 =====
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String getLastScanTime() {
    final enabled = scanPaths.where((p) => p.enabled && p.lastScanTime != null);
    if (enabled.isEmpty) return '未扫描';
    final latest = enabled.reduce((a, b) =>
        a.lastScanTime!.isAfter(b.lastScanTime!) ? a : b);
    return _formatTime(latest.lastScanTime!);
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}
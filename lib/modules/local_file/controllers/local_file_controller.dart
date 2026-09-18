import 'dart:io';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/local_file/models/file_sort_type.dart';
import 'package:yuanying/modules/local_file/models/scan_path.dart';
import 'package:yuanying/modules/local_file/models/video_file.dart';
import 'package:yuanying/modules/local_file/services/file_scanner_service.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/permission_handler.dart';

/// 文件夹数据（用于混合列表）
class FolderItemData {
  final String path;
  final String name;
  final bool isFolder;
  const FolderItemData({
    required this.path,
    required this.name,
    this.isFolder = true,
  });
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
        ? scanPaths
            .firstWhere((p) => p.enabled, orElse: () => scanPaths.first)
            .path
        : '';
    if (rootPath.isEmpty || currentFolderPath.value == rootPath) return [];
    String relativePath = currentFolderPath.value;
    if (relativePath.startsWith(rootPath)) {
      var subPath = relativePath.substring(rootPath.length);
      while (subPath.startsWith(Platform.pathSeparator)) {
        subPath = subPath.substring(1);
      }
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
        ? scanPaths
            .firstWhere((p) => p.enabled, orElse: () => scanPaths.first)
            .path
        : '';
    return rootPath.isEmpty || currentFolderPath.value == rootPath;
  }

  // ===== 生命周期 =====
  @override
  void onInit() {
    super.onInit();
    if (Platform.isIOS) {
      _initIOSMode();
    } else {
      _loadScanPaths();
      if (scanPaths.isNotEmpty) {
        final first = scanPaths
            .firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
        currentFolderPath.value = first.path;
        _ensurePermissionAndScan(first.path);
      }
    }
  }

  // ===== iOS 模式 =====
  /// iOS 默认进入文件模式：递归扫描 Documents 下所有视频，平铺展示
  Future<void> _initIOSMode() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    currentFolderPath.value = appDocDir.path;
    await _scanIOSRecursive(appDocDir.path);
  }

  /// 供下拉刷新 / AppBar 刷新按钮调用
  Future<void> refreshImportedFolder() async {
    if (!Platform.isIOS) return;
    final appDocDir = await getApplicationDocumentsDirectory();
    currentFolderPath.value = appDocDir.path;
    await _scanIOSRecursive(appDocDir.path);
  }

  /// iOS 递归扫描：遍历指定路径下所有子文件夹，平铺到列表
  Future<void> _scanIOSRecursive(String rootPath) async {
    if (rootPath.isEmpty || isLoading.value) return;
    isLoading.value = true;
    try {
      final files = await _scanner.scanDirectory(rootPath, recursive: true);
      videoFiles.value = files;
      _applyFilters();
    } catch (e) {
      SmartDialog.showToast('扫描失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ===== iOS 文件删除 =====
  /// 删除单个视频文件（仅沙盒内文件，无需权限）
  Future<bool> deleteVideo(VideoFile video) async {
    try {
      final file = File(video.path);
      if (await file.exists()) {
        await file.delete();
      }
      videoFiles.removeWhere((f) => f.path == video.path);
      filteredFiles.removeWhere((f) => f.path == video.path);
      _mixedList.removeWhere(
        (item) => item is VideoFile && item.path == video.path,
      );
      return true;
    } catch (e) {
      SmartDialog.showToast('删除失败: $e');
      return false;
    }
  }

  /// 批量删除
  Future<int> deleteVideos(List<VideoFile> videos) async {
    int count = 0;
    for (final v in videos) {
      if (await deleteVideo(v)) count++;
    }
    return count;
  }

  /// 清空当前列表所有视频
  Future<int> clearAllVideos() async {
    final all = List<VideoFile>.from(videoFiles);
    return deleteVideos(all);
  }

  // ===== 权限 + 扫描封装 =====
  Future<void> _ensurePermissionAndScan(String path) async {
    if (PlatformUtils.isMobile && !Platform.isIOS) {
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
    final data =
        StorageManager.getSetting<List<dynamic>>(SettingBoxKey.localFileScanPaths);
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
    _ensurePermissionAndScan(path);
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
        ? scanPaths
            .firstWhere((p) => p.enabled, orElse: () => scanPaths.first)
            .path
        : '';
    if (parentPath.isEmpty || parentPath == '/' || parentPath == rootPath) {
      currentFolderPath.value = rootPath;
      _loadFolderContent(rootPath);
      return;
    }
    currentFolderPath.value = parentPath;
    _loadFolderContent(parentPath);
  }

  /// 加载单层目录内容（文件夹模式用），与其他平台一致，非递归
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
      for (final file in files) {
        mixedList.add(file);
      }
      _mixedList.value = mixedList;
      videoFiles.value = files;
      _applyFilters();
    } catch (e) {
      SmartDialog.showToast('加载文件夹内容失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ===== 扫描 =====
  Future<void> scanDirectory(String path, {bool silent = false}) async {
    if (path.isEmpty || isScanning.value) return;

    // 权限检查（iOS 跳过）
    if (PlatformUtils.isMobile && !Platform.isIOS) {
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
        _updatePathScanInfo(
          path,
          files.length,
          files.fold<int>(0, (sum, f) => sum + f.size),
        );
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
      final first = scanPaths
          .firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
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
    viewMode.value =
        viewMode.value == ViewMode.list ? ViewMode.grid : ViewMode.list;
  }

  void toggleFolderMode() {
    isFolderMode.value = !isFolderMode.value;
    if (isFolderMode.value) {
      // 进入文件夹模式：直接用当前路径（iOS 是 Documents 根）
      if (currentFolderPath.value.isNotEmpty) {
        _loadFolderContent(currentFolderPath.value);
      }
    } else {
      // 退出文件夹模式
      if (Platform.isIOS) {
        // iOS：回到递归平铺
        if (currentFolderPath.value.isNotEmpty) {
          _scanIOSRecursive(currentFolderPath.value);
        }
      } else {
        if (scanPaths.isNotEmpty) {
          final first = scanPaths
              .firstWhere((p) => p.enabled, orElse: () => scanPaths.first);
          currentFolderPath.value = first.path;
          _ensurePermissionAndScan(first.path);
        }
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

    // 构造 VideoDetail（单文件，不做多剧集）
    final cleanName = _stripMediaExtension(video.name);
    final videoDetail = VideoDetail(
      vodId: 'local_${video.path.hashCode}',
      vodName: cleanName,
      vodPic: '',
      vodContent: '来自本地文件',
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: video.sizeFormatted,
      typeName: '本地文件',
      playSources: [
        PlaySource(
          name: '本地文件',
          episodes: [
            Episode(name: cleanName, url: video.path),
          ],
        ),
      ],
    );

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': video.path,
        'directTitle': cleanName,
        'videoDetail': videoDetail,
        'sourceName': '本地文件',
        'vodPic': '',
        'vodContent': '来自本地文件',
        'vodYear': '',
        'vodActor': '',
        'vodDirector': '',
        'vodRemarks': video.sizeFormatted,
        'isSeries': false,
        'isDirectPushMode': true,
      },
    );
  }

  /// 去除媒体扩展名，用于展示标题
  static String _stripMediaExtension(String name) {
    final idx = name.lastIndexOf('.');
    if (idx <= 0) return name;
    final ext = name.substring(idx + 1).toLowerCase();
    const validExts = {
      'mp4', 'mkv', 'avi', 'webm', 'mov', 'ts', 'm2ts', 'wmv', 'flv',
      'ogv', 'rmvb', 'mpg', 'mpeg', 'vob', '3gp', 'm4v', 'rm',
      'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'ape',
      'dsf', 'dff', 'aiff', 'alac',
    };
    if (!validExts.contains(ext)) return name;
    return name.substring(0, idx);
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
    if (Platform.isIOS) return '沙盒';
    final enabled = scanPaths.where((p) => p.enabled && p.lastScanTime != null);
    if (enabled.isEmpty) return '未扫描';
    final latest = enabled
        .reduce((a, b) => a.lastScanTime!.isAfter(b.lastScanTime!) ? a : b);
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
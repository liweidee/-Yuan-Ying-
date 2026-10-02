// lib/modules/download/models/cache_entry.dart
import 'package:yuanying/utils/cache_manager.dart';

/// 缓存状态
enum CacheStatus {
  waiting('等待中'),
  downloading('下载中'),
  paused('已暂停'),
  completed('已完成'),
  failed('下载失败');

  final String label;
  const CacheStatus(this.label);
}

/// 缓存条目
///
/// 与 PiliPlus 的 BiliDownloadEntryInfo 相比，仅保留源影能拿到的字段：
/// - 播放直链（url / headers）
/// - 视频标题、集数名称、封面
/// - 画质标签
/// - 本地路径、进度、状态
///
/// 进度语义：
/// - M3U8：`totalBytes` / `downloadedBytes` 存的是**分片数**
///   下载完成后 CacheService 会把它们替换为**实际文件字节数**
/// - 直链：`totalBytes` / `downloadedBytes` 始终是**字节数**
class CacheEntry {
  final String id;
  final String vodId;
  final String vodName;
  final String episodeName;
  final String? vodPic;
  final String qualityLabel;
  final String url;
  final Map<String, String>? headers;

  /// 是否是 M3U8 资源
  final bool isM3u8;

  String savePath;
  int totalBytes;
  int downloadedBytes;
  CacheStatus status;
  final int createdAt;
  int updatedAt;

  CacheEntry({
    required this.id,
    required this.vodId,
    required this.vodName,
    required this.episodeName,
    this.vodPic,
    required this.qualityLabel,
    required this.url,
    this.headers,
    this.isM3u8 = false,
    this.savePath = '',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = CacheStatus.waiting,
    required this.createdAt,
    required this.updatedAt,
  });

  // ============================================================
  // 状态判断
  // ============================================================
  bool get isCompleted => status == CacheStatus.completed;
  bool get isDownloading => status == CacheStatus.downloading;
  bool get isPaused => status == CacheStatus.paused;

  // ============================================================
  // 进度
  // ============================================================
  /// 进度百分比 0.0 ~ 1.0
  double get progress =>
      totalBytes == 0 ? 0 : (downloadedBytes / totalBytes).clamp(0.0, 1.0);

  /// 进度百分比文本：`45%`
  String get progressPercent {
    if (totalBytes == 0) return '0%';
    final p = (downloadedBytes / totalBytes * 100).clamp(0, 100);
    return '${p.toStringAsFixed(0)}%';
  }

  /// 进度文本
  ///
  /// - M3U8：`45 / 100 分片`
  /// - 直链：`1.2M / 5.6M`
  String get progressText {
    if (isM3u8) {
      return '$downloadedBytes / $totalBytes 分片';
    }
    return '${CacheManager.formatSize(downloadedBytes)} / '
        '${CacheManager.formatSize(totalBytes)}';
  }

  /// 大小文本（已完成条目使用）
  ///
  /// M3U8 完成后 totalBytes 已被替换为实际文件字节数，
  /// 因此这里统一格式化即可。
  String get sizeText => CacheManager.formatSize(totalBytes);

  // ============================================================
  // 展示
  // ============================================================
  String get displayTitle => episodeName.isNotEmpty ? episodeName : vodName;

  // ============================================================
  // 序列化
  // ============================================================
  Map<String, dynamic> toMap() => {
        'id': id,
        'vodId': vodId,
        'vodName': vodName,
        'episodeName': episodeName,
        'vodPic': vodPic,
        'qualityLabel': qualityLabel,
        'url': url,
        'headers': headers,
        'savePath': savePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'status': status.index,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'isM3u8': isM3u8,
      };

  factory CacheEntry.fromMap(Map<dynamic, dynamic> map) => CacheEntry(
        id: map['id'] as String,
        vodId: map['vodId'] as String? ?? '',
        vodName: map['vodName'] as String? ?? '',
        episodeName: map['episodeName'] as String? ?? '',
        vodPic: map['vodPic'] as String?,
        qualityLabel: map['qualityLabel'] as String? ?? '默认',
        url: map['url'] as String,
        headers: (map['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        isM3u8: map['isM3u8'] as bool? ?? false,
        savePath: map['savePath'] as String? ?? '',
        totalBytes: map['totalBytes'] as int? ?? 0,
        downloadedBytes: map['downloadedBytes'] as int? ?? 0,
        status: CacheStatus.values[(map['status'] as int? ?? 0)
            .clamp(0, CacheStatus.values.length - 1)],
        createdAt: map['createdAt'] as int? ?? 0,
        updatedAt: map['updatedAt'] as int? ?? 0,
      );
}
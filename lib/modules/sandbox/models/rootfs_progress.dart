// lib/modules/sandbox/models/rootfs_progress.dart

/// Rootfs 安装阶段
enum RootfsStage {
  checking,      // 检查缓存
  downloading,   // 下载中
  extracting,    // 解压中
  fixingPerms,   // 修复权限
  configuring,   // 配置网络与软件源
  done,          // 完成
  failed,        // 失败
}

/// Rootfs 安装进度
class RootfsProgress {
  final RootfsStage stage;
  final int received;   // 已下载字节
  final int total;      // 总字节（0 表示未知）
  final String? detail; // 附加信息

  const RootfsProgress({
    required this.stage,
    this.received = 0,
    this.total = 0,
    this.detail,
  });

  double get percent {
    if (total <= 0) return 0;
    return (received / total).clamp(0.0, 1.0);
  }

  /// 是否有明确的进度（下载阶段且 total > 0）
  bool get hasDeterminateProgress =>
      stage == RootfsStage.downloading && total > 0;

  String get stageLabel {
    switch (stage) {
      case RootfsStage.checking:
        return '检查缓存';
      case RootfsStage.downloading:
        return '下载中';
      case RootfsStage.extracting:
        return '解压中';
      case RootfsStage.fixingPerms:
        return '修复权限';
      case RootfsStage.configuring:
        return '配置软件源';
      case RootfsStage.done:
        return '完成';
      case RootfsStage.failed:
        return '失败';
    }
  }

  String get stageDesc {
    switch (stage) {
      case RootfsStage.checking:
        return '正在检查本地缓存…';
      case RootfsStage.downloading:
        return '正在下载 rootfs 镜像（约 3–30MB）';
      case RootfsStage.extracting:
        return '正在解压 rootfs，请稍候（约 5–30 秒）…';
      case RootfsStage.fixingPerms:
        return '正在修复文件权限…';
      case RootfsStage.configuring:
        return '正在配置 DNS 与软件源…';
      case RootfsStage.done:
        return '安装完成';
      case RootfsStage.failed:
        return '安装失败';
    }
  }
}
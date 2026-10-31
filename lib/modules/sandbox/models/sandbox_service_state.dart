// lib/modules/sandbox/models/sandbox_service_state.dart
import 'dart:io';

/// 服务状态（对齐 DsPlayer 的 ServiceStatus）
enum SandboxServiceStatus { stopped, starting, running, error }

extension SandboxServiceStatusLabel on SandboxServiceStatus {
  String get label {
    switch (this) {
      case SandboxServiceStatus.stopped:
        return '已停止';
      case SandboxServiceStatus.starting:
        return '启动中';
      case SandboxServiceStatus.running:
        return '运行中';
      case SandboxServiceStatus.error:
        return '异常';
    }
  }
}

/// 探活方式（对齐 DsPlayer 的 healthType）
enum SandboxHealthType { process, tcp, http }

extension SandboxHealthTypeLabel on SandboxHealthType {
  String get label {
    switch (this) {
      case SandboxHealthType.process:
        return '进程';
      case SandboxHealthType.tcp:
        return 'TCP';
      case SandboxHealthType.http:
        return 'HTTP';
    }
  }
}

/// 运行时状态（不持久化，App 重启后清空）
class SandboxServiceState {
  SandboxServiceStatus status;
  Process? process;
  int? pid;
  String? lastError;

  /// 日志环形缓冲（最近 2000 行）
  final List<String> logs;

  /// 日志版本号（UI 用 Obx 订阅）
  int logVersion;

  /// 启动时间戳
  int? startedAtMs;

  /// 重启次数（本会话）
  int restartCount;

  SandboxServiceState({
    this.status = SandboxServiceStatus.stopped,
    this.process,
    this.pid,
    this.lastError,
    List<String>? logs,
    this.logVersion = 0,
    this.startedAtMs,
    this.restartCount = 0,
  }) : logs = logs ?? [];

  void appendLog(String line) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    logs.add('$ts $line');
    if (logs.length > 2000) {
      logs.removeRange(0, logs.length - 2000);
    }
    logVersion++;
  }

  void clearLogs() {
    logs.clear();
    logVersion++;
  }
}
// lib/modules/sandbox/models/sandbox_service.dart
class SandboxService {
  final String id;
  final String name;

  /// 在沙盒内执行的命令，如 "cd /srv && node app.js --port 5757"
  final String command;

  /// 端口（选填）：填了之后做 TCP 探活 + 支持"打开 Web"
  final int? port;

  /// 备注
  final String? remark;

  final int createdAtMs;

  /// 自启动（App 冷启动时自动拉起）
  final bool autostart;

  const SandboxService({
    required this.id,
    required this.name,
    required this.command,
    this.port,
    this.remark,
    required this.createdAtMs,
    this.autostart = false,
  });

  factory SandboxService.fromJson(Map<String, dynamic> json) {
    return SandboxService(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      command: json['command']?.toString() ?? '',
      port: (json['port'] is num) ? (json['port'] as num).toInt() : null,
      remark: json['remark']?.toString(),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs'] as num).toInt()
          : 0,
      autostart: json['autostart'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'port': port,
        'remark': remark,
        'createdAtMs': createdAtMs,
        'autostart': autostart,
      };

  SandboxService copyWith({
    String? name,
    String? command,
    int? port,
    String? remark,
    bool? autostart,
  }) {
    return SandboxService(
      id: id,
      name: name ?? this.name,
      command: command ?? this.command,
      port: port ?? this.port,
      remark: remark ?? this.remark,
      createdAtMs: createdAtMs,
      autostart: autostart ?? this.autostart,
    );
  }
}
// lib/modules/plugin_center/models/service_config.dart

/// 服务配置
class ServiceConfig {
  final String id;
  final String name;

  /// 选填端口
  final int? port;

  /// 引用的运行时插件 id（如 nodejs-win / php-win / python-win / custom）
  final String runtime;

  /// 启动参数
  final List<String> args;

  /// 工作目录
  final String cwd;

  /// App 冷启动时自动拉起
  final bool autostart;

  /// 常驻前台服务（App 关闭时不杀）
  final bool keepForeground;

  /// 环境变量
  final Map<String, String> env;

  /// 高级：本会话最多重启次数（0=不重启）
  final int maxRestart;

  // ===== 新增字段 =====

  /// 自定义可执行文件路径（空 = 按 runtime 自动解析）
  final String? executable;

  /// 探活方式：process / tcp / http
  final String healthType;

  /// HTTP 探活路径（healthType == 'http' 时用）
  final String healthPath;

  /// PID 文件路径（仅自定义环境用；空 = 自动生成）
  final String? pidFile;

  ServiceConfig({
    required this.id,
    required this.name,
    this.port,
    required this.runtime,
    this.args = const [],
    required this.cwd,
    this.autostart = false,
    this.keepForeground = false,
    this.env = const {},
    this.maxRestart = 1,
    this.executable,
    this.healthType = 'process',
    this.healthPath = '/',
    this.pidFile,
  });

  factory ServiceConfig.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'];
    final rawEnv = json['env'];
    return ServiceConfig(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      port: (json['port'] is num) ? (json['port'] as num).toInt() : null,
      runtime: json['runtime']?.toString() ?? '',
      args: rawArgs is List
          ? rawArgs.map((e) => e.toString()).toList()
          : const [],
      cwd: json['cwd']?.toString() ?? '',
      autostart: json['autostart'] == true,
      keepForeground: json['keepForeground'] == true,
      env: rawEnv is Map
          ? rawEnv.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      maxRestart: (json['maxRestart'] is num)
          ? (json['maxRestart'] as num).toInt()
          : 1,
      executable: json['executable']?.toString(),
      healthType: json['healthType']?.toString() ?? 'process',
      healthPath: json['healthPath']?.toString() ?? '/',
      pidFile: json['pidFile']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'port': port,
        'runtime': runtime,
        'args': args,
        'cwd': cwd,
        'autostart': autostart,
        'keepForeground': keepForeground,
        'env': env,
        'maxRestart': maxRestart,
        'executable': executable,
        'healthType': healthType,
        'healthPath': healthPath,
        'pidFile': pidFile,
      };

  ServiceConfig copyWith({
    String? name,
    int? port,
    String? runtime,
    List<String>? args,
    String? cwd,
    bool? autostart,
    bool? keepForeground,
    Map<String, String>? env,
    int? maxRestart,
    String? executable,
    String? healthType,
    String? healthPath,
    String? pidFile,
  }) {
    return ServiceConfig(
      id: id,
      name: name ?? this.name,
      port: port ?? this.port,
      runtime: runtime ?? this.runtime,
      args: args ?? this.args,
      cwd: cwd ?? this.cwd,
      autostart: autostart ?? this.autostart,
      keepForeground: keepForeground ?? this.keepForeground,
      env: env ?? this.env,
      maxRestart: maxRestart ?? this.maxRestart,
      executable: executable ?? this.executable,
      healthType: healthType ?? this.healthType,
      healthPath: healthPath ?? this.healthPath,
      pidFile: pidFile ?? this.pidFile,
    );
  }
}

/// 服务运行时状态
enum ServiceStatus {
  stopped,
  starting,
  running,
  error,
}

extension ServiceStatusLabel on ServiceStatus {
  String get label {
    switch (this) {
      case ServiceStatus.stopped:
        return '已停止';
      case ServiceStatus.starting:
        return '启动中';
      case ServiceStatus.running:
        return '运行中';
      case ServiceStatus.error:
        return '异常';
    }
  }
}
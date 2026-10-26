// lib/modules/local_php_t4/services/php_t4_service.dart

import 'dart:io';

import 'package:hive_ce/hive.dart';

import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/utils/business_exception.dart';

import 'php_t4_scanner.dart';

/// PHP-T4 本地服务：基于插件中心 ServiceManager 启动
///
/// - 服务 ID 固定为 `svc-local-php-t4`，在 ServiceManager 里可被引用，
///   但**不会展示在服务 Tab**（由 PHP-T4 专用页面管理）
/// - 运行时依赖 `php-win`（Windows）/ `php`（Android）插件
/// - 通过 `php -S 0.0.0.0:{port} -t {cwd}` 起内置 web 服务器
/// - 支持用户指定端口；未指定时自动 5788~5797
abstract final class PhpT4Service {
  static const String serviceId = 'svc-local-php-t4';
  static const String serviceName = 'PHP-T4 本地服务';

  /// 自动分配的起始端口（共尝试 _portRange 个）
  static const int defaultPort = 5788;
  static const int _portRange = 10;

  /// 用户指定端口的 Hive key（不存在 = 自动分配）
  static const String _preferredPortKey = 'php_t4_preferred_port';

  static bool get isSupported => Platform.isWindows || Platform.isAndroid;

  static String get runtimeId => Platform.isWindows ? 'php-win' : 'php';

  // ============================================================
  // 端口设置（持久化到 app_settings）
  // ============================================================
  static Box? get _box {
    try {
      return Hive.box('app_settings');
    } catch (_) {
      return null;
    }
  }

  /// 读取用户指定端口；返回 null 表示自动分配
  static int? getPreferredPort() {
    final v = _box?.get(_preferredPortKey);
    if (v is int && v > 0 && v <= 65535) return v;
    return null;
  }

  /// 设置用户指定端口（传 null 表示改回自动分配）
  static Future<void> setPreferredPort(int? port) async {
    final box = _box;
    if (box == null) return;
    if (port == null) {
      await box.delete(_preferredPortKey);
    } else {
      await box.put(_preferredPortKey, port);
    }
  }

  // ============================================================
  // 运行时检查
  // ============================================================
  /// 检查 PHP 运行时插件是否可用；返回 null 表示可用
  static String? checkRuntime() {
    if (!isSupported) {
      return 'PHP-T4 本地服务仅支持 Windows / Android';
    }
    final reg = InstallManager.instance.findInstalled(runtimeId);
    if (reg == null) {
      return '未安装 PHP 运行时（$runtimeId）。'
          '请前往「插件中心 → 市场」安装后再启动 PHP-T4 服务。';
    }
    if (!reg.enabled) {
      return 'PHP 运行时（$runtimeId）已关闭。'
          '请前往「插件中心 → 插件」重新开启后再启动 PHP-T4 服务。';
    }
    return null;
  }

  // ============================================================
  // 服务状态
  // ============================================================
  static ServiceStatus get status =>
      ServiceManager.instance.getStatus(serviceId);

  static bool get isRunning => status == ServiceStatus.running;

  static int? get currentPort => ServiceManager.instance.find(serviceId)?.port;

  // ============================================================
  // 端口解析
  // ============================================================
  /// 解析端口：用户指定优先（占用则抛错），否则自动从 5788 尝试 +1
  static Future<int> resolvePort() async {
    final preferred = getPreferredPort();
    if (preferred != null) {
      try {
        final socket =
            await ServerSocket.bind(InternetAddress.anyIPv4, preferred);
        await socket.close();
        return preferred;
      } catch (_) {
        throw BusinessException(
          '指定端口 $preferred 已被占用，请更换端口或改回自动分配',
        );
      }
    }
    for (var port = defaultPort; port < defaultPort + _portRange; port++) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
        await socket.close();
        return port;
      } catch (_) {}
    }
    throw BusinessException(
      '无可用端口（$defaultPort~${defaultPort + _portRange - 1} 均被占用），'
      '请关闭其他服务后重试，或在端口设置里手动指定',
    );
  }

  // ============================================================
  // 配置 / 启动 / 停止
  // ============================================================
  static Future<void> ensureConfig({required int port}) async {
    final dir = await PhpT4Scanner.dir();
    final config = ServiceConfig(
      id: serviceId,
      name: serviceName,
      port: port,
      runtime: runtimeId,
      args: ['-S', '0.0.0.0:$port', '-t', dir.path],
      cwd: dir.path,
      autostart: false,
      keepForeground: false,
      healthType: 'tcp',
    );
    await ServiceManager.instance.addOrUpdate(config);
  }

  /// 启动服务；失败抛 BusinessException。成功返回实际端口
  static Future<int> start() async {
    // 1) 运行时插件
    final runtimeError = checkRuntime();
    if (runtimeError != null) throw BusinessException(runtimeError);

    // 2) 骨架完整性
    final missing = await PhpT4Scanner.missingSkeletonFiles();
    if (missing.isNotEmpty) {
      throw BusinessException(
        'PHP-T4 骨架包不完整（缺少 ${missing.length} 个文件：${missing.join('、')}）。'
        '请把完整骨架文件放入 spider/php-t4 目录后重试。',
      );
    }

    // 3) 端口 + 启动
    final port = await resolvePort();
    await ensureConfig(port: port);
    try {
      await ServiceManager.instance.start(serviceId);
    } catch (e) {
      throw BusinessException('启动失败：$e');
    }
    if (status != ServiceStatus.running) {
      final lastError = ServiceManager.instance.getLastError(serviceId);
      throw BusinessException(lastError ?? '服务未进入运行状态');
    }
    return port;
  }

  /// 停止服务（幂等）
  static Future<void> stop() async {
    try {
      await ServiceManager.instance.stop(serviceId);
    } catch (_) {}
  }

  /// 构造用于日志弹窗的 ServiceConfig
  ///
  /// 服务未启动过时 `find()` 返回 null，此时构造一个临时 config，
  /// 保证日志弹窗能正常打开（显示"暂无日志"）。
  static Future<ServiceConfig> buildConfigForLog() async {
    final existing = ServiceManager.instance.find(serviceId);
    if (existing != null) return existing;
    final dir = await PhpT4Scanner.dir();
    return ServiceConfig(
      id: serviceId,
      name: serviceName,
      port: getPreferredPort() ?? defaultPort,
      runtime: runtimeId,
      args: const [],
      cwd: dir.path,
      autostart: false,
      keepForeground: false,
    );
  }

  // ============================================================
  // 局域网地址
  // ============================================================
  static Future<String> localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  static String configUrl({required String ip, required int port}) {
    return 'http://$ip:$port/config.php';
  }
}
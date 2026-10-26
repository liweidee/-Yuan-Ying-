// lib/modules/plugin_center/services/port_cleaner.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import 'package:yuanying/core/constants/plugin_storage_keys.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';

/// 端口占用类型
enum PortOccupancyType {
  /// 残留：服务已停止，但进程还在（我们启动的）
  residual,

  /// 运行中：服务正在跑
  running,

  /// 端口冲突：端口被别的进程占（不是我们启动的，含应用自身）
  conflict,

  /// 其他应用占用
  others,
}

extension PortOccupancyTypeLabel on PortOccupancyType {
  String get label {
    switch (this) {
      case PortOccupancyType.residual:
        return '残留进程';
      case PortOccupancyType.running:
        return '运行中';
      case PortOccupancyType.conflict:
        return '端口冲突';
      case PortOccupancyType.others:
        return '其他应用';
    }
  }
}

/// 端口占用项
class PortOccupant {
  final int port;
  final String serviceName;
  final int? pid;
  final String? processName;
  final PortOccupancyType type;

  const PortOccupant({
    required this.port,
    required this.serviceName,
    this.pid,
    this.processName,
    required this.type,
  });

  /// 是否可被强杀：只杀「残留」（运行中由用户去服务 Tab 停）
  bool get killable => type == PortOccupancyType.residual;
}

/// 端口清理器
abstract final class PortCleaner {
  /// 检测所有已配置服务的端口占用
  static Future<List<PortOccupant>> scan() async {
    final services = ServiceManager.instance.getAll();
    final result = <PortOccupant>[];
    final selfPid = pid;

    for (final s in services) {
      if (s.port == null || s.port! <= 0) continue;

      final foundPid = await _findPidByPort(s.port!);
      if (foundPid == null) continue; // 端口空闲，跳过

      final procName = await _getProcessName(foundPid);
      final serviceRunning =
          ServiceManager.instance.getStatus(s.id) == ServiceStatus.running;

      // 1. 自身进程 → 冲突（绝对不杀）
      if (foundPid == selfPid) {
        result.add(PortOccupant(
          port: s.port!,
          serviceName: s.name,
          pid: foundPid,
          processName: procName,
          type: PortOccupancyType.conflict,
        ));
        continue;
      }

      // 2. 服务运行中
      if (serviceRunning) {
        final runtimePid = ServiceManager.instance.getPid(s.id);
        if (runtimePid == foundPid) {
          // 我们启动的，正常
          result.add(PortOccupant(
            port: s.port!,
            serviceName: s.name,
            pid: foundPid,
            processName: procName,
            type: PortOccupancyType.running,
          ));
        } else {
          // 服务运行中但端口被别的进程占 → 冲突
          result.add(PortOccupant(
            port: s.port!,
            serviceName: s.name,
            pid: foundPid,
            processName: procName,
            type: PortOccupancyType.conflict,
          ));
        }
        continue;
      }

      // 3. 服务已停止
      final isOurPath = await _isOurProcessPath(foundPid);
      if (isOurPath) {
        result.add(PortOccupant(
          port: s.port!,
          serviceName: s.name,
          pid: foundPid,
          processName: procName,
          type: PortOccupancyType.residual,
        ));
      } else {
        result.add(PortOccupant(
          port: s.port!,
          serviceName: s.name,
          pid: foundPid,
          processName: procName,
          type: PortOccupancyType.others,
        ));
      }
    }
    return result;
  }

  /// 强杀单个 PID
  static Future<bool> killPid(int pid) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'taskkill',
        ['/F', '/PID', '$pid'],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 5));
      debugPrint('[PortCleaner] taskkill $pid → ${result.exitCode}');
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('[PortCleaner] kill $pid failed: $e');
      return false;
    }
  }

  /// 强杀所有「残留」进程（不含运行中/冲突/其他/自身）
  static Future<int> killAllOurs(List<PortOccupant> list) async {
    int killed = 0;
    for (final occ in list) {
      if (occ.type != PortOccupancyType.residual || occ.pid == null) continue;
      final ok = await killPid(occ.pid!);
      if (ok) killed++;
    }
    return killed;
  }

  /// 服务启动前的端口清理钩子：
  /// 若端口被“我们自己上次的残留进程”占用，强杀并返回 true；
  /// 端口空闲 / 被其他应用占用 / 杀失败 → 返回 false。
  /// 仅 Windows 有效；Android 恒返回 false（跨进程无法杀）。
  static Future<bool> tryKillResidualOnPort(int port) async {
    if (!Platform.isWindows) return false;
    try {
      final foundPid = await _findPidByPort(port);
      if (foundPid == null) return true; // 端口已空闲
      // 自身进程绝不杀
      if (foundPid == pid) return false;
      // 仅杀“我们自己的残留”
      final isOurs = await _isOurProcessPath(foundPid);
      if (!isOurs) return false;
      return await killPid(foundPid);
    } catch (e) {
      debugPrint('[PortCleaner] tryKillResidualOnPort($port) failed: $e');
      return false;
    }
  }

  // ============================================================
  // 自动清理开关
  // ============================================================

  static bool isAutoCleanEnabled() {
    final box = Hive.box(PluginStorageKeys.serviceBox);
    return box.get(PluginStorageKeys.autoCleanOrphan) == true;
  }

  static Future<void> setAutoCleanEnabled(bool enabled) async {
    final box = Hive.box(PluginStorageKeys.serviceBox);
    await box.put(PluginStorageKeys.autoCleanOrphan, enabled);
  }

  /// App 启动时如果开了自动清理，静默清理「残留」（不含运行中）
  static Future<void> autoCleanIfEnabled() async {
    if (!isAutoCleanEnabled()) return;
    try {
      final list = await scan();
      int killed = 0;
      for (final occ in list) {
        if (occ.type != PortOccupancyType.residual || occ.pid == null) {
          continue;
        }
        final ok = await killPid(occ.pid!);
        if (ok) killed++;
      }
      if (killed > 0) {
        debugPrint('[PortCleaner] 自动清理了 $killed 个残留进程');
      }
    } catch (e) {
      debugPrint('[PortCleaner] autoClean failed: $e');
    }
  }

  // ============================================================
  // 内部：netstat / tasklist / powershell
  // ============================================================

  static Future<int?> _findPidByPort(int port) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-NetTCPConnection -LocalPort $port -State Listen '
              '-ErrorAction SilentlyContinue | '
              'Where-Object { \$_.OwningProcess -gt 0 } | '
              'Select-Object -ExpandProperty OwningProcess -First 1',
        ],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 5));

      final out = result.stdout.toString().trim();
      if (out.isEmpty) return null;
      final p = int.tryParse(out);
      if (p == null || p == 0) return null;
      return p;
    } catch (e) {
      debugPrint('[PortCleaner] _findPidByPort($port) failed: $e');
      return null;
    }
  }

  static Future<String?> _getProcessName(int pid) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'tasklist',
        ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 5));
      final out = result.stdout.toString().trim();
      if (out.isEmpty) return null;
      final firstComma = out.indexOf(',');
      if (firstComma <= 0) return null;
      return out.substring(0, firstComma).replaceAll('"', '').trim();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isOurProcessPath(int pid) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_Process -Filter "ProcessId=$pid").CommandLine',
        ],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 5));

      final cmdline = result.stdout.toString().trim();
      if (cmdline.isEmpty) return false;
      return cmdline.contains('plugins') || cmdline.contains('services');
    } catch (_) {
      return false;
    }
  }
}
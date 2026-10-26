// lib/modules/plugin_center/services/service_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import 'package:yuanying/core/constants/plugin_storage_keys.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/port_cleaner.dart';

/// 服务事件类型
enum ServiceEventType {
  started,
  stopped,
  failed,
  portTimeout,
  abnormalExit,
  restartFailed,
}

class ServiceEvent {
  final String serviceId;
  final String serviceName;
  final ServiceEventType type;
  final String? message;
  final String? detail;

  const ServiceEvent({
    required this.serviceId,
    required this.serviceName,
    required this.type,
    this.message,
    this.detail,
  });
}

class ServiceRuntimeState {
  ServiceStatus status;
  int? pid;
  String? lastError;

  ServiceRuntimeState({
    this.status = ServiceStatus.stopped,
    this.pid,
    this.lastError,
  });
}

class ServiceManager {
  ServiceManager._();
  static final ServiceManager instance = ServiceManager._();

  Box get _box => Hive.box(PluginStorageKeys.serviceBox);

  final Map<String, ServiceRuntimeState> _runtimeStates = {};
  final Map<String, Process> _processes = {};
  final Map<String, Timer> _healthCheckTimers = {};
  final Map<String, int> _restartCounts = {};
  bool _isShuttingDown = false;

  /// 每个 serviceId 一把启动锁：
  /// 堵死「自启动 autoStartAll 与用户手动 start 并发」以及「用户快速双击启动」
  /// 导致的重复 spawn / 孤儿进程。锁粒度按服务隔离，互不阻塞。
  final Map<String, Lock> _startLocks = {};

  Lock _startLockFor(String serviceId) =>
      _startLocks.putIfAbsent(serviceId, () => Lock());

  final Map<String, List<String>> _serviceLogs = {};
  final Map<String, RxInt> _logVersions = {};
  static const int _maxLogLines = 2000;

  /// 端口 → 服务 id 的全局占用表（内存态，权威来源）
  /// 用途：在 spawn 之前拦截「两个服务抢同一端口」，并区分「残留进程」与「活跃服务」
  final Map<int, String> _portOwners = {};
  final Lock _portLock = Lock();

  final RxInt revision = 0.obs;

  final StreamController<void> _changeController =
      StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;

  final StreamController<ServiceEvent> _eventController =
      StreamController<ServiceEvent>.broadcast();
  Stream<ServiceEvent> get onEvent => _eventController.stream;

  void _notifyChange() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
    revision.value++;
  }

  void _emitEvent(ServiceEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  // ============================================================
  // 端口表
  // ============================================================

  /// 登记端口占用。
  /// - 该服务已有其他端口登记 → 先释放旧登记（改端口重启场景）
  /// - 端口被「活跃服务」占用 → 返回 false
  /// - 端口被「僵尸登记」（占用者非 running/starting）占用 → 接管
  Future<bool> _claimPort(int port, String serviceId) async {
    return await _portLock.synchronized(() {
      // 先释放该服务的旧端口登记（改端口重启）
      _portOwners.removeWhere((p, owner) => owner == serviceId && p != port);
      final owner = _portOwners[port];
      if (owner != null && owner != serviceId) {
        final ownerStatus = getStatus(owner);
        if (ownerStatus == ServiceStatus.running ||
            ownerStatus == ServiceStatus.starting) {
          return false;
        }
        // 僵尸登记：占用者不活跃，接管
      }
      _portOwners[port] = serviceId;
      return true;
    });
  }

  /// 释放端口占用（幂等）
  Future<void> _releasePort(String serviceId) async {
    await _portLock.synchronized(() {
      _portOwners.removeWhere((port, owner) => owner == serviceId);
    });
  }

  /// 查询端口当前归属（调试/报错用）
  String? getPortOwner(int port) => _portOwners[port];

  // ============================================================
  // 占位符替换
  // ============================================================

  Future<String> _resolvePlaceholders(String input) async {
    if (!input.contains('__')) return input;
    var result = input;

    final dataRoot = await PluginPaths.dataRoot();
    final rootPath = dataRoot.path.replaceAll('\\', '/');

    result = result.replaceAll('__filesDir__', rootPath);
    result = result.replaceAll('__sdcard__', rootPath);
    result = result.replaceAll('__pkg__', 'com.example.yuanying');

    final pluginPattern = RegExp(r'__plugin:([\w\-]+)__');
    final matches = pluginPattern.allMatches(result).toList();
    for (final m in matches) {
      final pluginId = m.group(1)!;
      final installed = InstallManager.instance.findInstalled(pluginId);
      if (installed != null) {
        result = result.replaceAll(
          m.group(0)!,
          installed.installPath.replaceAll('\\', '/'),
        );
      }
    }

    return result;
  }

  // ============================================================
  // 日志
  // ============================================================

  List<String> getLogs(String serviceId) {
    return List<String>.from(_serviceLogs[serviceId] ?? const []);
  }

  RxInt logVersionOf(String serviceId) {
    return _logVersions.putIfAbsent(serviceId, () => 0.obs);
  }

  void clearLogs(String serviceId) {
    _serviceLogs[serviceId] = [];
    logVersionOf(serviceId).value++;
  }

  void _appendLog(String serviceId, String line) {
    final buf = _serviceLogs.putIfAbsent(serviceId, () => []);
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    buf.add('$ts $line');
    if (buf.length > _maxLogLines) {
      buf.removeRange(0, buf.length - _maxLogLines);
    }
    logVersionOf(serviceId).value++;
  }

  // ============================================================
  // 配置 CRUD
  // ============================================================

  List<ServiceConfig> getAll() {
    final raw = _box.get(PluginStorageKeys.serviceList);
    if (raw is! List) return [];
    return raw
        .map((e) =>
            ServiceConfig.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  ServiceConfig? find(String id) {
    for (final s in getAll()) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _saveAll(List<ServiceConfig> list) async {
    await _box.put(
      PluginStorageKeys.serviceList,
      list.map((e) => e.toJson()).toList(),
    );
    _notifyChange();
  }

  Future<void> addOrUpdate(ServiceConfig config) async {
    final list = getAll();
    final idx = list.indexWhere((e) => e.id == config.id);
    if (idx >= 0) {
      list[idx] = config;
    } else {
      list.add(config);
    }
    await _saveAll(list);
  }

  Future<void> remove(String id) async {
    await stop(id);
    final list = getAll();
    list.removeWhere((e) => e.id == id);
    await _saveAll(list);
    _runtimeStates.remove(id);
    _restartCounts.remove(id);
    _serviceLogs.remove(id);
    _logVersions.remove(id);
    _startLocks.remove(id);
    await _releasePort(id);
    _notifyChange();
  }

  Future<void> removeWithDir(String id) async {
    final config = find(id);
    if (config == null) return;
    final cwd = config.cwd;

    await stop(id);

    final list = getAll();
    list.removeWhere((e) => e.id == id);
    await _saveAll(list);
    _runtimeStates.remove(id);
    _restartCounts.remove(id);
    _serviceLogs.remove(id);
    _logVersions.remove(id);
    _startLocks.remove(id);
    await _releasePort(id);
    _notifyChange();

    try {
      final servicesRoot = await PluginPaths.servicesRoot();
      final cwdPath = p.normalize(cwd);
      final rootPath = p.normalize(servicesRoot.path);
      if (cwdPath != rootPath &&
          cwdPath.startsWith('$rootPath${p.separator}')) {
        final d = Directory(cwd);
        if (d.existsSync()) {
          await d.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('[ServiceManager] delete cwd failed: $e');
    }
  }

  // ============================================================
  // 运行时状态
  // ============================================================

  ServiceStatus getStatus(String id) {
    return _runtimeStates[id]?.status ?? ServiceStatus.stopped;
  }

  int? getPid(String id) => _runtimeStates[id]?.pid;
  String? getLastError(String id) => _runtimeStates[id]?.lastError;

  void _setStatus(
    String id,
    ServiceStatus status, {
    int? pid,
    String? lastError,
  }) {
    final state = _runtimeStates.putIfAbsent(id, () => ServiceRuntimeState());
    state.status = status;
    if (pid != null) state.pid = pid;
    if (lastError != null) state.lastError = lastError;
    _notifyChange();
  }

  void resetToStopped(String id) {
    if (_processes.containsKey(id)) return;
    _setStatus(id, ServiceStatus.stopped, pid: null);
    // 兜底：状态重置为 stopped 时释放端口（防止僵尸登记阻塞后续启动）
    _releasePort(id);
  }

  // ============================================================
  // 启动
  // ============================================================

  Future<void> start(String serviceId) async {
    // D1：按 serviceId 粒度串行化，堵死「自启动 autoStartAll 与手动 start 并发」
    // 以及「快速双击启动」导致的重复 spawn / 孤儿进程。
    // 第二次进入锁时，第一次已把状态置为 starting/running，
    // 原有的状态判断会直接 return，行为等价于「第二次调用被忽略」。
    await _startLockFor(serviceId).synchronized(() async {
      await _startInternal(serviceId);
    });
  }

  Future<void> _startInternal(String serviceId) async {
    final config = find(serviceId);
    if (config == null) throw Exception('服务不存在：$serviceId');

    final current = getStatus(serviceId);
    if (current == ServiceStatus.running ||
        current == ServiceStatus.starting) {
      return;
    }

    // 运行时插件检查（custom 不检查）
    if (config.runtime != 'custom') {
      final runtimePlugin =
          InstallManager.instance.findInstalled(config.runtime);
      if (runtimePlugin == null) {
        final msg = '依赖插件 ${config.runtime} 未安装，请先从市场安装';
        _appendLog(serviceId, '[error] $msg');
        _setStatus(serviceId, ServiceStatus.error, lastError: msg);
        _emitEvent(ServiceEvent(
          serviceId: serviceId,
          serviceName: config.name,
          type: ServiceEventType.failed,
          message: '依赖插件未安装',
          detail: msg,
        ));
        throw Exception(msg);
      }
      if (!runtimePlugin.enabled) {
        final msg = '依赖插件 ${config.runtime} 已关闭，请先在插件 Tab 开启';
        _appendLog(serviceId, '[error] $msg');
        _setStatus(serviceId, ServiceStatus.error, lastError: msg);
        _emitEvent(ServiceEvent(
          serviceId: serviceId,
          serviceName: config.name,
          type: ServiceEventType.failed,
          message: '依赖插件已关闭',
          detail: msg,
        ));
        throw Exception(msg);
      }
    }

    _setStatus(serviceId, ServiceStatus.starting);

    // ===== 端口预检（spawn 前） =====
    if (config.port != null && config.port! > 0) {
      final port = config.port!;

      // 1. 先查端口表：被其他活跃服务占用 → 直接报错
      final claimed = await _claimPort(port, serviceId);
      if (!claimed) {
        final owner = getPortOwner(port);
        final ownerName = owner != null ? (find(owner)?.name ?? owner) : '';
        final msg = ownerName.isNotEmpty
            ? '端口 $port 已被服务「$ownerName」占用，请更换端口'
            : '端口 $port 已被占用，请更换端口';
        _appendLog(serviceId, '[error] $msg');
        _setStatus(serviceId, ServiceStatus.error, lastError: msg);
        _emitEvent(ServiceEvent(
          serviceId: serviceId,
          serviceName: config.name,
          type: ServiceEventType.failed,
          message: '端口冲突',
          detail: msg,
        ));
        throw Exception(msg);
      }

      // 2. 端口表登记成功，再探实际占用（可能是残留或外部应用）
      final occupied = await _probePort(port);
      if (occupied) {
        if (Platform.isWindows) {
          final killed = await PortCleaner.tryKillResidualOnPort(port);
          if (killed) {
            await Future.delayed(const Duration(milliseconds: 200));
          } else {
            await _releasePort(serviceId);
            final msg = '端口 $port 已被其他应用占用，请更换端口';
            _appendLog(serviceId, '[error] $msg');
            _setStatus(serviceId, ServiceStatus.error, lastError: msg);
            _emitEvent(ServiceEvent(
              serviceId: serviceId,
              serviceName: config.name,
              type: ServiceEventType.failed,
              message: '端口被占用',
              detail: msg,
            ));
            throw Exception(msg);
          }
        } else {
          await _releasePort(serviceId);
          final msg = '端口 $port 已被占用，请更换端口或重启应用';
          _appendLog(serviceId, '[error] $msg');
          _setStatus(serviceId, ServiceStatus.error, lastError: msg);
          _emitEvent(ServiceEvent(
            serviceId: serviceId,
            serviceName: config.name,
            type: ServiceEventType.failed,
            message: '端口被占用',
            detail: msg,
          ));
          throw Exception(msg);
        }
      }
    }

    // 解析可执行文件
    final executable = await _resolveExecutable(config);
    if (executable == null) {
      await _releasePort(serviceId);
      _appendLog(serviceId, '[error] 找不到可执行文件');
      _setStatus(serviceId, ServiceStatus.error, lastError: '找不到可执行文件');
      _emitEvent(ServiceEvent(
        serviceId: serviceId,
        serviceName: config.name,
        type: ServiceEventType.failed,
        message: '找不到可执行文件',
        detail: config.executable ?? config.runtime,
      ));
      throw Exception('找不到可执行文件');
    }

    // 占位符替换
    final resolvedExe = await _resolvePlaceholders(executable);
    final resolvedArgs =
        await Future.wait(config.args.map(_resolvePlaceholders));
    final resolvedCwd = await _resolvePlaceholders(config.cwd);
    final resolvedEnv = <String, String>{};
    for (final e in config.env.entries) {
      resolvedEnv[e.key] = await _resolvePlaceholders(e.value);
    }

    final cwdDir = Directory(resolvedCwd);
    if (!cwdDir.existsSync()) {
      await cwdDir.create(recursive: true);
    }

    _appendLog(
      serviceId,
      '[start] spawn $resolvedExe ${resolvedArgs.join(' ')}',
    );

    final env = <String, String>{
      ...Platform.environment,
      ...resolvedEnv,
    };
    if (config.runtime.startsWith('python')) {
      env['PYTHONIOENCODING'] = 'utf-8';
      env['PYTHONUTF8'] = '1';

      // 注入 pyRuntime.env（PYTHONHOME / LD_LIBRARY_PATH 等，musl python 必需）
      final installed = InstallManager.instance.findInstalled(config.runtime);
      if (installed != null) {
        final pluginJson = File(p.join(installed.installPath, 'plugin.json'));
        if (pluginJson.existsSync()) {
          try {
            final j = jsonDecode(await pluginJson.readAsString()) as Map;
            final pyEnv = j['pyRuntime']?['env'];
            if (pyEnv is Map) {
              for (final e in pyEnv.entries) {
                final k = e.key.toString();
                final v = await _resolvePlaceholders(e.value.toString());
                env[k] = v;
              }
            }
          } catch (_) {}
        }
      }
    }

    Process process;
    try {
      process = await Process.start(
        resolvedExe,
        resolvedArgs,
        workingDirectory: resolvedCwd,
        environment: env,
      );
    } catch (e) {
      await _releasePort(serviceId);
      _appendLog(serviceId, '[error] $e');
      _setStatus(serviceId, ServiceStatus.error, lastError: '启动失败：$e');
      _emitEvent(ServiceEvent(
        serviceId: serviceId,
        serviceName: config.name,
        type: ServiceEventType.failed,
        message: '启动进程失败',
        detail: '$e',
      ));
      throw Exception('启动进程失败：$e');
    }

    _processes[serviceId] = process;
    _appendLog(serviceId, '[proc] pid=${process.pid}');
    _setStatus(serviceId, ServiceStatus.starting, pid: process.pid);

    // 写 PID 文件（仅自定义环境）
    await _writePidFile(config, process.pid);

    final stdoutDecoder = const Utf8Codec(allowMalformed: true).decoder;
    final stderrDecoder = const Utf8Codec(allowMalformed: true).decoder;

    process.stdout
        .transform(stdoutDecoder)
        .transform(const LineSplitter())
        .listen((line) {
      _appendLog(serviceId, line);
    });
    process.stderr
        .transform(stderrDecoder)
        .transform(const LineSplitter())
        .listen((line) {
      _appendLog(serviceId, '[err] $line');
    });

    final startedProcess = process;
    startedProcess.exitCode.then((code) {
      if (_processes[serviceId] != startedProcess) return;
      _appendLog(serviceId, '[proc] exited ($code)');
      _processes.remove(serviceId);
      _stopHealthCheck(serviceId);
      _setStatus(serviceId, ServiceStatus.stopped, pid: null);
      _deletePidFile(config);
      _releasePort(serviceId);

      if (_isShuttingDown) return;

      final restartCount = _restartCounts[serviceId] ?? 0;
      if (restartCount >= config.maxRestart) {
        _appendLog(serviceId, '[state] 已达重启上限，不再重启');
        _setStatus(serviceId, ServiceStatus.error, lastError: '进程异常退出');
        _emitEvent(ServiceEvent(
          serviceId: serviceId,
          serviceName: config.name,
          type: ServiceEventType.restartFailed,
          message: '重启 $restartCount 次仍失败，已停止自动重启',
          detail: '退出码：$code',
        ));
        return;
      }

      _restartCounts[serviceId] = restartCount + 1;
      _appendLog(serviceId, '[restart] 尝试第 ${restartCount + 1} 次重启');
      Future.delayed(const Duration(seconds: 2), () {
        if (_isShuttingDown) return;
        start(serviceId).catchError((e) {});
      });
    });

    // 探活
    await _waitForReady(serviceId, config, process);
  }

  /// 按 healthType 探活
  Future<void> _waitForReady(
    String serviceId,
    ServiceConfig config,
    Process process,
  ) async {
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (getStatus(serviceId) == ServiceStatus.stopped) return;
      if (!_processes.containsKey(serviceId)) {
        _appendLog(serviceId, '[error] 进程已退出');
        return;
      }

      bool ok = false;
      switch (config.healthType) {
        case 'process':
          ok = _processes.containsKey(serviceId);
          break;
        case 'tcp':
          if (config.port != null && config.port! > 0) {
            ok = await _probePort(config.port!);
          }
          break;
        case 'http':
          if (config.port != null && config.port! > 0) {
            ok = await _probeHttp(config.port!, config.healthPath);
          }
          break;
      }

      if (ok) {
        _setStatus(serviceId, ServiceStatus.running);
        _appendLog(serviceId, '[health] ${config.healthType} → OK');
        _startHealthCheck(serviceId, config);
        _emitEvent(ServiceEvent(
          serviceId: serviceId,
          serviceName: config.name,
          type: ServiceEventType.started,
          message: config.port != null ? '端口 ${config.port}' : null,
        ));
        return;
      }
    }

    // C9+D5：探活超时。
    // 原实现只把状态标 error，进程仍存活并占着端口 →
    // 用户重新点启动时 _claimPort 把 error 当僵尸接管，
    // 新进程 spawn 后绑端口失败 → 探活又失败 → 陷入永久不可用。
    // 修复：先把 _processes 引用摘除（避免 exitCode.then 回调误判
    // "进程还活着" 而触发自动重启），再 sigkill 掉进程，释放端口。
    _appendLog(serviceId, '[error] 探活超时（15 秒），已终止进程');
    _processes.remove(serviceId);
    _stopHealthCheck(serviceId);
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {}
    await _releasePort(serviceId);
    _setStatus(serviceId, ServiceStatus.error, lastError: '探活超时（15 秒）');
    _emitEvent(ServiceEvent(
      serviceId: serviceId,
      serviceName: config.name,
      type: ServiceEventType.portTimeout,
      message: '探活超时（15 秒）',
      detail: '请查看运行日志',
    ));
  }

  Future<bool> _probePort(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 800),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeHttp(int port, String path) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 800);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final resp = await req.close();
      client.close(force: true);
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  void _startHealthCheck(String serviceId, ServiceConfig config) {
    _stopHealthCheck(serviceId);
    _healthCheckTimers[serviceId] = Timer.periodic(
      const Duration(seconds: 5),
      (timer) async {
        if (getStatus(serviceId) != ServiceStatus.running) {
          timer.cancel();
          return;
        }
        bool ok = false;
        switch (config.healthType) {
          case 'process':
            ok = _processes.containsKey(serviceId);
            break;
          case 'tcp':
            if (config.port != null && config.port! > 0) {
              ok = await _probePort(config.port!);
            }
            break;
          case 'http':
            if (config.port != null && config.port! > 0) {
              ok = await _probeHttp(config.port!, config.healthPath);
            }
            break;
        }
        if (!ok) {
          _appendLog(serviceId, '[health] 探活失败');
          _setStatus(serviceId, ServiceStatus.error, lastError: '探活失败');
          timer.cancel();
        }
      },
    );
  }

  void _stopHealthCheck(String serviceId) {
    _healthCheckTimers[serviceId]?.cancel();
    _healthCheckTimers.remove(serviceId);
  }

  // ============================================================
  // PID 文件（仅自定义环境）
  // ============================================================

  Future<void> _writePidFile(ServiceConfig config, int pid) async {
    if (config.runtime != 'custom') return;
    final path = await _resolvePidFilePath(config);
    if (path == null) return;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('$pid', flush: true);
    } catch (e) {
      debugPrint('[ServiceManager] write pid file failed: $e');
    }
  }

  Future<void> _deletePidFile(ServiceConfig config) async {
    if (config.runtime != 'custom') return;
    final path = await _resolvePidFilePath(config);
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  Future<String?> _resolvePidFilePath(ServiceConfig config) async {
    if (config.pidFile != null && config.pidFile!.isNotEmpty) {
      return await _resolvePlaceholders(config.pidFile!);
    }
    try {
      final dir = await PluginPaths.servicesRoot();
      return p.join(dir.path, '${config.id}.pid');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _probePidFile(ServiceConfig config) async {
    if (config.runtime != 'custom') return false;
    final path = await _resolvePidFilePath(config);
    if (path == null) return false;
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      final pid = int.tryParse((await file.readAsString()).trim());
      if (pid == null || pid <= 0) return false;
      if (Platform.isWindows) {
        final r = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
          stdoutEncoding: const SystemEncoding(),
          stderrEncoding: const SystemEncoding(),
        );
        final out = r.stdout.toString().trim();
        return out.isNotEmpty && !out.toLowerCase().contains('no tasks');
      } else if (Platform.isAndroid) {
        return Directory('/proc/$pid').existsSync();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 停止
  // ============================================================

  Future<void> stop(String serviceId) async {
    _stopHealthCheck(serviceId);
    final process = _processes.remove(serviceId);
    final config = find(serviceId);

    if (process == null) {
      _setStatus(serviceId, ServiceStatus.stopped, pid: null);
      if (config != null) await _deletePidFile(config);
      await _releasePort(serviceId);
      return;
    }

    _setStatus(serviceId, ServiceStatus.stopped, pid: null);

    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {}

    try {
      final code = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          try {
            process.kill(ProcessSignal.sigkill);
          } catch (_) {}
          return -1;
        },
      );

      // D2：sigterm 超时后已发 sigkill，再等 1 秒确认真正退出。
      // 原实现发完 sigkill 立即返回，进程可能仍在（占端口）→
      // 状态已 stopped、端口已释放，但进程活着，下次启动报"端口被占用"。
      // 修复：等 1 秒；仍杀不掉（极罕见的 D 状态进程）保留引用并标 error，
      // 让用户看到真相，而不是假装已停止。
      if (code == -1) {
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
          _appendLog(serviceId, '[warn] sigterm 超时，已通过 sigkill 结束');
        } catch (_) {
          _appendLog(
            serviceId,
            '[error] 进程未能强制结束，可能仍在占用端口',
          );
          _processes[serviceId] = process;
          await _releasePort(serviceId);
          _setStatus(
            serviceId,
            ServiceStatus.error,
            lastError: '无法终止进程',
          );
          if (config != null) {
            _emitEvent(ServiceEvent(
              serviceId: serviceId,
              serviceName: config.name,
              type: ServiceEventType.abnormalExit,
              message: '无法终止进程',
              detail: '进程可能仍占用端口，请重启应用后清理',
            ));
          }
          return;
        }
      }
    } catch (_) {}

    _appendLog(serviceId, '[proc] stopped');
    if (config != null) {
      await _deletePidFile(config);
      _emitEvent(ServiceEvent(
        serviceId: serviceId,
        serviceName: config.name,
        type: ServiceEventType.stopped,
      ));
    }
    await _releasePort(serviceId);
  }

  // ============================================================
  // 自启动 & 关闭
  // ============================================================

  Future<void> autoStartAll() async {
    _isShuttingDown = false;
    final list = getAll();
    for (final config in list) {
      try {
        // 运行时插件检查（custom 跳过）
        if (config.runtime != 'custom') {
          final runtimePlugin =
              InstallManager.instance.findInstalled(config.runtime);
          if (runtimePlugin == null || !runtimePlugin.enabled) {
            continue;
          }
        }

        // 常驻服务收养
        if (config.keepForeground) {
          bool alive = false;
          if (config.runtime == 'custom') {
            alive = await _probePidFile(config);
          } else if (config.healthType == 'tcp' && config.port != null) {
            alive = await _probePort(config.port!);
          } else if (config.healthType == 'http' && config.port != null) {
            alive = await _probeHttp(config.port!, config.healthPath);
          }
          if (alive) {
            // 收养时登记端口；若端口已被其他活跃服务占用 → 记日志 + error
            if (config.port != null && config.port! > 0) {
              final claimed = await _claimPort(config.port!, config.id);
              if (!claimed) {
                final owner = getPortOwner(config.port!);
                final ownerName =
                    owner != null ? (find(owner)?.name ?? owner) : '';
                final msg = ownerName.isNotEmpty
                    ? '端口 ${config.port} 已被服务「$ownerName」占用，收养失败'
                    : '端口 ${config.port} 已被占用，收养失败';
                _appendLog(config.id, '[error] $msg');
                _setStatus(config.id, ServiceStatus.error, lastError: msg);
                continue;
              }
            }
            _setStatus(config.id, ServiceStatus.running);
            _appendLog(config.id, '[adopt] 已收养');
            _startHealthCheck(config.id, config);
            continue;
          }
        }

        if (config.autostart) {
          await start(config.id);
        }
      } catch (e) {
        debugPrint('[ServiceManager] 自启动 ${config.id} 失败: $e');
      }
    }
  }

  Future<void> shutdown() async {
    _isShuttingDown = true;
    final list = getAll();
    for (final config in list) {
      final runtimePlugin =
          InstallManager.instance.findInstalled(config.runtime);
      final pluginActive =
          config.runtime == 'custom' ||
              (runtimePlugin != null && runtimePlugin.enabled);

      if (config.keepForeground && pluginActive) continue;

      try {
        await stop(config.id);
      } catch (_) {}
    }
    // 防御性清空端口表（stop 已逐项释放，这里兜底）
    await _portLock.synchronized(() => _portOwners.clear());
  }

  // ============================================================
  // 可执行文件解析
  // ============================================================

  /// 解析可执行文件；Android 上统一走 prepareAndroidExecutable
  Future<String?> _resolveExecutable(ServiceConfig config) async {
    final raw = await _resolveExecutableRaw(config);
    if (raw == null) return null;
    if (Platform.isAndroid) {
      return PluginPaths.prepareAndroidExecutable(raw);
    }
    return raw;
  }

  Future<String?> _resolveExecutableRaw(ServiceConfig config) async {
    // 1. 自定义 exe 优先
    if (config.executable != null && config.executable!.isNotEmpty) {
      final resolved = await _resolvePlaceholders(config.executable!);
      if (File(resolved).existsSync()) return resolved;
      return null;
    }

    // 2. 自定义环境但没填 exe → 报错
    if (config.runtime == 'custom') return null;

    // 3. 标准运行时：从 plugin.json 解析
    final installed = InstallManager.instance.findInstalled(config.runtime);
    if (installed == null) return null;
    final installPath = installed.installPath;

    final pluginJson = File(p.join(installPath, 'plugin.json'));
    if (pluginJson.existsSync()) {
      try {
        final raw = await pluginJson.readAsString();
        final j = jsonDecode(raw) as Map;

        // 特殊：python 运行时用 pyRuntime.pythonBin（binaries.android 是 musl loader，不是 python 本身）
        final pyRuntime = j['pyRuntime'];
        if (pyRuntime is Map && pyRuntime['pythonBin'] is String) {
          final rel = pyRuntime['pythonBin'] as String;
          final candidate = p.join(installPath, rel);
          if (File(candidate).existsSync()) return candidate;
        }

        final binaries = j['binaries'];
        final binariesKey = Platform.isWindows ? 'win32' : 'android';
        if (binaries is Map && binaries[binariesKey] is String) {
          final rel = binaries[binariesKey] as String;
          final candidates = [
            p.join(installPath, rel),
            p.join(installPath, 'bin', rel),
            p.join(installPath, p.basename(rel)),
            p.join(installPath, 'bin', p.basename(rel)),
          ];
          for (final c in candidates) {
            if (File(c).existsSync()) return c;
          }
        }
      } catch (_) {}
    }

    final exeName = _executableNameFor(config.runtime);
    if (exeName == null) return null;
    try {
      final entities = Directory(installPath).listSync(recursive: true);
      for (final e in entities) {
        if (e is File &&
            p.basename(e.path).toLowerCase() == exeName.toLowerCase()) {
          return e.path;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _executableNameFor(String runtimeId) {
    final ext = Platform.isWindows ? '.exe' : '';
    if (runtimeId.startsWith('nodejs')) return 'node$ext';
    if (runtimeId.startsWith('php')) return 'php$ext';
    if (runtimeId.startsWith('python')) {
      return Platform.isWindows ? 'python.exe' : 'python3.12';
    }
    if (runtimeId.startsWith('mediaProxy')) {
      return Platform.isWindows ? 'mediaProxy-win.exe' : 'mediaProxy';
    }
    return null;
  }
}
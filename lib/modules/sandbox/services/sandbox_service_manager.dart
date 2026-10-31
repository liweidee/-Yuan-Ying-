// lib/modules/sandbox/services/sandbox_service_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:synchronized/synchronized.dart';

import 'package:yuanying/modules/sandbox/models/sandbox_service.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_service_state.dart';
import 'package:yuanying/modules/sandbox/services/proot_launcher.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_service_store.dart';
import 'package:yuanying/modules/sandbox/services/service_host_bridge.dart';

/// 沙盒服务管理器
class SandboxServiceManager extends GetxService {
  SandboxServiceManager._();
  static final SandboxServiceManager instance = SandboxServiceManager._();

  final Map<String, SandboxServiceState> _states = {};
  final Map<String, Timer> _healthTimers = {};
  final Map<String, int> _restartCounts = {};
  final Map<String, Lock> _startLocks = {};
  final Map<int, String> _portOwners = {};
  final Lock _portLock = Lock();

  bool _isShuttingDown = false;

  final RxInt revision = 0.obs;

  Lock _startLockFor(String id) => _startLocks.putIfAbsent(id, () => Lock());

  SandboxServiceState stateOf(String id) =>
      _states.putIfAbsent(id, () => SandboxServiceState());

  SandboxServiceStatus statusOf(String id) =>
      _states[id]?.status ?? SandboxServiceStatus.stopped;

  bool isRunning(String id) =>
      statusOf(id) == SandboxServiceStatus.running;

  int get runningCount => _states.values
      .where((s) => s.status == SandboxServiceStatus.running)
      .length;

  void _notify() {
    revision.value++;
    _syncHostService();
  }

  // ============================================================
  // 端口锁
  // ============================================================
  Future<bool> _claimPort(int port, String serviceId) async {
    return await _portLock.synchronized(() {
      _portOwners.removeWhere((p, owner) => owner == serviceId && p != port);
      final owner = _portOwners[port];
      if (owner != null && owner != serviceId) {
        final ownerStatus = statusOf(owner);
        if (ownerStatus == SandboxServiceStatus.running ||
            ownerStatus == SandboxServiceStatus.starting) {
          return false;
        }
      }
      _portOwners[port] = serviceId;
      return true;
    });
  }

  Future<void> _releasePort(String serviceId) async {
    await _portLock.synchronized(() {
      _portOwners.removeWhere((port, owner) => owner == serviceId);
    });
  }

  String? getPortOwner(int port) => _portOwners[port];

  // ============================================================
  // 前台服务同步
  // ============================================================
  void _syncHostService() {
    if (_isShuttingDown) return;
    final pids = <int>[];
    int running = 0;
    for (final entry in _states.entries) {
      final st = entry.value;
      if (st.status == SandboxServiceStatus.running ||
          st.status == SandboxServiceStatus.starting) {
        if (st.pid != null) pids.add(st.pid!);
        if (st.status == SandboxServiceStatus.running) running++;
      }
    }
    if (pids.isEmpty) {
      ServiceHostBridge.instance.stopAll();
    } else {
      ServiceHostBridge.instance.sync(pids: pids, serviceCount: running);
    }
  }

  // ============================================================
  // 启动
  // ============================================================
  Future<void> start(
    SandboxService service, {
    required String distroId,
    SandboxHealthType healthType = SandboxHealthType.process,
    String healthPath = '/',
    int maxRestart = 1,
  }) async {
    await _startLockFor(service.id).synchronized(() async {
      await _startInternal(
        service,
        distroId: distroId,
        healthType: healthType,
        healthPath: healthPath,
        maxRestart: maxRestart,
      );
    });
  }

  Future<void> _startInternal(
    SandboxService service, {
    required String distroId,
    required SandboxHealthType healthType,
    required String healthPath,
    required int maxRestart,
  }) async {
    final st = stateOf(service.id);
    if (st.status == SandboxServiceStatus.running ||
        st.status == SandboxServiceStatus.starting) {
      return;
    }

    if (service.port != null && service.port! > 0) {
      final claimed = await _claimPort(service.port!, service.id);
      if (!claimed) {
        final owner = getPortOwner(service.port!);
        final msg = owner != null
            ? '端口 ${service.port} 已被服务「$owner」占用'
            : '端口 ${service.port} 已被占用';
        st.status = SandboxServiceStatus.error;
        st.lastError = msg;
        st.appendLog('[error] $msg');
        _notify();
        throw Exception(msg);
      }
    }

    st.status = SandboxServiceStatus.starting;
    st.lastError = null;
    st.appendLog('[start] ${service.command}');
    _notify();

    try {
      final env = await ProotLauncher.resolve(distroId);
      if (env == null) {
        throw Exception('PRoot 插件未安装或已损坏');
      }

      final process = await Process.start(
        env.prootExec,
        ProotLauncher.buildArgs(env, ['/bin/sh', '-c', service.command]),
        environment: ProotLauncher.buildEnv(env),
      );

      st.process = process;
      st.pid = process.pid;
      st.startedAtMs = DateTime.now().millisecondsSinceEpoch;
      st.appendLog('[proc] pid=${process.pid}');
      _notify();

      const decoder = Utf8Decoder(allowMalformed: true);
      process.stdout
          .transform(decoder)
          .transform(const LineSplitter())
          .listen((line) {
        st.appendLog(line);
        _notify();
      });
      process.stderr
          .transform(decoder)
          .transform(const LineSplitter())
          .listen((line) {
        st.appendLog('[err] $line');
        _notify();
      });

      final startedProcess = process;
      startedProcess.exitCode.then((code) {
        if (st.process != startedProcess) return;
        st.appendLog('[proc] exited ($code)');
        st.process = null;
        st.pid = null;
        st.status = SandboxServiceStatus.stopped;
        _stopHealthCheck(service.id);
        _releasePort(service.id);
        _notify();

        if (_isShuttingDown) return;
        final rc = _restartCounts[service.id] ?? 0;
        if (rc >= maxRestart) {
          st.appendLog('[state] 已达重启上限，不再重启');
          st.status = SandboxServiceStatus.error;
          st.lastError = '进程异常退出（code=$code）';
          _notify();
          return;
        }
        _restartCounts[service.id] = rc + 1;
        st.appendLog('[restart] 第 ${rc + 1} 次重启');
        Future.delayed(const Duration(seconds: 2), () {
          if (_isShuttingDown) return;
          start(
            service,
            distroId: distroId,
            healthType: healthType,
            healthPath: healthPath,
            maxRestart: maxRestart,
          ).catchError((e) =>
              debugPrint('[SandboxServiceManager] restart: $e'));
        });
      });

      await _waitForReady(service, st, process,
          healthType: healthType, healthPath: healthPath);

      st.status = SandboxServiceStatus.running;
      st.appendLog('[health] ready');
      _startHealthCheck(service, distroId,
          healthType: healthType, healthPath: healthPath);
      _notify();
    } catch (e) {
      st.status = SandboxServiceStatus.error;
      st.lastError = e.toString();
      st.appendLog('[error] $e');
      _releasePort(service.id);
      _notify();
      rethrow;
    }
  }

  Future<void> _waitForReady(
    SandboxService service,
    SandboxServiceState st,
    Process process, {
    required SandboxHealthType healthType,
    required String healthPath,
  }) async {
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (st.process == null) {
        throw Exception('进程已退出');
      }
      bool ok = false;
      switch (healthType) {
        case SandboxHealthType.process:
          ok = st.process != null;
          break;
        case SandboxHealthType.tcp:
          if (service.port != null) {
            ok = await _probeTcp(service.port!);
          }
          break;
        case SandboxHealthType.http:
          if (service.port != null) {
            ok = await _probeHttp(service.port!, healthPath);
          }
          break;
      }
      if (ok) return;
    }
    throw Exception('探活超时（15 秒）');
  }

  void _startHealthCheck(
    SandboxService service,
    String distroId, {
    required SandboxHealthType healthType,
    required String healthPath,
  }) {
    _stopHealthCheck(service.id);
    _healthTimers[service.id] = Timer.periodic(
      const Duration(seconds: 5),
      (t) async {
        final st = _states[service.id];
        if (st == null || st.status != SandboxServiceStatus.running) {
          t.cancel();
          return;
        }
        bool ok = false;
        switch (healthType) {
          case SandboxHealthType.process:
            ok = st.process != null;
            break;
          case SandboxHealthType.tcp:
            if (service.port != null) ok = await _probeTcp(service.port!);
            break;
          case SandboxHealthType.http:
            if (service.port != null) {
              ok = await _probeHttp(service.port!, healthPath);
            }
            break;
        }
        if (!ok) {
          st.appendLog('[health] 探活失败');
          st.status = SandboxServiceStatus.error;
          st.lastError = '探活失败';
          t.cancel();
          _notify();
        }
      },
    );
  }

  void _stopHealthCheck(String id) {
    _healthTimers[id]?.cancel();
    _healthTimers.remove(id);
  }

  Future<bool> _probeTcp(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 800));
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
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final resp = await req.close();
      client.close(force: true);
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 停止
  // ============================================================
  Future<void> stop(String id) async {
    _stopHealthCheck(id);
    final st = _states[id];
    if (st == null) return;
    final proc = st.process;
    if (proc == null) {
      st.status = SandboxServiceStatus.stopped;
      _releasePort(id);
      _notify();
      return;
    }
    st.appendLog('[stop] sigterm pid=${st.pid}');
    try {
      proc.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      await proc.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          try {
            proc.kill(ProcessSignal.sigkill);
          } catch (_) {}
          return -1;
        },
      );
    } catch (_) {}
    st.process = null;
    st.pid = null;
    st.status = SandboxServiceStatus.stopped;
    _releasePort(id);
    _notify();
  }

  Future<void> stopAll() async {
    final ids = _states.keys.toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  Future<void> remove(String id) async {
    await stop(id);
    _states.remove(id);
    _restartCounts.remove(id);
    _startLocks.remove(id);
    _notify();
  }

  Future<void> autoStartAll(String distroId) async {
    final services = SandboxServiceStore.getAll();
    for (final svc in services) {
      if (!svc.autostart) continue;
      if (isRunning(svc.id)) continue;
      try {
        final healthType = (svc.port != null && svc.port! > 0)
            ? SandboxHealthType.tcp
            : SandboxHealthType.process;
        await start(
          svc,
          distroId: distroId,
          healthType: healthType,
          healthPath: '/',
          maxRestart: 1,
        );
      } catch (e) {
        debugPrint('[SandboxServiceManager] autostart ${svc.id} failed: $e');
      }
    }
  }

  Future<void> shutdown() async {
    _isShuttingDown = true;
    final ids = _states.keys.toList();
    for (final id in ids) {
      try {
        await stop(id);
      } catch (_) {}
    }
    await _portLock.synchronized(() => _portOwners.clear());
  }

  @override
  void onClose() {
    for (final t in _healthTimers.values) {
      t.cancel();
    }
    _healthTimers.clear();
    super.onClose();
  }
}
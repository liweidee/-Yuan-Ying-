// lib/modules/sandbox/services/shell_session.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:yuanying/modules/sandbox/services/proot_launcher.dart';

/// 沙盒 Shell 会话（基于 Process.start，稳定优于 Pty）
///
/// 特性：
///  - /bin/sh -l 长驻，stdin 持续写入，stdout/stderr 逐块流出
///  - cd / 环境变量 / 已装软件全程保持
///  - 无 tty，不支持 vim/top 等全屏交互程序，但满足安装软件 + 跑服务
///
/// 生命周期：
///  - start()  → 创建 proot + /bin/sh -l
///  - write()  → 向 stdin 写入命令（末尾自动补 \n 由调用方负责）
///  - kill()   → SIGTERM，2 秒后 SIGKILL 兜底
///  - dispose()→ 关闭流
class ShellSession {
  final Process _process;
  final void Function(String chunk) onOutput;

  /// 退出回调：退出码 + 最近 N 行 stderr（用于诊断闪退原因）
  final void Function(int exitCode, List<String> stderrTail) onExit;

  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;

  final List<String> _stderrTail = [];
  static const int _maxStderrLines = 20;

  bool _closed = false;

  ShellSession._(this._process, this.onOutput, this.onExit) {
    const decoder = Utf8Decoder(allowMalformed: true);

    _outSub = _process.stdout.transform(decoder).listen((s) {
      if (!_closed && s.isNotEmpty) onOutput(s);
    });

    _errSub = _process.stderr.transform(decoder).listen((s) {
      if (_closed || s.isEmpty) return;
      onOutput(s);
      for (final line in s.split('\n')) {
        if (line.isNotEmpty) _stderrTail.add(line);
      }
      while (_stderrTail.length > _maxStderrLines) {
        _stderrTail.removeAt(0);
      }
    });

    _process.exitCode.then((code) {
      if (_closed) return;
      _outSub?.cancel();
      _errSub?.cancel();
      _outSub = null;
      _errSub = null;
      debugPrint('[ShellSession] exit code=$code');
      onExit(code, List<String>.unmodifiable(_stderrTail));
    });
  }

  static Future<ShellSession> start({
    required String distroId,
    required void Function(String chunk) onOutput,
    required void Function(int exitCode, List<String> stderrTail) onExit,
  }) async {
    final env = await ProotLauncher.resolve(distroId);
    if (env == null) {
      throw Exception('PRoot 插件未安装或已损坏');
    }

    final process = await Process.start(
      env.prootExec,
      ProotLauncher.buildArgs(env, ['/bin/sh', '-l']),
      environment: ProotLauncher.buildEnv(env),
    );

    return ShellSession._(process, onOutput, onExit);
  }

  int get pid => _process.pid;

  void write(String data) {
    if (_closed) return;
    try {
      _process.stdin.add(utf8.encode(data));
      _process.stdin.flush().catchError((_) {});
    } catch (e) {
      debugPrint('[ShellSession] write failed: $e');
    }
  }

  void kill() {
    if (_closed) return;
    try {
      _process.kill(ProcessSignal.sigterm);
    } catch (_) {}
    Future.delayed(const Duration(seconds: 2), () {
      try {
        _process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    });
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await _process.stdin.close();
    } catch (_) {}
    kill();
    await _outSub?.cancel();
    await _errSub?.cancel();
    _outSub = null;
    _errSub = null;
  }
}
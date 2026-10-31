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
  final void Function(int exitCode) onExit;

  late final StreamSubscription<String> _outSub;
  late final StreamSubscription<String> _errSub;
  bool _closed = false;

  ShellSession._(this._process, this.onOutput, this.onExit) {
    const decoder = Utf8Decoder(allowMalformed: true);

    _outSub = _process.stdout.transform(decoder).listen((s) {
      if (!_closed && s.isNotEmpty) onOutput(s);
    });

    _errSub = _process.stderr.transform(decoder).listen((s) {
      if (!_closed && s.isNotEmpty) onOutput(s);
    });

    _process.exitCode.then((code) {
      if (_closed) return;
      debugPrint('[ShellSession] exit code=$code');
      onExit(code);
      _outSub.cancel();
      _errSub.cancel();
    });
  }

  static Future<ShellSession> start({
    required String distroId,
    required void Function(String chunk) onOutput,
    required void Function(int exitCode) onExit,
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

  /// 向 shell 写入原始字符（调用方负责补 \n）
  void write(String data) {
    try {
      _process.stdin.add(utf8.encode(data));
      _process.stdin.flush().catchError((_) {});
    } catch (e) {
      debugPrint('[ShellSession] write failed: $e');
    }
  }

  /// 优雅关闭：SIGTERM → 2 秒超时 SIGKILL
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
    await _outSub.cancel();
    await _errSub.cancel();
  }
}
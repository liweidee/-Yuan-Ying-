// lib/modules/sandbox/services/proot_launcher.dart
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_paths.dart';

/// PRoot 运行环境（解析后的绝对路径集合）
class ProotEnv {
  final String prootExec;
  final String prootLoader;
  final String binDir;
  final String rootfsDir;
  final String tmpDir;

  const ProotEnv({
    required this.prootExec,
    required this.prootLoader,
    required this.binDir,
    required this.rootfsDir,
    required this.tmpDir,
  });
}

abstract final class ProotLauncher {
  static Future<ProotEnv?> resolve(String distroId) async {
    final plugin = InstallManager.instance.findInstalled('proot');
    if (plugin == null || !plugin.enabled) return null;

    final installPath = plugin.installPath;
    final binDir = p.join(installPath, 'bin');

    final candidates = [
      p.join(binDir, 'libproot_exec.so'),
      p.join(installPath, 'libproot_exec.so'),
    ];
    String? prootExec;
    for (final c in candidates) {
      if (File(c).existsSync()) {
        prootExec = c;
        break;
      }
    }
    if (prootExec == null) return null;

    final execDir = p.dirname(prootExec);
    final prootLoader = p.join(execDir, 'libproot_loader.so');
    if (!File(prootLoader).existsSync()) return null;

    if (Platform.isAndroid) {
      const fourSuit = [
        'libproot_exec.so', 'libproot_loader.so',
        'libtalloc.so', 'libandroid-shmem.so',
      ];
      for (final name in fourSuit) {
        final path = p.join(execDir, name);
        if (File(path).existsSync()) {
          try {
            await Process.run('chmod', ['755', path]);
          } catch (e) {
            debugPrint('[ProotLauncher] chmod $path failed: $e');
          }
        }
      }

      // 补全 libtalloc.so.2 依赖（针对 CANNOT LINK EXECUTABLE 错误）
      final talloc = File(p.join(execDir, 'libtalloc.so'));
      final talloc2 = File(p.join(execDir, 'libtalloc.so.2'));
      if (talloc.existsSync() && !talloc2.existsSync()) {
        try {
          await talloc.copy(talloc2.path);
          await Process.run('chmod', ['755', talloc2.path]);
          debugPrint('[ProotLauncher] 已补 libtalloc.so.2 副本');
        } catch (e) {
          debugPrint('[ProotLauncher] 复制 libtalloc.so.2 失败: $e');
        }
      }
    }

    final rootfs = await SandboxPaths.rootfs(distroId);
    final tmp = await SandboxPaths.prootTmp();

    return ProotEnv(
      prootExec: prootExec,
      prootLoader: prootLoader,
      binDir: execDir,
      rootfsDir: rootfs.path,
      tmpDir: tmp.path,
    );
  }

  static Map<String, String> buildEnv(ProotEnv env) {
    final base = Map<String, String>.from(Platform.environment);

    // ===== 精准修复 1：清除 LD_PRELOAD =====
    // termux-exec 会通过 LD_PRELOAD 注入 execve() 钩子，与 PRoot 冲突。
    // 必须清除，否则 PRoot 无法正常拦截和重定向系统调用。
    base.remove('LD_PRELOAD');

    // ===== 精准修复 2：绕过 seccomp/ptrace 限制 =====
    // 部分 Android 内核的 seccomp 策略会阻止 PRoot 所需的 ptrace 操作。
    // 设置此变量是官方推荐的标准绕过方式。
    base['PROOT_NO_SECCOMP'] = '1';

    final existingLd = base['LD_LIBRARY_PATH'] ?? '';
    base['PROOT_TMP_DIR'] = env.tmpDir;
    base['PROOT_LOADER'] = env.prootLoader;
    base['LD_LIBRARY_PATH'] =
        existingLd.isEmpty ? env.binDir : '${env.binDir}:$existingLd';
    base['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
    base['HOME'] = '/root';
    base['TERM'] = 'xterm-256color';
    base['LANG'] = 'C.UTF-8';
    return base;
  }

  static List<String> buildArgs(ProotEnv env, List<String> innerCommand) {
    return [
      '--rootfs=${env.rootfsDir}',
      '-0',
      // ===== 精准修复 3：移除 --link2symlink =====
      // 该选项会创建指向宿主绝对路径的符号链接，在 Android 的应用私有目录下
      // 可能导致 /bin/sh 等关键链接解析失败。
      // '--link2symlink',   // <-- 已移除
      '--kill-on-exit',
      '-w', '/',
      '--bind=/dev', '--bind=/proc', '--bind=/sys',
      '--bind=/dev/urandom:/dev/random',
      '--bind=/proc/self/fd:/dev/fd',
      '--bind=/proc/self/fd/0:/dev/stdin',
      '--bind=/proc/self/fd/1:/dev/stdout',
      '--bind=/proc/self/fd/2:/dev/stderr',
      if (Platform.isAndroid) '--bind=/storage/emulated/0:/mnt/sdcard',
      ...innerCommand,
    ];
  }

  static Future<ProcessResult> runOnce({
    required String distroId,
    required List<String> command,
  }) async {
    final env = await resolve(distroId);
    if (env == null) throw Exception('PRoot 插件未安装或损坏');
    return Process.run(
      env.prootExec,
      buildArgs(env, command),
      environment: buildEnv(env),
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
  }

  static Future<({bool ok, String stdout, String stderr})> probe(
    String distroId,
  ) async {
    try {
      final env = await resolve(distroId);
      if (env == null) {
        return (
          ok: false, stdout: '',
          stderr: 'proot 环境解析失败：找不到 libproot_exec.so 或 libproot_loader.so。',
        );
      }
      final r = await Process.run(
        env.prootExec,
        buildArgs(env, ['/bin/sh', '-c', 'echo PROOT_OK && uname -m']),
        environment: buildEnv(env),
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );
      return (
        ok: r.exitCode == 0 && (r.stdout as String).contains('PROOT_OK'),
        stdout: r.stdout as String,
        stderr: r.stderr as String,
      );
    } catch (e) {
      return (ok: false, stdout: '', stderr: e.toString());
    }
  }
}
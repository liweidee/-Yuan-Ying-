// lib/modules/sandbox/services/proot_launcher.dart
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_paths.dart';

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

    if (Platform.isAndroid) {
      await _ensureBusyboxCommands(rootfs);
    }

    return ProotEnv(
      prootExec: prootExec,
      prootLoader: prootLoader,
      binDir: execDir,
      rootfsDir: rootfs.path,
      tmpDir: tmp.path,
    );
  }

  static Future<void> _ensureBusyboxCommands(Directory rootfs) async {
    final busybox = File(p.join(rootfs.path, 'bin', 'busybox'));
    if (!busybox.existsSync()) {
      debugPrint('[ProotLauncher] /bin/busybox 不存在，无法补全命令');
      return;
    }

    final busyboxBytes = await busybox.readAsBytes();
    const dirs = ['bin', 'sbin', 'usr/bin', 'usr/sbin'];
    const keyCommands = [
      'sh', 'ash',
      'cat', 'ls', 'mkdir', 'rm', 'cp', 'mv', 'ln', 'touch',
      'chmod', 'chown',
      'env', 'echo', 'printf', 'true', 'false',
      'ps', 'kill',
    ];
    int fixed = 0;

    for (final dirName in dirs) {
      final dir = Directory(p.join(rootfs.path, dirName));
      if (!dir.existsSync()) continue;

      for (final cmd in keyCommands) {
        final file = File(p.join(dir.path, cmd));
        final link = Link(p.join(dir.path, cmd));

        if (file.existsSync() && !link.existsSync()) continue;

        try {
          if (link.existsSync()) await link.delete();
          await file.writeAsBytes(busyboxBytes);
          await Process.run('chmod', ['755', file.path]);
          fixed++;
        } catch (e) {
          debugPrint('[ProotLauncher] 补全 $dirName/$cmd 失败: $e');
        }
      }
    }

    if (fixed > 0) {
      debugPrint('[ProotLauncher] 已补全 $fixed 个 busybox 实体命令');
    }
  }

  static Map<String, String> buildEnv(ProotEnv env) {
    final base = Map<String, String>.from(Platform.environment);
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
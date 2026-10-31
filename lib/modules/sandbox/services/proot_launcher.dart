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

/// PRoot 启动器
abstract final class ProotLauncher {
  /// 解析 PRoot 环境（要求 proot 插件已安装）
  ///
  /// 返回 null 表示：
  ///  - 插件未安装 / 已禁用
  ///  - .so 文件不存在（安装损坏）
  ///
  /// 副作用（Android）：
  ///  - 幂等 chmod 755 四件套（exec / loader / talloc / shmem）
  ///    插件安装时 archive 不保留可执行位，必须在这里补
  static Future<ProotEnv?> resolve(String distroId) async {
    final plugin = InstallManager.instance.findInstalled('proot');
    if (plugin == null || !plugin.enabled) return null;

    final installPath = plugin.installPath;
    final binDir = p.join(installPath, 'bin');

    // 兼容两种布局：installPath/bin/libproot_exec.so 或 installPath/libproot_exec.so
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

    // loader 与 exec 同目录
    final execDir = p.dirname(prootExec);
    final prootLoader = p.join(execDir, 'libproot_loader.so');
    if (!File(prootLoader).existsSync()) return null;

    // 幂等 chmod 四件套
    // archive 包解压时不保留可执行位，Process.start 会 EACCES
    if (Platform.isAndroid) {
      const fourSuit = [
        'libproot_exec.so',
        'libproot_loader.so',
        'libtalloc.so',
        'libandroid-shmem.so',
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

  /// 构建 PRoot 环境变量
  ///
  /// Dart Process.start 的 environment 是「完全替换」语义（不合并），
  /// 因此必须显式拷贝宿主 Platform.environment，否则 proot 内部
  /// 拿不到 ANDROID_ROOT / TMPDIR 等关键变量，部分 ROM 上 dlopen 会失败。
  static Map<String, String> buildEnv(ProotEnv env) {
    final base = Map<String, String>.from(Platform.environment);
    final existingLd = base['LD_LIBRARY_PATH'] ?? '';
    base['PROOT_TMP_DIR'] = env.tmpDir;
    base['PROOT_LOADER'] = env.prootLoader;
    base['LD_LIBRARY_PATH'] =
        existingLd.isEmpty ? env.binDir : '${env.binDir}:$existingLd';
    // 以下变量只在 rootfs 内生效（proot chroot 后 exec /bin/sh）
    base['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
    base['HOME'] = '/root';
    base['TERM'] = 'xterm-256color';
    base['LANG'] = 'C.UTF-8';
    return base;
  }

  /// 构建 PRoot 启动参数
  ///
  /// --kill-on-exit：proot 主进程正常退出（含 SIGTERM）时，
  ///                连带杀掉沙盒内所有子进程，避免漏子进程占端口。
  /// 注意：SIGKILL 场景无法捕获，此选项不生效——上层必须用 SIGTERM 停服务。
  static List<String> buildArgs(ProotEnv env, List<String> innerCommand) {
    return [
      '--rootfs=${env.rootfsDir}',
      '-0',
      '--link2symlink',
      '--kill-on-exit',
      '-w',
      '/',
      '--bind=/dev',
      '--bind=/proc',
      '--bind=/sys',
      '--bind=/dev/urandom:/dev/random',
      '--bind=/proc/self/fd:/dev/fd',
      '--bind=/proc/self/fd/0:/dev/stdin',
      '--bind=/proc/self/fd/1:/dev/stdout',
      '--bind=/proc/self/fd/2:/dev/stderr',

      // sdcard 桥接
      // /storage/emulated/0 对普通 App 在 Android 11+ 需要 MANAGE_EXTERNAL_STORAGE，
      // 但即使未授权 bind 也会成功（只是空目录），不会让 proot 崩，
      // 用户进入后 ls 发现是空的就知道要去授权。
      if (Platform.isAndroid)
        '--bind=/storage/emulated/0:/mnt/sdcard',

      ...innerCommand,
    ];
  }

  /// 一次性执行（探活 / 装软件）
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

  /// 探测：用最小命令验证 PRoot 能跑（首次启动前用）
  static Future<({bool ok, String stdout, String stderr})> probe(
    String distroId,
  ) async {
    try {
      final r = await runOnce(
        distroId: distroId,
        command: ['/bin/sh', '-c', 'echo PROOT_OK && uname -m'],
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
// lib/modules/sandbox/services/rootfs_manager.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/sandbox/models/rootfs_progress.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_paths.dart';

/// 发行版元信息
class DistroInfo {
  final String id;
  final String name;
  final String version;
  final int sizeBytes;
  final List<({String label, String url})> mirrors;

  const DistroInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.sizeBytes,
    required this.mirrors,
  });
}

/// 内置发行版（arm64 专用）
const kDistros = <DistroInfo>[
  DistroInfo(
    id: 'alpine',
    name: 'Alpine',
    version: '3.22.7',
    sizeBytes: 3_500_000,
    mirrors: [
      (
        label: '华为云',
        url:
            'https://mirrors.huaweicloud.com/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.7-aarch64.tar.gz',
      ),
      (
        label: '清华',
        url:
            'https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.7-aarch64.tar.gz',
      ),
      (
        label: '官方',
        url:
            'https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.7-aarch64.tar.gz',
      ),
    ],
  ),
  DistroInfo(
    id: 'ubuntu',
    name: 'Ubuntu',
    version: '24.04.3',
    sizeBytes: 30_000_000,
    mirrors: [
      (
        label: '清华',
        url:
            'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04.3/release/ubuntu-base-24.04.3-base-arm64.tar.gz',
      ),
      (
        label: '官方',
        url:
            'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.3/release/ubuntu-base-24.04.3-arm64.tar.gz',
      ),
    ],
  ),
];

/// 用户取消异常
class RootfsCancelledException implements Exception {
  @override
  String toString() => '已取消';
}

/// Rootfs 管理器
class RootfsManager {
  RootfsManager._();
  static final RootfsManager instance = RootfsManager._();

  /// 安装 rootfs
  ///
  /// [onProgress] 阶段与进度回调（必传，供 UI 渲染进度对话框）
  /// [cancelToken] 用于取消下载
  ///
  /// 流程：
  ///  1. 检查缓存（若已下完整包则跳过下载）
  ///  2. 多镜像顺序尝试下载（失败自动切下一个）
  ///  3. 清空旧 rootfs + 解压
  ///  4. 修复权限
  ///  5. 配置 DNS 与软件源
  ///  6. 写 marker（含 installedAt 供多 distro 场景排序）
  Future<void> install(
    DistroInfo distro, {
    required void Function(RootfsProgress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();

    void emit(RootfsStage stage, {int r = 0, int t = 0, String? detail}) {
      onProgress(RootfsProgress(
        stage: stage,
        received: r,
        total: t,
        detail: detail,
      ));
    }

    // ============================================================
    // 1. 检查缓存
    // ============================================================
    emit(RootfsStage.checking);
    final cache = await SandboxPaths.cache();
    final tgz = File(p.join(cache.path, '${distro.id}.tar.gz'));

    final cachedOk = tgz.existsSync() &&
        await tgz.length() >= (distro.sizeBytes * 0.8).round();

    // ============================================================
    // 2. 下载（多镜像 fallback）
    // ============================================================
    if (!cachedOk) {
      if (tgz.existsSync()) {
        try {
          await tgz.delete();
        } catch (_) {}
      }

      DioException? lastDioError;
      Exception? lastError;
      bool downloaded = false;

      for (int i = 0; i < distro.mirrors.length; i++) {
        final mirror = distro.mirrors[i];
        final tag = i == 0 ? '' : '（切换镜像 ${mirror.label}）';
        emit(RootfsStage.downloading, detail: '从 ${mirror.label} 下载$tag');

        try {
          await _download(
            mirror.url,
            tgz,
            token,
            (received, total) {
              // 若服务器未给 Content-Length，用 distro.sizeBytes 作为估算，
              // 这样进度条也能动起来
              final effectiveTotal = total > 0 ? total : distro.sizeBytes;
              emit(
                RootfsStage.downloading,
                r: received,
                t: effectiveTotal,
                detail: '从 ${mirror.label} 下载',
              );
            },
          );
          downloaded = true;
          break;
        } on RootfsCancelledException {
          try {
            await tgz.delete();
          } catch (_) {}
          rethrow;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) {
            try {
              await tgz.delete();
            } catch (_) {}
            throw RootfsCancelledException();
          }
          lastDioError = e;
          debugPrint('[RootfsManager] mirror ${mirror.label} failed: $e');
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          debugPrint('[RootfsManager] mirror ${mirror.label} failed: $e');
        }
      }

      if (!downloaded) {
        throw lastDioError ?? lastError ?? Exception('所有镜像均下载失败');
      }
    }

    // ============================================================
    // 3. 清空旧 rootfs + 解压
    // ============================================================
    emit(RootfsStage.extracting);
    // 让 UI 有机会渲染"正在解压"再开始（避免同步阻塞感知）
    await Future.delayed(const Duration(milliseconds: 80));

    final rootfsDir = await SandboxPaths.rootfs(distro.id);
    final marker = await SandboxPaths.installedMarker(distro.id);
    if (marker.existsSync()) {
      try {
        await marker.delete();
      } catch (_) {}
    }

    // 清空旧内容
    final entries = await rootfsDir.list().toList();
    for (final e in entries) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }

    try {
      await _extractTarGz(tgz, rootfsDir);
    } catch (e) {
      try {
        await tgz.delete();
      } catch (_) {}
      throw Exception('解压失败：$e');
    }

    // ============================================================
    // 4. 修复权限
    // ============================================================
    emit(RootfsStage.fixingPerms);
    await _fixPermissions(rootfsDir);

    // ============================================================
    // 5. 配置网络
    // ============================================================
    emit(RootfsStage.configuring);
    await _setupNetwork(distro, rootfsDir);

    // ============================================================
    // 6. 写 marker
    // ============================================================
    await marker.writeAsString(
      jsonEncode({
        'id': distro.id,
        'name': distro.name,
        'version': distro.version,
        'installedAt': DateTime.now().toIso8601String(),
      }),
    );

    try {
      await tgz.delete();
    } catch (_) {}

    emit(RootfsStage.done);
  }

  /// 卸载 rootfs
  Future<void> uninstall(String distroId) async {
    final rootfs = await SandboxPaths.rootfs(distroId);
    if (rootfs.existsSync()) {
      try {
        await _chmodRecursive(rootfs.path, '755');
      } catch (_) {}
      await rootfs.delete(recursive: true);
    }
    final marker = await SandboxPaths.installedMarker(distroId);
    if (marker.existsSync()) await marker.delete();
  }

  Future<bool> isInstalled(String distroId) async {
    return (await SandboxPaths.installedMarker(distroId)).existsSync();
  }

  Future<Map<String, dynamic>?> readMarker(String distroId) async {
    final f = await SandboxPaths.installedMarker(distroId);
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 返回当前激活的 distro（按 installedAt 最新）
  Future<String?> currentInstalledDistro() async {
    String? latestId;
    DateTime? latestTime;
    for (final d in kDistros) {
      final marker = await SandboxPaths.installedMarker(d.id);
      if (!marker.existsSync()) continue;
      try {
        final json = jsonDecode(await marker.readAsString()) as Map;
        final installedAt = json['installedAt']?.toString();
        final t = installedAt != null
            ? (DateTime.tryParse(installedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0))
            : DateTime.fromMillisecondsSinceEpoch(0);
        if (latestTime == null || t.isAfter(latestTime)) {
          latestTime = t;
          latestId = d.id;
        }
      } catch (_) {}
    }
    return latestId;
  }

  // ============================================================
  // 下载（手动 stream，保证即使无 Content-Length 也有进度）
  // ============================================================
  Future<void> _download(
    String url,
    File target,
    CancelToken cancelToken,
    void Function(int received, int total) onProgress,
  ) async {
    final dio = HttpClientFactory.dio;
    final resp = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 400,
        receiveTimeout: const Duration(minutes: 5),
      ),
      cancelToken: cancelToken,
    );

    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final contentLength = int.tryParse(
          resp.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;

    final sink = target.openWrite();
    int received = 0;
    try {
      await for (final chunk in resp.data!.stream) {
        if (cancelToken.isCancelled) {
          throw RootfsCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, contentLength);
      }
    } finally {
      try {
        await sink.flush();
        await sink.close();
      } catch (_) {}
    }

    if (received < 1024) {
      // 极端情况：拿到空包
      throw Exception('下载内容为空');
    }
  }

  // ============================================================
  // 网络配置（DNS + 软件源）
  // ============================================================
  Future<void> _setupNetwork(DistroInfo distro, Directory rootfs) async {
    final resolv = File(p.join(rootfs.path, 'etc/resolv.conf'));
    await resolv.parent.create(recursive: true);
    if (resolv.existsSync()) {
      try {
        await resolv.delete();
      } catch (_) {}
    }
    await resolv.writeAsString(
      'nameserver 223.5.5.5\n'
      'nameserver 119.29.29.29\n',
    );

    switch (distro.id) {
      case 'alpine':
        await _setupAlpineRepos(distro, rootfs);
        break;
      case 'ubuntu':
        await _setupUbuntuRepos(rootfs);
        break;
      default:
        break;
    }

    final hosts = File(p.join(rootfs.path, 'etc/hosts'));
    if (!hosts.existsSync()) {
      await hosts.parent.create(recursive: true);
      await hosts.writeAsString(
        '127.0.0.1   localhost localhost.localdomain\n'
        '::1         localhost localhost.localdomain\n',
      );
    }
  }

  Future<void> _setupAlpineRepos(
    DistroInfo distro,
    Directory rootfs,
  ) async {
    final minor = _majorMinorVersion(distro.version);
    final apkRepos = File(p.join(rootfs.path, 'etc/apk/repositories'));
    if (!apkRepos.parent.existsSync()) return;
    await apkRepos.writeAsString(
      'https://mirrors.aliyun.com/alpine/v$minor/main\n'
      'https://mirrors.aliyun.com/alpine/v$minor/community\n',
    );
  }

  Future<void> _setupUbuntuRepos(Directory rootfs) async {
    const codename = 'noble';
    const mirror = 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/';

    final keyring = File(p.join(
      rootfs.path,
      'usr/share/keyrings/ubuntu-archive-keyring.gpg',
    ));
    final hasKeyring = keyring.existsSync();

    final sourcesDeb822 = File(p.join(
      rootfs.path,
      'etc/apt/sources.list.d/ubuntu.sources',
    ));
    await sourcesDeb822.parent.create(recursive: true);
    if (hasKeyring) {
      await sourcesDeb822.writeAsString('''
Types: deb
URIs: $mirror
Suites: $codename $codename-updates $codename-backports $codename-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
''');
    } else {
      await sourcesDeb822.writeAsString('''
Types: deb
URIs: $mirror
Suites: $codename $codename-updates $codename-backports $codename-security
Components: main restricted universe multiverse
Trusted: yes
''');
    }

    final sourcesList = File(p.join(rootfs.path, 'etc/apt/sources.list'));
    if (sourcesList.existsSync()) {
      await sourcesList.writeAsString(
        '# 已迁移到 /etc/apt/sources.list.d/ubuntu.sources\n',
      );
    }
  }

  String _majorMinorVersion(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return version;
  }

  // ============================================================
  // 解压
  // ============================================================
  Future<void> _extractTarGz(File tgz, Directory target) async {
    final bytes = await tgz.readAsBytes();
    final gz = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(gz);

    final normalizedTarget = p.normalize(target.path);

    for (final f in archive) {
      final outPath = p.normalize(p.join(target.path, f.name));

      if (outPath != normalizedTarget &&
          !p.isWithin(normalizedTarget, outPath)) {
        debugPrint('[RootfsManager] skip unsafe entry: ${f.name}');
        continue;
      }

      if (f.isSymbolicLink) {
        final linkTarget = f.content is String
            ? f.content as String
            : utf8.decode(f.content as List<int>, allowMalformed: true);
        try {
          final link = Link(outPath);
          await link.parent.create(recursive: true);
          if (link.existsSync()) await link.delete();
          await link.create(linkTarget, recursive: true);
        } catch (e) {
          debugPrint('[RootfsManager] symlink ${f.name} failed: $e');
        }
        continue;
      }

      if (f.isFile) {
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
        final mode = f.mode;
        if (mode != null && (mode & 0x49) != 0) {
          try {
            await Process.run('chmod', ['755', outPath]);
          } catch (e) {
            debugPrint('[RootfsManager] chmod $outPath failed: $e');
          }
        }
        continue;
      }

      await Directory(outPath).create(recursive: true);
    }
  }

  Future<void> _fixPermissions(Directory rootfs) async {
    const criticalDirs = [
      'bin', 'sbin', 'usr', 'usr/bin', 'usr/sbin', 'usr/lib',
      'usr/local', 'usr/local/bin', 'usr/share', 'etc', 'var',
      'var/lib', 'var/cache', 'tmp', 'root', 'lib', 'lib64',
      'dev', 'proc', 'sys', 'run',
    ];
    for (final rel in criticalDirs) {
      final d = Directory(p.join(rootfs.path, rel));
      if (d.existsSync()) {
        try {
          await Process.run('chmod', ['755', d.path]);
        } catch (_) {}
      }
    }

    const criticalFiles = [
      'bin/sh', 'bin/busybox', 'bin/ash', 'sbin/apk',
      'usr/bin/env', 'usr/bin/apt', 'usr/bin/apt-get',
      'usr/bin/dpkg', 'bin/dash', 'usr/bin/perl',
    ];
    for (final rel in criticalFiles) {
      final f = File(p.join(rootfs.path, rel));
      if (f.existsSync()) {
        try {
          await Process.run('chmod', ['755', f.path]);
        } catch (_) {}
      }
    }

    final tmp = Directory(p.join(rootfs.path, 'tmp'));
    if (tmp.existsSync()) {
      try {
        await Process.run('chmod', ['1777', tmp.path]);
      } catch (_) {}
    }
  }

  Future<void> _chmodRecursive(String path, String perm) async {
    try {
      await Process.run('chmod', ['-R', perm, path]);
    } catch (_) {}
  }
}
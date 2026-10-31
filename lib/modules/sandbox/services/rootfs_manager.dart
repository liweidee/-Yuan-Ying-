// lib/modules/sandbox/services/rootfs_manager.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/http/init.dart';
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
            'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.3/release/ubuntu-base-24.04.3-base-arm64.tar.gz',
      ),
    ],
  ),
];

/// Rootfs 管理器（下载 / 解压 / 权限修复 / 网络配置 / 卸载）
class RootfsManager {
  RootfsManager._();
  static final RootfsManager instance = RootfsManager._();

  /// 安装 rootfs
  Future<void> install(
    DistroInfo distro, {
    String? mirrorLabel,
    void Function(int received, int total)? onProgress,
  }) async {
    final selected = mirrorLabel != null
        ? distro.mirrors.firstWhere(
            (m) => m.label == mirrorLabel,
            orElse: () => distro.mirrors.first,
          )
        : distro.mirrors.first;

    final cache = await SandboxPaths.cache();
    final tgz = File(p.join(cache.path, '${distro.id}.tar.gz'));

    // ============================================================
    // 1. 下载
    // ============================================================
    if (!tgz.existsSync() || await tgz.length() < distro.sizeBytes * 0.8) {
      final dio = HttpClientFactory.dio;
      await dio.download(
        selected.url,
        tgz.path,
        onReceiveProgress: onProgress,
      );
    }

    // ============================================================
    // 2. 清空旧 rootfs 并解压
    //
    //  先删 marker，避免解压失败后「残留旧 marker」导致
    //   UI 误判为「已安装」但实际 rootfs 是空的、启动终端白屏。
    //   顺序：删 marker → 清空 rootfs → 解压 → 建 marker
    // ============================================================
    final rootfsDir = await SandboxPaths.rootfs(distro.id);
    final marker = await SandboxPaths.installedMarker(distro.id);

    if (marker.existsSync()) {
      try {
        await marker.delete();
      } catch (_) {}
    }

    final entries = await rootfsDir.list().toList();
    for (final e in entries) {
      await e.delete(recursive: true);
    }

    try {
      await _extractTarGz(tgz, rootfsDir);
    } catch (e) {
      // 解压失败（多半是下载中断）：删掉 tgz 让下次重新下
      try {
        await tgz.delete();
      } catch (_) {}
      rethrow;
    }

    // ============================================================
    // 3. 修复权限
    // ============================================================
    await _fixPermissions(rootfsDir);

    // ============================================================
    // 4. 配置网络（DNS + 软件源）
    //
    // Alpine / Ubuntu 基础镜像默认 /etc/resolv.conf 是
    //   nameserver 127.0.0.1 / 127.0.0.53，PRoot 环境下无对应服务 →
    //   解析域名必失败 → apk add / apt install 全挂。
    //   同时把软件源切到国内镜像，避免跨境拉包超时。
    // ============================================================
    await _setupNetwork(distro, rootfsDir);

    // ============================================================
    // 5. 写标记（含 installedAt 时间戳，供多 distro 场景排序）
    // ============================================================
    await marker.writeAsString(
      jsonEncode({
        'id': distro.id,
        'name': distro.name,
        'version': distro.version,
        'installedAt': DateTime.now().toIso8601String(),
      }),
    );

    await tgz.delete();
  }

  /// 卸载 rootfs
  Future<void> uninstall(String distroId) async {
    final rootfs = await SandboxPaths.rootfs(distroId);
    if (rootfs.existsSync()) {
      // 部分 rootfs 里目录权限 0555，先 chmod 再删
      try {
        await _chmodRecursive(rootfs.path, '755');
      } catch (_) {}
      await rootfs.delete(recursive: true);
    }
    final marker = await SandboxPaths.installedMarker(distroId);
    if (marker.existsSync()) await marker.delete();
  }

  /// 是否已安装
  Future<bool> isInstalled(String distroId) async {
    return (await SandboxPaths.installedMarker(distroId)).existsSync();
  }

  /// 读取安装标记
  Future<Map<String, dynamic>?> readMarker(String distroId) async {
    final f = await SandboxPaths.installedMarker(distroId);
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 返回当前激活的发行版 id
  ///
  /// 原实现按 `kDistros` 顺序遍历，永远先返回 alpine，
  ///   导致用户后装 Ubuntu 时仍显示 Alpine 就绪。
  ///   现改为读 marker 的 `installedAt` 时间戳，取最近安装的 distro。
  ///   - 单 distro 用户：行为不变
  ///   - 多 distro 用户：后装的生效（重装某 distro 也会刷新 installedAt 并生效）
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
      } catch (_) {
        // 脏 marker：跳过
      }
    }
    return latestId;
  }

  // ============================================================
  // 网络配置（DNS + 软件源）
  // ============================================================
  Future<void> _setupNetwork(DistroInfo distro, Directory rootfs) async {
    // ① DNS：阿里 + 腾讯公共 DNS（国内外均可解析）
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

    // ② 软件源：按 distro 分支
    switch (distro.id) {
      case 'alpine':
        await _setupAlpineRepos(distro, rootfs);
        break;
      case 'ubuntu':
        await _setupUbuntuRepos(rootfs);
        break;
      default:
        // 未知 distro：只配 DNS，源由用户自己处理
        break;
    }

    // ③ /etc/hosts 兜底（部分极简镜像为空，会导致 localhost 解析失败）
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
    // "3.22.7" → "3.22"；后续 Alpine 升级到 3.23.x 时这里也自动跟着变
    final minor = _majorMinorVersion(distro.version);

    final apkRepos = File(p.join(rootfs.path, 'etc/apk/repositories'));
    if (!apkRepos.parent.existsSync()) return;

    await apkRepos.writeAsString(
      'https://mirrors.aliyun.com/alpine/v$minor/main\n'
      'https://mirrors.aliyun.com/alpine/v$minor/community\n',
    );
  }

  Future<void> _setupUbuntuRepos(Directory rootfs) async {
    // Ubuntu 24.04 的 codename 是 noble
    // ARM 架构必须用 ubuntu-ports（x86 用 ubuntu）
    const codename = 'noble';
    const mirror = 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/';

    // ① 检查 keyring 是否存在（极简 base 镜像可能不含）
    final keyring = File(p.join(
      rootfs.path,
      'usr/share/keyrings/ubuntu-archive-keyring.gpg',
    ));
    final hasKeyring = keyring.existsSync();

    // ② 只写 DEB822（Ubuntu 24.04 官方推荐格式）
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
      // 无 keyring → 用 Trusted: yes 兜底，apt 不会报 "not signed"
      await sourcesDeb822.writeAsString('''
  Types: deb
  URIs: $mirror
  Suites: $codename $codename-updates $codename-backports $codename-security
  Components: main restricted universe multiverse
  Trusted: yes
  ''');
    }

    // ③ 清空老式 sources.list（避免 apt 读双份源导致重复）
    final sourcesList = File(p.join(rootfs.path, 'etc/apt/sources.list'));
    if (sourcesList.existsSync()) {
      await sourcesList.writeAsString(
        '# ubuntu-ports 源已迁移到 /etc/apt/sources.list.d/ubuntu.sources\n',
      );
    }
  }

  /// "3.22.7" → "3.22"；"1.0" → "1.0"；异常输入原样返回
  String _majorMinorVersion(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return version;
  }

  // ============================================================
  // 解压（symlink 安全版）
  // ============================================================
  Future<void> _extractTarGz(File tgz, Directory target) async {
    final bytes = await tgz.readAsBytes();
    final gz = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(gz);

    final normalizedTarget = p.normalize(target.path);

    for (final f in archive) {
      final outPath = p.normalize(p.join(target.path, f.name));

      // H1: Zip Slip 防护
      if (outPath != normalizedTarget &&
          !p.isWithin(normalizedTarget, outPath)) {
        debugPrint('[RootfsManager] skip unsafe entry: ${f.name}');
        continue;
      }

      // ① symlink
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
          debugPrint('[RootfsManager] create symlink ${f.name} -> '
              '$linkTarget failed: $e');
        }
        continue;
      }

      // ② 普通文件
      if (f.isFile) {
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
        // 保留可执行位（mode & 0o111）
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

      // ③ 目录
      await Directory(outPath).create(recursive: true);
    }
  }

  /// 修复关键目录与文件的权限
  Future<void> _fixPermissions(Directory rootfs) async {
    // 1. 关键目录 755（否则 cd 进去被拒）
    const criticalDirs = [
      'bin',
      'sbin',
      'usr',
      'usr/bin',
      'usr/sbin',
      'usr/lib',
      'usr/local',
      'usr/local/bin',
      'usr/share',
      'etc',
      'var',
      'var/lib',
      'var/cache',
      'tmp',
      'root',
      'lib',
      'lib64',
      'dev',
      'proc',
      'sys',
      'run',
    ];
    for (final rel in criticalDirs) {
      final d = Directory(p.join(rootfs.path, rel));
      if (d.existsSync()) {
        try {
          await Process.run('chmod', ['755', d.path]);
        } catch (_) {}
      }
    }

    // 2. 关键可执行文件 755（symlink 不在此列，它们跟随目标）
    const criticalFiles = [
      'bin/sh',
      'bin/busybox',
      'bin/ash',
      'sbin/apk',
      'usr/bin/env',
      'usr/bin/apt',
      'usr/bin/apt-get',
      'usr/bin/dpkg',
      'bin/dash',
      'usr/bin/perl',
    ];
    for (final rel in criticalFiles) {
      final f = File(p.join(rootfs.path, rel));
      if (f.existsSync()) {
        try {
          await Process.run('chmod', ['755', f.path]);
        } catch (_) {}
      }
    }

    // 3. tmp 目录可写（部分程序用 /tmp）
    final tmp = Directory(p.join(rootfs.path, 'tmp'));
    if (tmp.existsSync()) {
      try {
        await Process.run('chmod', ['1777', tmp.path]);
      } catch (_) {}
    }
  }

  /// 递归 chmod（仅卸载时使用，尽力而为）
  Future<void> _chmodRecursive(String path, String perm) async {
    try {
      await Process.run('chmod', ['-R', perm, path]);
    } catch (_) {}
  }
}
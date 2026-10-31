// lib/modules/sandbox/services/rootfs_manager.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/http/init.dart';
import 'package:yuanying/modules/sandbox/models/rootfs_progress.dart';
import 'package:yuanying/modules/sandbox/models/sandbox_pref.dart';
import 'package:yuanying/modules/sandbox/services/sandbox_paths.dart';

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

class RootfsCancelledException implements Exception {
  @override
  String toString() => '已取消';
}

/// 软件源元信息
class SoftwareSource {
  final String id;
  final String label;
  final String icon; // emoji 或短标识（UI 层转 IconData）
  const SoftwareSource(this.id, this.label, this.icon);
}

/// 各发行版支持的软件源列表
List<SoftwareSource> softwareSourcesFor(String distroId) {
  if (distroId == 'alpine') {
    return const [
      SoftwareSource('aliyun', '阿里云', 'aliyun'),
      SoftwareSource('tuna', '清华 TUNA', 'tuna'),
      SoftwareSource('huawei', '华为云', 'huawei'),
      SoftwareSource('official', '官方 CDN', 'official'),
    ];
  } else if (distroId == 'ubuntu') {
    return const [
      SoftwareSource('tuna', '清华 TUNA', 'tuna'),
      SoftwareSource('aliyun', '阿里云', 'aliyun'),
      SoftwareSource('huawei', '华为云', 'huawei'),
      SoftwareSource('official', '官方', 'official'),
    ];
  }
  return const [];
}

String softwareSourceLabel(String distroId, String id) {
  for (final s in softwareSourcesFor(distroId)) {
    if (s.id == id) return s.label;
  }
  return id;
}

class RootfsManager {
  RootfsManager._();
  static final RootfsManager instance = RootfsManager._();

  /// 安装 rootfs
  ///
  /// [mirrorLabel] null 表示 auto（全部镜像依序 fallback），
  ///               非 null 表示只用指定镜像 label（如 '华为云'）
  Future<void> install(
    DistroInfo distro, {
    required void Function(RootfsProgress) onProgress,
    CancelToken? cancelToken,
    String? mirrorLabel,
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
    // 2. 下载（按用户选择的镜像）
    // ============================================================
    if (!cachedOk) {
      if (tgz.existsSync()) {
        try {
          await tgz.delete();
        } catch (_) {}
      }

      // ★ 根据 mirrorLabel 决定候选镜像
      List<({String label, String url})> targets;
      if (mirrorLabel == null || mirrorLabel.isEmpty) {
        targets = distro.mirrors; // auto：全部尝试
      } else {
        final matched = distro.mirrors
            .where((m) => m.label == mirrorLabel)
            .toList();
        if (matched.isEmpty) {
          throw Exception('镜像「$mirrorLabel」不存在');
        }
        targets = matched;
      }

      DioException? lastDioError;
      Exception? lastError;
      bool downloaded = false;

      for (int i = 0; i < targets.length; i++) {
        final mirror = targets[i];
        // 只在 auto 模式下、且不是第一个时才提示"切换镜像"
        final tag = (mirrorLabel == null && i > 0)
            ? '（切换镜像 ${mirror.label}）'
            : '';
        emit(RootfsStage.downloading, detail: '从 ${mirror.label} 下载$tag');

        try {
          await _download(
            mirror.url,
            tgz,
            token,
            (received, total) {
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
        // 手动指定镜像失败 → 直接报错；auto 模式 → 全部失败
        final msg = mirrorLabel != null
            ? '镜像「$mirrorLabel」下载失败，请尝试其它源'
            : '所有镜像均下载失败，请检查网络';
        throw lastDioError ?? lastError ?? Exception(msg);
      }
    }

    // ============================================================
    // 3. 清空旧 rootfs + 解压
    // ============================================================
    emit(RootfsStage.extracting);
    await Future.delayed(const Duration(milliseconds: 80));

    final rootfsDir = await SandboxPaths.rootfs(distro.id);
    final marker = await SandboxPaths.installedMarker(distro.id);
    if (marker.existsSync()) {
      try {
        await marker.delete();
      } catch (_) {}
    }

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
    // 5. 配置网络（DNS + 软件源，软件源用用户偏好）
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

  /// 应用软件源（用户运行中切换）
  ///
  /// 写配置文件；不刷新索引（让调用方决定是否跑 apk/apt update）
  Future<void> applySoftwareSource(String distroId, String sourceId) async {
    final distro = kDistros.firstWhere(
      (d) => d.id == distroId,
      orElse: () => throw Exception('未知发行版：$distroId'),
    );
    final rootfs = await SandboxPaths.rootfs(distroId);
    final marker = await SandboxPaths.installedMarker(distroId);
    if (!marker.existsSync()) {
      throw Exception('rootfs 未安装');
    }

    switch (distroId) {
      case 'alpine':
        await _applyAlpineSoftwareSource(distro, rootfs, sourceId);
        break;
      case 'ubuntu':
        await _applyUbuntuSoftwareSource(rootfs, sourceId);
        break;
      default:
        throw Exception('$distroId 不支持切换软件源');
    }

    await SandboxPref.setSoftwareMirror(sourceId);
  }

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
  // 下载
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
      throw Exception('下载内容为空');
    }
  }

  // ============================================================
  // 网络配置
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

    // ★ 用偏好里保存的软件源；若没装过，按默认
    String sourceId = SandboxPref.softwareMirror;
    if (sourceId.isEmpty) {
      sourceId = SandboxPref.defaultSoftwareMirrorFor(distro.id);
    }

    switch (distro.id) {
      case 'alpine':
        await _applyAlpineSoftwareSource(distro, rootfs, sourceId);
        break;
      case 'ubuntu':
        await _applyUbuntuSoftwareSource(rootfs, sourceId);
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

  // ============================================================
  // 软件源映射表
  // ============================================================

  /// Alpine 镜像基础 URL（不含 /main /community）
  String? _alpineMirrorBase(String sourceId, String minor) {
    switch (sourceId) {
      case 'aliyun':
        return 'https://mirrors.aliyun.com/alpine/v$minor';
      case 'tuna':
        return 'https://mirrors.tuna.tsinghua.edu.cn/alpine/v$minor';
      case 'huawei':
        return 'https://mirrors.huaweicloud.com/alpine/v$minor';
      case 'official':
        return 'https://dl-cdn.alpinelinux.org/alpine/v$minor';
      default:
        return null;
    }
  }

  /// Ubuntu 镜像基础 URL（不含 codename 部分）
  String? _ubuntuMirrorBase(String sourceId) {
    switch (sourceId) {
      case 'tuna':
        return 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/';
      case 'aliyun':
        return 'https://mirrors.aliyun.com/ubuntu-ports/';
      case 'huawei':
        return 'https://mirrors.huaweicloud.com/ubuntu-ports/';
      case 'official':
        return 'http://ports.ubuntu.com/ubuntu-ports/';
      default:
        return null;
    }
  }

  Future<void> _applyAlpineSoftwareSource(
    DistroInfo distro,
    Directory rootfs,
    String sourceId,
  ) async {
    final minor = _majorMinorVersion(distro.version);
    final baseUrl = _alpineMirrorBase(sourceId, minor);
    if (baseUrl == null) {
      throw Exception('不支持的 Alpine 软件源：$sourceId');
    }
    final apkRepos = File(p.join(rootfs.path, 'etc/apk/repositories'));
    if (!apkRepos.parent.existsSync()) {
      throw Exception('rootfs 目录结构异常（etc/apk 不存在）');
    }
    await apkRepos.writeAsString(
      '$baseUrl/main\n'
      '$baseUrl/community\n',
    );
  }

  Future<void> _applyUbuntuSoftwareSource(
    Directory rootfs,
    String sourceId,
  ) async {
    final baseUrl = _ubuntuMirrorBase(sourceId);
    if (baseUrl == null) {
      throw Exception('不支持的 Ubuntu 软件源：$sourceId');
    }
    const codename = 'noble';

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
URIs: $baseUrl
Suites: $codename $codename-updates $codename-backports $codename-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
''');
    } else {
      await sourcesDeb822.writeAsString('''
Types: deb
URIs: $baseUrl
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
  // 解压 & 权限（与原实现相同）
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
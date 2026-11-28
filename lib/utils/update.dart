import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:install_plugin_v3/install_plugin_v3.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/http/init.dart';
import 'package:yuanying/utils/app_version.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 从 GitHub Releases 检查并安装更新。
abstract final class Update {
  static const _repository = 'liweidee/-Yuan-Ying-';
  static const _releasesApi =
      'https://api.github.com/repos/$_repository/releases?per_page=20';
  static const _releasesPage =
      'https://github.com/$_repository/releases/latest';
  static final _versionPattern = RegExp(
    r'^[vV]?(\d+(?:\.\d+){0,3})(?:\+(\d+))?',
  );
  static bool _checking = false;

  /// [isAuto] 为启动时的静默检查；手动检查会提示结果和错误。
  static Future<void> checkUpdate([bool isAuto = true]) async {
    if (_checking) return;
    _checking = true;
    try {
      final release = await _findLatestRelease();
      if (release == null) {
        if (!isAuto) SmartDialog.showToast('已是最新版本');
        return;
      }

      final asset = await _findTargetAsset(release.assets);
      final releaseBuild =
          release.buildNumber ?? _buildNumberFromAssetName(asset?.name);
      if (!_isNewer(
        release.version,
        releaseBuild,
        AppVersion.name,
        AppVersion.code,
      )) {
        if (!isAuto) SmartDialog.showToast('已是最新版本');
        return;
      }

      _showUpdateDialog(release, releaseBuild, asset);
    } catch (error, stackTrace) {
      debugPrint('[Update] 检查更新失败: $error\n$stackTrace');
      if (!isAuto) SmartDialog.showToast('检查更新失败，请检查网络后重试');
    } finally {
      _checking = false;
    }
  }

  static Future<_ReleaseInfo?> _findLatestRelease() async {
    final response = await HttpClientFactory.http11Dio.get<dynamic>(
      _releasesApi,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Yuanying/${AppVersion.display}',
        },
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 403) {
      throw Exception('GitHub API 请求过于频繁');
    }
    if (status != 200) {
      throw Exception('GitHub API HTTP $status');
    }

    final data = response.data;
    if (data is! List) throw const FormatException('Release 响应格式错误');

    _ReleaseInfo? latest;
    for (final item in data) {
      if (item is! Map) continue;
      if (item['draft'] == true || item['prerelease'] == true) continue;
      final parsed = _ReleaseInfo.fromJson(item);
      if (parsed == null) continue;
      if (latest == null ||
          _isNewer(
            parsed.version,
            parsed.buildNumber,
            latest.version,
            latest.buildNumber,
          )) {
        latest = parsed;
      }
    }
    return latest;
  }

  static Future<_ReleaseAsset?> _findTargetAsset(
    List<_ReleaseAsset> assets,
  ) async {
    if (assets.isEmpty) return null;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final supported = androidInfo.supportedAbis
          .map((abi) => abi.toLowerCase())
          .toList(growable: false);
      const knownAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
      final preferred = <String>{
        for (final abi in supported)
          for (final known in knownAbis)
            if (abi == known || abi.startsWith('$known-')) known,
      };

      for (final abi in preferred) {
        for (final asset in assets) {
          final name = asset.name.toLowerCase();
          if (name.endsWith('.apk') && name.contains(abi)) return asset;
        }
      }

      for (final asset in assets) {
        final name = asset.name.toLowerCase();
        if (name.endsWith('.apk') &&
            (name.contains('universal') || name.contains('all'))) {
          return asset;
        }
      }
      for (final asset in assets) {
        if (asset.name.toLowerCase().endsWith('.apk')) return asset;
      }
      return null;
    }

    final extensions = Platform.isIOS
        ? const ['.ipa']
        : Platform.isMacOS
        ? const ['.dmg']
        : Platform.isWindows
        ? const ['.exe']
        : const ['.appimage', '.deb', '.tar.gz'];
    for (final asset in assets) {
      final lower = asset.name.toLowerCase();
      if (extensions.any(lower.endsWith)) return asset;
    }
    return null;
  }

  static void _showUpdateDialog(
    _ReleaseInfo release,
    int? releaseBuild,
    _ReleaseAsset? asset,
  ) {
    SmartDialog.show(
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final notes = release.notes.isEmpty
            ? '本次更新暂无详细说明，请前往发布页查看。'
            : release.notes;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: colorScheme.surface,
          title: Row(
            children: [
              const Text('发现新版本'),
              const Spacer(),
              GestureDetector(
                onTap: SmartDialog.dismiss,
                child: Icon(Icons.close, size: 20, color: colorScheme.outline),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            height: 220,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'v${release.version}'
                    '${releaseBuild == null ? '' : '+$releaseBuild'}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '当前版本 v${AppVersion.display}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    notes,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                StorageManager.setSetting(SettingBoxKey.autoUpdate, false);
              },
              child: Text(
                '不再提醒',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: SmartDialog.dismiss,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                unawaited(_startUpdate(release, asset));
              },
              style: TextButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Text(asset == null ? '前往下载' : '立即更新'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _startUpdate(
    _ReleaseInfo release,
    _ReleaseAsset? asset,
  ) async {
    if (!Platform.isAndroid || asset == null) {
      await _openExternal(
        asset?.downloadUrl ?? release.pageUrl ?? _releasesPage,
      );
      return;
    }

    SmartDialog.showLoading(msg: '正在下载更新...');
    try {
      final tempDir = await getTemporaryDirectory();
      final safeName = p
          .basename(asset.name)
          .replaceAll(RegExp(r'[^A-Za-z0-9._+\-]'), '_');
      final file = File(p.join(tempDir.path, safeName));
      if (file.existsSync()) await file.delete();

      final response = await HttpClientFactory.http11Dio.download(
        asset.downloadUrl,
        file.path,
        options: Options(
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode != 200) {
        throw Exception('下载失败：HTTP ${response.statusCode}');
      }
      if (!file.existsSync() || file.lengthSync() == 0) {
        throw Exception('下载的 APK 文件为空');
      }

      SmartDialog.dismiss();
      final result = await InstallPlugin.install(file.path);
      if (result['isSuccess'] != true) {
        throw Exception(result['errorMessage'] ?? '安装器未能启动');
      }
    } catch (error, stackTrace) {
      SmartDialog.dismiss();
      debugPrint('[Update] 下载或安装失败: $error\n$stackTrace');
      SmartDialog.showToast('更新失败：$error');
    }
  }

  static Future<void> _openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw const FormatException('下载地址协议无效');
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('系统未能打开下载页面');
    } catch (error) {
      SmartDialog.showToast('打开下载页面失败：$error');
    }
  }

  static bool _isNewer(
    String candidateName,
    int? candidateBuild,
    String currentName,
    int? currentBuild,
  ) {
    final versionCompare = _compareVersions(candidateName, currentName);
    if (versionCompare != 0) return versionCompare > 0;
    if (candidateBuild == null) return false;
    return currentBuild == null || candidateBuild > currentBuild;
  }

  static int? _buildNumberFromAssetName(String? name) {
    if (name == null || name.isEmpty) return null;
    final match = RegExp(r'\+(\d+)').firstMatch(name);
    return int.tryParse(match?.group(1) ?? '');
  }

  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final length = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var i = 0; i < length; i++) {
      final left = i < aParts.length ? aParts[i] : 0;
      final right = i < bParts.length ? bParts[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }
}

class _ReleaseInfo {
  const _ReleaseInfo({
    required this.version,
    required this.buildNumber,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  final String version;
  final int? buildNumber;
  final String notes;
  final String? pageUrl;
  final List<_ReleaseAsset> assets;

  static _ReleaseInfo? fromJson(Map json) {
    final tag = json['tag_name']?.toString().trim() ?? '';
    final match = Update._versionPattern.firstMatch(tag);
    if (match == null) return null;

    final assets = <_ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final raw in rawAssets) {
        final asset = _ReleaseAsset.fromJson(raw);
        if (asset.downloadUrl.isNotEmpty) assets.add(asset);
      }
    }

    return _ReleaseInfo(
      version: match.group(1)!,
      buildNumber: int.tryParse(match.group(2) ?? ''),
      notes: json['body']?.toString().trim() ?? '',
      pageUrl: json['html_url']?.toString(),
      assets: assets,
    );
  }
}

class _ReleaseAsset {
  const _ReleaseAsset({
    required this.name,
    required this.downloadUrl,
  });

  final String name;
  final String downloadUrl;

  static _ReleaseAsset fromJson(dynamic raw) {
    if (raw is! Map) {
      return const _ReleaseAsset(name: '', downloadUrl: '');
    }
    return _ReleaseAsset(
      name: raw['name']?.toString() ?? '',
      downloadUrl: raw['browser_download_url']?.toString() ?? '',
    );
  }
}

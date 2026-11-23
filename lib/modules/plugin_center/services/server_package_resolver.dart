import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:yuanying/modules/plugin_center/models/market_entry.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';

class ServerPackagePlan {
  final String pluginId;
  final String serviceId;
  final String packageRoot;
  final String serviceName;
  final String description;
  final String workDir;
  final String entry;
  final String runtime;
  final String healthType;
  final String healthPath;
  final int? port;
  final bool autoStart;
  final String? marketVersion;
  final String? manifestVersion;
  final bool linkedToMarket;
  final String identitySource;
  final MarketEntry? marketEntry;

  const ServerPackagePlan({
    required this.pluginId,
    required this.serviceId,
    required this.packageRoot,
    required this.serviceName,
    required this.description,
    required this.workDir,
    required this.entry,
    required this.runtime,
    required this.healthType,
    required this.healthPath,
    required this.port,
    required this.autoStart,
    required this.marketVersion,
    required this.manifestVersion,
    required this.linkedToMarket,
    required this.identitySource,
    required this.marketEntry,
  });

  String get registryVersion => marketVersion ?? manifestVersion ?? '';
}

abstract final class ServerPackageResolver {
  static ServerPackagePlan resolve({
    required Map<dynamic, dynamic> manifest,
    required String fileName,
    required String servicesRootPath,
    MarketEntry? marketEntry,
    List<MarketEntry> marketEntries = const [],
  }) {
    final fileStem = p
        .basenameWithoutExtension(fileName)
        .toLowerCase()
        .replaceFirst(RegExp(r'\s*\(\d+\)$'), '')
        .trim();
    final rawServiceId = _normalizeCandidate(manifest['serviceId']);
    final rawId = _normalizeCandidate(manifest['id']);
    final rawPluginId = _normalizeCandidate(manifest['pluginId']);

    var linkedEntry = marketEntry;
    var identitySource = marketEntry == null ? '' : 'market';
    if (linkedEntry == null) {
      for (final candidate in [rawServiceId, rawId, rawPluginId]) {
        if (candidate == null) continue;
        linkedEntry = _findServerEntry(marketEntries, candidate);
        if (linkedEntry != null) {
          identitySource = candidate == rawServiceId
              ? 'manifest-service-id'
              : 'manifest-plugin-id';
          break;
        }
      }
    }

    linkedEntry ??= _matchServerEntryByFileName(marketEntries, fileStem);
    if (linkedEntry != null && identitySource.isEmpty) {
      identitySource = 'filename-market-match';
    }

    final pluginId =
        linkedEntry?.id ??
        rawServiceId ??
        rawId ??
        rawPluginId ??
        _stripTrailingVersion(fileStem);
    PluginPaths.ensureSafePathSegment(pluginId, '服务包插件 ID');
    if (identitySource.isEmpty) {
      identitySource = linkedEntry != null ? 'market' : 'filename';
    }

    final serviceId = 'svc-mkt-$pluginId';
    PluginPaths.ensureSafePathSegment(serviceId, '服务 ID');
    final packageRoot = p.join(servicesRootPath, serviceId);

    final entry = manifest['entry']?.toString().trim() ?? '';
    if (entry.isEmpty || !_isInside(packageRoot, p.join(packageRoot, entry))) {
      throw FormatException('server.json entry 路径非法：$entry');
    }
    final workDir = manifest['workDir']?.toString().trim() ?? '';
    final cwdPath = workDir.isEmpty
        ? packageRoot
        : p.join(packageRoot, workDir);
    if (!_isInside(packageRoot, cwdPath)) {
      throw FormatException('server.json workDir 路径越界：$workDir');
    }

    final manifestVersion = _nonEmpty(manifest['version']);
    final runtime = _resolveRuntime(
      manifest['runtime']?.toString() ?? '',
      entry,
    );
    final healthTypeRaw =
        manifest['healthType']?.toString().toLowerCase() ??
        _nestedString(manifest['healthCheck'], 'type') ??
        'process';
    final healthType = const {'process', 'tcp', 'http'}.contains(healthTypeRaw)
        ? healthTypeRaw
        : 'process';
    final healthPath =
        _nonEmpty(manifest['healthPath']) ??
        _nestedString(manifest['healthCheck'], 'path') ??
        '/';
    final port = manifest['port'] is num
        ? (manifest['port'] as num).toInt()
        : null;
    final autoStart =
        manifest['autoStart'] == true || manifest['autostart'] == true;

    return ServerPackagePlan(
      pluginId: pluginId,
      serviceId: serviceId,
      packageRoot: packageRoot,
      serviceName:
          _nonEmpty(manifest['serviceName']) ?? linkedEntry?.name ?? pluginId,
      description: _nonEmpty(manifest['desc']) ?? linkedEntry?.desc ?? '',
      workDir: workDir,
      entry: entry,
      runtime: runtime,
      healthType: healthType,
      healthPath: healthPath,
      port: port,
      autoStart: autoStart,
      marketVersion: linkedEntry?.version,
      manifestVersion: manifestVersion,
      linkedToMarket: linkedEntry != null,
      identitySource: identitySource,
      marketEntry: linkedEntry,
    );
  }

  static MarketEntry? _findServerEntry(
    List<MarketEntry> entries,
    String id,
  ) {
    for (final entry in entries) {
      if (entry.type == 'server' && entry.id == id) return entry;
    }
    return null;
  }

  static MarketEntry? _matchServerEntryByFileName(
    List<MarketEntry> entries,
    String fileStem,
  ) {
    MarketEntry? best;
    for (final entry in entries) {
      if (entry.type != 'server') continue;
      final id = entry.id.toLowerCase();
      if (fileStem == id || fileStem.startsWith('$id-')) {
        if (best == null || entry.id.length > best.id.length) {
          best = entry;
        }
      }
    }
    return best;
  }

  static String _resolveRuntime(String runtime, String entry) {
    final value = runtime.trim().toLowerCase();
    final isWindows = Platform.isWindows;
    if (value == 'php' || value == 'php-win') {
      return isWindows ? 'php-win' : 'php';
    }
    if (value == 'python' || value == 'python-win' || value == 'py') {
      return isWindows ? 'python-win' : 'python';
    }
    if (value == 'node' || value == 'nodejs' || value == 'nodejs-win') {
      return isWindows ? 'nodejs-win' : 'nodejs';
    }
    if (entry.endsWith('.php')) return isWindows ? 'php-win' : 'php';
    if (entry.endsWith('.py')) return isWindows ? 'python-win' : 'python';
    return isWindows ? 'nodejs-win' : 'nodejs';
  }

  static String? _normalizeCandidate(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text.startsWith('svc-mkt-') ? text.substring(8) : text;
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String? _nestedString(dynamic value, String key) {
    if (value is! Map) return null;
    return _nonEmpty(value[key]);
  }

  static String _stripTrailingVersion(String value) {
    final match = RegExp(
      r'^(.+?)-(?:v)?\d+(?:\.\d+)+(?:[-+][A-Za-z0-9.-]+)?$',
    ).firstMatch(value);
    final base = match?.group(1)?.trim();
    return base == null || base.isEmpty ? value : base;
  }

  static bool _isInside(String root, String candidate) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final normalizedCandidate = p.normalize(p.absolute(candidate));
    return p.isWithin(normalizedRoot, normalizedCandidate) ||
        normalizedRoot == normalizedCandidate;
  }
}

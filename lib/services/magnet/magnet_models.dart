import 'dart:convert';

enum MagnetPluginState {
  ready,
  unsupportedPlatform,
  unsupportedAbi,
  notInstalled,
  disabled,
  missingLibrary,
}

class MagnetPluginAvailability {
  final MagnetPluginState state;
  final String message;
  final String? libraryPath;
  final String? pluginVersion;

  const MagnetPluginAvailability({
    required this.state,
    required this.message,
    this.libraryPath,
    this.pluginVersion,
  });

  bool get isReady => state == MagnetPluginState.ready;
}

class MagnetFileInfo {
  final int index;
  final String name;
  final int size;
  final String? ext;
  final String? mimeType;

  const MagnetFileInfo({
    required this.index,
    required this.name,
    required this.size,
    this.ext,
    this.mimeType,
  });

  factory MagnetFileInfo.fromJson(
    Map<String, dynamic> json, {
    required int fallbackIndex,
  }) {
    final name = json['name']?.toString() ?? '';
    final dot = name.lastIndexOf('.');
    final mimeType = json['mimeType']?.toString().trim();
    return MagnetFileInfo(
      index: (json['index'] as num?)?.toInt() ?? fallbackIndex,
      name: name,
      size: (json['size'] as num?)?.toInt() ?? 0,
      ext:
          json['ext']?.toString() ??
          (dot >= 0 && dot < name.length - 1
              ? name.substring(dot + 1).toLowerCase()
              : null),
      mimeType: mimeType == null || mimeType.isEmpty ? null : mimeType,
    );
  }

  bool get isLikelyVideo {
    if (mimeType?.toLowerCase().startsWith('video/') == true) {
      return true;
    }
    const videoExts = {
      'mp4',
      'mkv',
      'avi',
      'mov',
      'm4v',
      'ts',
      'm2ts',
      'flv',
      'webm',
      'wmv',
      'rmvb',
      'rm',
      'mpg',
      'mpeg',
      'strm',
    };
    final dot = name.lastIndexOf('.');
    final inferredExt = dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1)
        : null;
    final value = (ext ?? inferredExt)?.toLowerCase();
    return value != null && videoExts.contains(value);
  }
}

class MagnetTaskSnapshot {
  static const empty = MagnetTaskSnapshot(
    state: '',
    error: '',
    infoHash: null,
    url: null,
    files: <MagnetFileInfo>[],
    progress: 0,
    completed: 0,
    total: 0,
    downRate: 0,
    upRate: 0,
    peers: 0,
    seeders: 0,
  );

  final String state;
  final String error;
  final String? infoHash;
  final String? url;
  final List<MagnetFileInfo> files;
  final double progress;
  final int completed;
  final int total;
  final int downRate;
  final int upRate;
  final int peers;
  final int seeders;

  const MagnetTaskSnapshot({
    required this.state,
    required this.error,
    required this.infoHash,
    required this.url,
    required this.files,
    required this.progress,
    required this.completed,
    required this.total,
    required this.downRate,
    required this.upRate,
    required this.peers,
    required this.seeders,
  });

  factory MagnetTaskSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = <MagnetFileInfo>[];
    if (rawFiles is List) {
      for (var i = 0; i < rawFiles.length; i++) {
        final value = rawFiles[i];
        if (value is Map) {
          files.add(
            MagnetFileInfo.fromJson(
              value.cast<String, dynamic>(),
              fallbackIndex: i,
            ),
          );
        }
      }
    }
    return MagnetTaskSnapshot(
      state: json['state']?.toString() ?? '',
      error: json['error']?.toString() ?? '',
      infoHash: _nonEmpty(json['infoHash']),
      url: _nonEmpty(json['url']),
      files: files,
      progress: (json['progress'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      downRate: (json['downRate'] as num?)?.toInt() ?? 0,
      upRate: (json['upRate'] as num?)?.toInt() ?? 0,
      peers: (json['peers'] as num?)?.toInt() ?? 0,
      seeders: (json['seeders'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isError => state == 'error' || error.isNotEmpty;
  bool get isReady => state == 'ready' && files.isNotEmpty;
  bool get hasUrl => url != null && url!.isNotEmpty;

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text;
  }
}

class MagnetExpansion {
  final String originalMagnet;
  final String infoHash;
  final List<MagnetFileInfo> files;

  const MagnetExpansion({
    required this.originalMagnet,
    required this.infoHash,
    required this.files,
  });
}

class MagnetPlaybackSession {
  final String ownerTag;
  final int playTaskId;
  final String infoHash;
  final MagnetFileInfo file;
  final String? originalMagnet;
  final bool deleteMediaOnStop;

  const MagnetPlaybackSession({
    required this.ownerTag,
    required this.playTaskId,
    required this.infoHash,
    required this.file,
    required this.originalMagnet,
    required this.deleteMediaOnStop,
  });
}

class MagnetPlaybackResult {
  final String streamUrl;
  final MagnetPlaybackSession session;

  const MagnetPlaybackResult({
    required this.streamUrl,
    required this.session,
  });
}

class MagnetPlaybackStatus {
  final String ownerTag;
  final String state;
  final String fileName;
  final String infoHash;
  final double progress;
  final int completed;
  final int total;
  final int downRate;
  final int upRate;
  final int peers;
  final int seeders;
  final String error;

  const MagnetPlaybackStatus({
    required this.ownerTag,
    required this.state,
    required this.fileName,
    required this.infoHash,
    required this.progress,
    required this.completed,
    required this.total,
    required this.downRate,
    required this.upRate,
    required this.peers,
    required this.seeders,
    required this.error,
  });

  factory MagnetPlaybackStatus.fromSession(
    MagnetPlaybackSession session, {
    String? state,
    MagnetTaskSnapshot? snapshot,
  }) {
    return MagnetPlaybackStatus(
      ownerTag: session.ownerTag,
      state: state ?? snapshot?.state ?? 'starting',
      fileName: session.file.name,
      infoHash: session.infoHash,
      progress: snapshot?.progress ?? 0,
      completed: snapshot?.completed ?? 0,
      total: snapshot?.total ?? session.file.size,
      downRate: snapshot?.downRate ?? 0,
      upRate: snapshot?.upRate ?? 0,
      peers: snapshot?.peers ?? 0,
      seeders: snapshot?.seeders ?? 0,
      error: snapshot?.error ?? '',
    );
  }

  bool get isStarting => state == 'starting';
  bool get isError => state == 'error' || error.isNotEmpty;
  bool get isComplete => total > 0 && (progress >= 0.999 || completed >= total);
}

class MagnetUriRef {
  final String infoHash;
  final int fileIndex;
  final String? originalMagnet;
  final String? fileName;

  const MagnetUriRef({
    required this.infoHash,
    required this.fileIndex,
    this.originalMagnet,
    this.fileName,
  });
}

abstract final class MagnetUri {
  static const scheme = 'magnetplay';
  static const verifiedFallbackTracker =
      'https://tracker.opentrackr.org:443/announce';

  static bool isMagnet(String? value) {
    return value != null && value.trim().toLowerCase().startsWith('magnet:?');
  }

  /// DsPlayer receives source links that occasionally contain only a btih.
  /// Add one verified HTTP tracker for those links so peer discovery remains
  /// usable when the current network blocks DHT UDP. Explicit trackers are
  /// never modified.
  static String ensureFallbackTracker(String value) {
    final magnet = value.trim();
    if (!isMagnet(magnet) ||
        RegExp(r'[?&]tr=', caseSensitive: false).hasMatch(magnet)) {
      return magnet;
    }
    final separator = magnet.endsWith('&') || magnet.endsWith('?') ? '' : '&';
    return '$magnet${separator}tr=${Uri.encodeQueryComponent(
      verifiedFallbackTracker,
    )}';
  }

  static bool isMagnetPlay(String? value) {
    if (value == null || value.isEmpty) return false;
    return Uri.tryParse(value)?.scheme.toLowerCase() == scheme;
  }

  static bool isMagnetSource(String? value) {
    return isMagnet(value) || isMagnetPlay(value);
  }

  static String? infoHashFromMagnet(String magnet) {
    final uri = Uri.tryParse(magnet.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'magnet') return null;
    final values = uri.queryParametersAll['xt'] ?? const <String>[];
    for (final value in values) {
      final lower = value.toLowerCase();
      if (!lower.startsWith('urn:btih:')) continue;
      final raw = value.substring('urn:btih:'.length).trim();
      final normalized = _normalizeInfoHash(raw);
      if (normalized != null) return normalized;
    }
    return null;
  }

  static String? displayNameFromMagnet(String magnet) {
    final value = Uri.tryParse(magnet.trim())?.queryParameters['dn']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String build({
    required String infoHash,
    required int fileIndex,
    String? originalMagnet,
    String? fileName,
  }) {
    return Uri(
      scheme: scheme,
      host: infoHash.toLowerCase(),
      path: '/$fileIndex',
      queryParameters: {
        if (originalMagnet != null && originalMagnet.isNotEmpty)
          'm': base64UrlEncode(utf8.encode(originalMagnet)),
        if (fileName != null && fileName.isNotEmpty) 'n': fileName,
      },
    ).toString();
  }

  static MagnetUriRef? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != scheme) return null;
    final segments = uri.pathSegments;
    if (segments.length != 1) return null;
    final fileIndex = int.tryParse(segments.first);
    if (fileIndex == null || fileIndex < 0) return null;
    final infoHash = _normalizeInfoHash(uri.host);
    if (infoHash == null) return null;
    String? originalMagnet;
    final encoded = uri.queryParameters['m'];
    if (encoded != null && encoded.isNotEmpty) {
      try {
        originalMagnet = utf8.decode(base64Url.decode(encoded));
      } catch (_) {
        originalMagnet = null;
      }
    }
    return MagnetUriRef(
      infoHash: infoHash,
      fileIndex: fileIndex,
      originalMagnet: originalMagnet,
      fileName: uri.queryParameters['n'],
    );
  }

  static String? _normalizeInfoHash(String raw) {
    final value = raw.trim();
    if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value)) {
      return value.toLowerCase();
    }
    if (RegExp(r'^[A-Z2-7]{32}$').hasMatch(value.toUpperCase())) {
      final bytes = _decodeBase32(value.toUpperCase());
      if (bytes.length == 20) {
        return bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
      }
    }
    return null;
  }

  static List<int> _decodeBase32(String value) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var buffer = 0;
    var bits = 0;
    final output = <int>[];
    for (final codeUnit in value.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(codeUnit));
      if (index < 0) return const [];
      buffer = (buffer << 5) | index;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        output.add((buffer >> bits) & 0xff);
      }
    }
    return output;
  }
}

String formatMagnetBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)}${units[unit]}';
}

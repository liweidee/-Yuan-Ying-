import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/services/magnet/magnet_cache_manager.dart';
import 'package:yuanying/services/magnet/magnet_models.dart';

typedef _DmAbiVersionNative = Int32 Function();
typedef _DmAbiVersionDart = int Function();
typedef _DmInitNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _DmInitDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _DmParseNative = Int64 Function(Pointer<Utf8>);
typedef _DmParseDart = int Function(Pointer<Utf8>);
typedef _DmPollNative = Pointer<Utf8> Function(Int64);
typedef _DmPollDart = Pointer<Utf8> Function(int);
typedef _DmStartNative = Int64 Function(Pointer<Utf8>, Int32);
typedef _DmStartDart = int Function(Pointer<Utf8>, int);
typedef _DmStatsNative = Pointer<Utf8> Function(Int64);
typedef _DmStatsDart = Pointer<Utf8> Function(int);
typedef _DmStopNative = Void Function(Int64, Int32);
typedef _DmStopDart = void Function(int, int);
typedef _DmDisposeNative = Void Function(Int64);
typedef _DmDisposeDart = void Function(int);
typedef _DmFreeNative = Void Function(Pointer<Utf8>);
typedef _DmFreeDart = void Function(Pointer<Utf8>);

class MagnetPluginException implements Exception {
  final String message;

  const MagnetPluginException(this.message);

  @override
  String toString() => message;
}

class MagnetPluginService {
  MagnetPluginService._();

  static final MagnetPluginService instance = MagnetPluginService._();
  static const _abiVersion = 1;
  static const _pluginId = 'magnet';

  final currentStatus = Rxn<MagnetPlaybackStatus>();
  final _lock = Lock();
  final Map<int, String> _parseTaskOwners = {};

  DynamicLibrary? _library;
  bool _initialized = false;
  String? _cacheDirectoryPath;
  String? _loadedPluginVersion;
  MagnetPlaybackSession? _currentSession;
  Timer? _statusTimer;
  bool _pollingStatus = false;

  _DmAbiVersionDart? _dmAbiVersion;
  _DmInitDart? _dmInit;
  _DmParseDart? _dmParse;
  _DmPollDart? _dmPoll;
  _DmStartDart? _dmStart;
  _DmStatsDart? _dmStats;
  _DmStopDart? _dmStop;
  _DmDisposeDart? _dmDispose;
  _DmFreeDart? _dmFree;

  MagnetPlaybackSession? get currentSession => _currentSession;
  String? get activeInfoHash => _currentSession?.infoHash;
  bool get isPlaying => _currentSession != null;

  MagnetPluginAvailability checkAvailability() {
    if (!Platform.isAndroid) {
      return const MagnetPluginAvailability(
        state: MagnetPluginState.unsupportedPlatform,
        message: '磁力播放仅支持 Android',
      );
    }
    final abi = Abi.current();
    if (abi != Abi.androidArm64 && abi != Abi.androidArm) {
      return const MagnetPluginAvailability(
        state: MagnetPluginState.unsupportedAbi,
        message: '当前设备架构不支持磁力播放插件，仅支持 arm64-v8a / armeabi-v7a',
      );
    }
    final plugin = InstallManager.instance.findInstalled(_pluginId);
    if (plugin == null) {
      return const MagnetPluginAvailability(
        state: MagnetPluginState.notInstalled,
        message: '未安装磁力播放插件',
      );
    }
    if (!plugin.enabled) {
      return MagnetPluginAvailability(
        state: MagnetPluginState.disabled,
        message: '磁力播放插件已关闭',
        pluginVersion: plugin.version,
      );
    }
    final path = _resolveLibraryPath(plugin);
    if (path == null) {
      return MagnetPluginAvailability(
        state: MagnetPluginState.missingLibrary,
        message: '磁力播放插件文件不完整，请重新安装',
        pluginVersion: plugin.version,
      );
    }
    return MagnetPluginAvailability(
      state: MagnetPluginState.ready,
      message: '',
      libraryPath: path,
      pluginVersion: plugin.version,
    );
  }

  Future<void> ensureInitialized() async {
    final availability = checkAvailability();
    if (!availability.isReady) {
      throw MagnetPluginException(availability.message);
    }
    final cacheDir = await MagnetCacheManager.instance.cacheDirectory();
    if (_initialized &&
        _cacheDirectoryPath == cacheDir.path &&
        _loadedPluginVersion == availability.pluginVersion) {
      return;
    }

    await _lock.synchronized(() {
      if (_initialized &&
          _cacheDirectoryPath == cacheDir.path &&
          _loadedPluginVersion == availability.pluginVersion) {
        return;
      }
      if (_library != null &&
          _loadedPluginVersion != null &&
          _loadedPluginVersion != availability.pluginVersion) {
        throw const MagnetPluginException('磁力播放插件已更新，请重启应用后再使用');
      }
      _loadLibrary(availability.libraryPath!);
      if (_dmAbiVersion!() != _abiVersion) {
        throw const MagnetPluginException('磁力播放插件 ABI 不兼容');
      }

      final cachePtr = cacheDir.path.toNativeUtf8();
      final optionsPtr = jsonEncode({'metaTimeoutSec': 30}).toNativeUtf8();
      try {
        final ok = _dmInit!(cachePtr, optionsPtr);
        if (ok != 1) {
          throw const MagnetPluginException('磁力播放插件初始化失败');
        }
      } finally {
        malloc.free(cachePtr);
        malloc.free(optionsPtr);
      }
      _initialized = true;
      _cacheDirectoryPath = cacheDir.path;
      _loadedPluginVersion = availability.pluginVersion;
      debugPrint(
        '[Magnet] initialized abi=${Abi.current()} '
        'version=${availability.pluginVersion ?? '-'} '
        'cache=${cacheDir.path}',
      );
    });
  }

  Future<MagnetExpansion> expandMagnet(
    String magnet, {
    required String ownerTag,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!MagnetUri.isMagnet(magnet)) {
      throw const MagnetPluginException('仅支持 magnet: 链接');
    }
    await ensureInitialized();
    final magnetPtr = magnet.toNativeUtf8();
    final int parseTaskId;
    try {
      parseTaskId = await _lock.synchronized(() => _dmParse!(magnetPtr));
    } finally {
      malloc.free(magnetPtr);
    }
    if (parseTaskId <= 0) {
      throw const MagnetPluginException('磁力链接解析失败');
    }
    debugPrint(
      '[Magnet] parse task=$parseTaskId timeout=${timeout.inSeconds}s',
    );
    _parseTaskOwners[parseTaskId] = ownerTag;
    final deadline = DateTime.now().add(timeout);
    MagnetTaskSnapshot? lastSnapshot;
    var lastLoggedState = '';
    try {
      while (DateTime.now().isBefore(deadline)) {
        final snapshot = await _poll(parseTaskId);
        lastSnapshot = snapshot;
        if (snapshot.state != lastLoggedState) {
          lastLoggedState = snapshot.state;
          debugPrint(
            '[Magnet] parse state=${snapshot.state} '
            'error=${snapshot.error.isEmpty ? '-' : snapshot.error}',
          );
        }
        if (snapshot.isError) {
          throw MagnetPluginException(
            snapshot.error.isEmpty ? '磁力元数据解析失败' : snapshot.error,
          );
        }
        final infoHash = snapshot.infoHash;
        if (snapshot.isReady && infoHash != null && infoHash.isNotEmpty) {
          return MagnetExpansion(
            originalMagnet: magnet,
            infoHash: infoHash,
            files: snapshot.files,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      debugPrint(
        '[Magnet] metadata timeout infohash='
        '${MagnetUri.infoHashFromMagnet(magnet) ?? '-'} '
        'state=${lastSnapshot?.state ?? 'unknown'}',
      );
      throw MagnetPluginException(
        '磁力元数据解析超时（${timeout.inSeconds} 秒内未获取到种子信息）。'
        '请检查种子是否有可用节点、网络是否允许 BT/DHT，或尝试关闭代理后重试',
      );
    } finally {
      _parseTaskOwners.remove(parseTaskId);
      await _lock.synchronized(() {
        _safeDispose(parseTaskId);
      });
    }
  }

  Future<MagnetPlaybackResult> resolveToStream({
    required String source,
    required String ownerTag,
    String? fileNameHint,
    Duration metadataTimeout = const Duration(seconds: 30),
    Duration startTimeout = const Duration(seconds: 25),
  }) async {
    await ensureInitialized();
    late final String infoHash;
    late final String? originalMagnet;
    late final MagnetFileInfo file;

    final ref = MagnetUri.parse(source);
    if (ref != null) {
      infoHash = ref.infoHash;
      originalMagnet = ref.originalMagnet;
      file = MagnetFileInfo(
        index: ref.fileIndex,
        name: ref.fileName ?? fileNameHint ?? '种子文件',
        size: 0,
      );
    } else if (MagnetUri.isMagnet(source)) {
      final expansion = await expandMagnet(
        source,
        ownerTag: ownerTag,
        timeout: metadataTimeout,
      );
      infoHash = expansion.infoHash;
      originalMagnet = source;
      file = _selectDefaultFile(expansion.files);
    } else {
      throw const MagnetPluginException('不是有效的磁力播放地址');
    }

    await stopCurrent(deleteMedia: null, prune: false);

    final hashPtr = infoHash.toNativeUtf8();
    final int playTaskId;
    try {
      playTaskId = await _lock.synchronized(
        () => _dmStart!(hashPtr, file.index),
      );
    } finally {
      malloc.free(hashPtr);
    }
    if (playTaskId <= 0) {
      throw const MagnetPluginException('磁力播放任务启动失败');
    }

    final session = MagnetPlaybackSession(
      ownerTag: ownerTag,
      playTaskId: playTaskId,
      infoHash: infoHash,
      file: file,
      originalMagnet: originalMagnet,
      deleteMediaOnStop: MagnetCacheManager.instance.deleteMediaOnStop,
    );
    _currentSession = session;
    currentStatus.value = MagnetPlaybackStatus.fromSession(session);

    final deadline = DateTime.now().add(startTimeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        final snapshot = await _stats(playTaskId);
        if (snapshot.isError) {
          throw MagnetPluginException(
            snapshot.error.isEmpty ? '磁力起播失败' : snapshot.error,
          );
        }
        if (snapshot.hasUrl) {
          _updateFromSnapshot(session, snapshot);
          _startStatusTimer();
          unawaited(
            MagnetCacheManager.instance.pruneIfNeeded(
              activeInfoHash: infoHash,
            ),
          );
          return MagnetPlaybackResult(
            streamUrl: snapshot.url!,
            session: session,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw const MagnetPluginException('磁力起播超时，请检查节点或网络');
    } catch (_) {
      await stopCurrent(deleteMedia: session.deleteMediaOnStop);
      rethrow;
    }
  }

  Future<void> stopCurrent({
    required bool? deleteMedia,
    bool prune = true,
  }) async {
    final session = _currentSession;
    if (session == null) return;
    _statusTimer?.cancel();
    _statusTimer = null;
    final shouldDelete =
        deleteMedia ?? MagnetCacheManager.instance.deleteMediaOnStop;
    await _lock.synchronized(() {
      try {
        _dmStop!(session.playTaskId, shouldDelete ? 1 : 0);
      } catch (_) {}
      try {
        _dmDispose!(session.playTaskId);
      } catch (_) {}
    });
    if (identical(_currentSession, session)) {
      _currentSession = null;
      currentStatus.value = null;
    }
    MagnetCacheManager.instance.markStopped(
      infoHash: session.infoHash,
      fileIndex: session.file.index,
      mediaDeleted: shouldDelete,
    );
    if (prune) {
      unawaited(
        MagnetCacheManager.instance.pruneIfNeeded(
          activeInfoHash: activeInfoHash,
        ),
      );
    }
  }

  Future<void> disposeOwner(
    String ownerTag, {
    bool? deleteMedia,
  }) async {
    final session = _currentSession;
    if (session?.ownerTag == ownerTag) {
      await stopCurrent(deleteMedia: deleteMedia);
    }
    final parseIds = _parseTaskOwners.entries
        .where((entry) => entry.value == ownerTag)
        .map((entry) => entry.key)
        .toList();
    if (parseIds.isNotEmpty) {
      _parseTaskOwners.removeWhere((key, value) => value == ownerTag);
      await _lock.synchronized(() {
        for (final id in parseIds) {
          _safeDispose(id);
        }
      });
    }
  }

  Future<void> shutdownForPluginDisabled() async {
    await disposeAll(deleteMedia: null);
    _initialized = false;
    _cacheDirectoryPath = null;
  }

  Future<void> disposeAll({required bool? deleteMedia}) async {
    await stopCurrent(deleteMedia: deleteMedia);
    final ids = _parseTaskOwners.keys.toList();
    _parseTaskOwners.clear();
    if (ids.isNotEmpty) {
      await _lock.synchronized(() {
        for (final id in ids) {
          _safeDispose(id);
        }
      });
    }
    currentStatus.value = null;
  }

  void _loadLibrary(String path) {
    if (_library != null) return;
    _library = DynamicLibrary.open(path);
    _dmAbiVersion = _library!
        .lookupFunction<_DmAbiVersionNative, _DmAbiVersionDart>(
          'dm_abi_version',
        );
    _dmInit = _library!.lookupFunction<_DmInitNative, _DmInitDart>(
      'dm_init',
    );
    _dmParse = _library!.lookupFunction<_DmParseNative, _DmParseDart>(
      'dm_parse',
    );
    _dmPoll = _library!.lookupFunction<_DmPollNative, _DmPollDart>(
      'dm_poll',
    );
    _dmStart = _library!.lookupFunction<_DmStartNative, _DmStartDart>(
      'dm_start',
    );
    _dmStats = _library!.lookupFunction<_DmStatsNative, _DmStatsDart>(
      'dm_stats',
    );
    _dmStop = _library!.lookupFunction<_DmStopNative, _DmStopDart>(
      'dm_stop',
    );
    _dmDispose = _library!.lookupFunction<_DmDisposeNative, _DmDisposeDart>(
      'dm_dispose',
    );
    _dmFree = _library!.lookupFunction<_DmFreeNative, _DmFreeDart>(
      'dm_free',
    );
  }

  Future<MagnetTaskSnapshot> _poll(int taskId) {
    return _lock.synchronized(() {
      final ptr = _dmPoll!(taskId);
      return _decodeSnapshot(_takeString(ptr));
    });
  }

  Future<MagnetTaskSnapshot> _stats(int taskId) {
    return _lock.synchronized(() {
      final ptr = _dmStats!(taskId);
      return _decodeSnapshot(_takeString(ptr));
    });
  }

  MagnetTaskSnapshot _decodeSnapshot(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return MagnetTaskSnapshot.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    throw const MagnetPluginException('磁力插件返回了无效状态');
  }

  String _takeString(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      throw const MagnetPluginException('磁力插件返回空结果');
    }
    try {
      return ptr.toDartString();
    } finally {
      _dmFree!(ptr);
    }
  }

  void _safeDispose(int taskId) {
    try {
      _dmDispose!(taskId);
    } catch (_) {}
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshStatus());
    });
  }

  Future<void> _refreshStatus() async {
    final session = _currentSession;
    if (session == null || _pollingStatus) return;
    _pollingStatus = true;
    try {
      final snapshot = await _stats(session.playTaskId);
      if (!identical(_currentSession, session)) return;
      _updateFromSnapshot(session, snapshot);
      if (snapshot.isError) {
        _statusTimer?.cancel();
        _statusTimer = null;
        currentStatus.value = MagnetPlaybackStatus.fromSession(
          session,
          state: 'error',
          snapshot: snapshot,
        );
      }
    } catch (_) {
      if (identical(_currentSession, session)) {
        currentStatus.value = MagnetPlaybackStatus.fromSession(
          session,
          state: 'error',
        ).copyWithError('磁力状态获取失败');
      }
    } finally {
      _pollingStatus = false;
    }
  }

  void _updateFromSnapshot(
    MagnetPlaybackSession session,
    MagnetTaskSnapshot snapshot,
  ) {
    final currentFile = snapshot.total > 0 && session.file.size == 0
        ? MagnetFileInfo(
            index: session.file.index,
            name: session.file.name,
            size: snapshot.total,
            ext: session.file.ext,
          )
        : session.file;
    currentStatus.value = MagnetPlaybackStatus.fromSession(
      session,
      snapshot: snapshot,
    );
    MagnetCacheManager.instance.recordPlayback(
      infoHash: session.infoHash,
      file: currentFile,
      downloadedBytes: snapshot.completed,
      complete:
          snapshot.total > 0 &&
          (snapshot.progress >= 0.999 || snapshot.completed >= snapshot.total),
      originalMagnet: session.originalMagnet,
    );
  }

  MagnetFileInfo _selectDefaultFile(List<MagnetFileInfo> files) {
    if (files.isEmpty) {
      throw const MagnetPluginException('种子中没有可播放文件');
    }
    final videos = files.where((file) => file.isLikelyVideo).toList();
    final candidates = videos.isEmpty ? files : videos;
    candidates.sort((a, b) => b.size.compareTo(a.size));
    return candidates.first;
  }

  String? _resolveLibraryPath(InstalledPlugin plugin) {
    final root = Directory(plugin.installPath);
    if (!root.existsSync()) return null;
    final abi = Abi.current() == Abi.androidArm64 ? 'arm64-v8a' : 'armeabi-v7a';
    final candidates = [
      p.join(root.path, 'libmagnet.so'),
      p.join(root.path, 'bin', 'libmagnet.so'),
      p.join(root.path, 'lib', abi, 'libmagnet.so'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return p.normalize(candidate);
    }
    try {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is File && p.basename(entity.path) == 'libmagnet.so') {
          return p.normalize(entity.path);
        }
      }
    } catch (_) {}
    return null;
  }
}

extension on MagnetPlaybackStatus {
  MagnetPlaybackStatus copyWithError(String value) {
    return MagnetPlaybackStatus(
      ownerTag: ownerTag,
      state: 'error',
      fileName: fileName,
      infoHash: infoHash,
      progress: progress,
      completed: completed,
      total: total,
      downRate: downRate,
      upRate: upRate,
      peers: peers,
      seeders: seeders,
      error: value,
    );
  }
}

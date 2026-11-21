import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IosPipMedia {
  final String url;
  final Map<String, String> headers;
  final int episodeIndex;
  final String episodeName;

  const IosPipMedia({
    required this.url,
    this.headers = const <String, String>{},
    required this.episodeIndex,
    required this.episodeName,
  });
}

class IosPipEnterResult {
  final bool supported;
  final bool active;
  final bool requested;
  final String? error;

  const IosPipEnterResult({
    required this.supported,
    required this.active,
    required this.requested,
    this.error,
  });

  factory IosPipEnterResult.fromMap(Map<String, dynamic>? value) {
    return IosPipEnterResult(
      supported: value?['supported'] == true,
      active: value?['active'] == true,
      requested: value?['requested'] == true,
      error: value?['error']?.toString(),
    );
  }
}

class _IosPipSession {
  final String tag;
  final Map<String, dynamic> Function(int positionMs)? restoreArguments;
  final Future<IosPipMedia?> Function(int episodeIndex)? resolveNext;
  final int? Function(int currentIndex)? nextEpisodeIndex;
  final void Function(int episodeIndex)? onEpisodeAdvanced;
  final Future<void> Function(int positionMs, int episodeIndex)?
  onRestoreCurrent;
  final void Function(bool active, String? error, int? positionMs)?
  onStatusChanged;

  int episodeIndex;
  final double speed;
  bool playerActive;
  bool restoreHandled;

  _IosPipSession({
    required this.tag,
    required this.episodeIndex,
    required this.speed,
    required this.playerActive,
    required this.restoreArguments,
    required this.resolveNext,
    required this.nextEpisodeIndex,
    required this.onEpisodeAdvanced,
    required this.onRestoreCurrent,
    required this.onStatusChanged,
  }) : restoreHandled = false;
}

/// iOS 系统画中画协调器。
///
/// iOS PiP 使用原生 AVPlayer 独立播放，Flutter 侧的 MPV/MDK 在进入 PiP
/// 后会暂停。该类只维护桥接和会话元数据，不参与其他平台的播放器逻辑。
class IosPipHelper {
  IosPipHelper._();

  static final IosPipHelper instance = IosPipHelper._();
  static const MethodChannel _channel = MethodChannel(
    'com.example.yuanying/ios_pip',
  );

  final ValueNotifier<bool> isSupported = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isRequested = ValueNotifier<bool>(false);
  final ValueNotifier<int> activeEpisodeIndex = ValueNotifier<int>(0);

  Future<bool> Function(Map<String, dynamic> arguments)? _restorePage;
  _IosPipSession? _session;
  bool _initialized = false;
  bool _handlingRestore = false;
  bool _advancing = false;
  int _sessionGeneration = 0;

  bool get hasActiveSession => _session != null;

  Future<void> initialize({
    required Future<bool> Function(Map<String, dynamic> arguments)
    onRestorePage,
  }) async {
    _restorePage = onRestorePage;
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler(_handleMethodCall);
    }
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    try {
      final status = await _channel
          .invokeMapMethod<String, dynamic>('pictureInPictureStatus');
      isSupported.value = status?['supported'] == true;
      isActive.value = status?['active'] == true;
      if (!isActive.value) isRequested.value = false;
    } on MissingPluginException {
      isSupported.value = false;
      isActive.value = false;
      isRequested.value = false;
    } on PlatformException {
      isSupported.value = false;
      isActive.value = false;
      isRequested.value = false;
    }
  }

  Future<IosPipEnterResult> enter({
    required String tag,
    required String url,
    required Map<String, String> headers,
    required int positionMs,
    required double speed,
    required int episodeIndex,
    String? title,
    int? width,
    int? height,
    Map<String, int>? sourceRect,
    required Map<String, dynamic> Function(int positionMs) restoreArguments,
    required Future<IosPipMedia?> Function(int episodeIndex) resolveNext,
    int? Function(int currentIndex)? nextEpisodeIndex,
    void Function(int episodeIndex)? onEpisodeAdvanced,
    Future<void> Function(int positionMs, int episodeIndex)?
    onRestoreCurrent,
    void Function(bool active, String? error, int? positionMs)?
    onStatusChanged,
  }) async {
    _sessionGeneration++;
    _advancing = false;
    _session = _IosPipSession(
      tag: tag,
      episodeIndex: episodeIndex,
      speed: speed,
      playerActive: true,
      restoreArguments: restoreArguments,
      resolveNext: resolveNext,
      nextEpisodeIndex: nextEpisodeIndex,
      onEpisodeAdvanced: onEpisodeAdvanced,
      onRestoreCurrent: onRestoreCurrent,
      onStatusChanged: onStatusChanged,
    );
    activeEpisodeIndex.value = episodeIndex;
    isRequested.value = true;

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'enterPictureInPicture',
        <String, dynamic>{
          'url': url,
          if (headers.isNotEmpty) 'headers': headers,
          'position': positionMs,
          'speed': speed,
          'episodeIndex': episodeIndex,
          if (title != null && title.isNotEmpty) 'title': title,
          if (width != null && width > 0) 'width': width,
          if (height != null && height > 0) 'height': height,
          ...?sourceRect,
        },
      );
      final parsed = IosPipEnterResult.fromMap(result);
      isSupported.value = parsed.supported;
      isActive.value = parsed.active || isActive.value;
      isRequested.value = parsed.requested && !isActive.value;
      if (!parsed.supported || (!parsed.active && !parsed.requested)) {
        _session = null;
      }
      return parsed;
    } on MissingPluginException {
      _session = null;
      isRequested.value = false;
      return const IosPipEnterResult(
        supported: false,
        active: false,
        requested: false,
        error: '当前平台不支持 iOS 画中画',
      );
    } on PlatformException catch (error) {
      _session = null;
      isRequested.value = false;
      return IosPipEnterResult(
        supported: true,
        active: false,
        requested: false,
        error: error.message,
      );
    } catch (error) {
      _session = null;
      isRequested.value = false;
      return IosPipEnterResult(
        supported: true,
        active: false,
        requested: false,
        error: error.toString(),
      );
    }
  }

  void notifyPlayerDisposed(String tag) {
    final session = _session;
    if (session == null || session.tag != tag) return;
    session.playerActive = false;
  }

  Future<int?> stop({bool restoreApp = true}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'stopPictureInPicture',
      );
      final position = (result?['position'] as num?)?.toInt();
      isRequested.value = false;
      if (restoreApp && position != null && position > 0) {
        await _restoreApplication(position, allowPageRestore: true);
      }
      return position;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments;
    final map = arguments is Map
        ? Map<String, dynamic>.from(arguments)
        : const <String, dynamic>{};

    switch (call.method) {
      case 'iosPipChanged':
        final active = map['active'] == true;
        isSupported.value = map['supported'] != false;
        isActive.value = active;
        isRequested.value = false;
        if (active) {
          final index = (map['episodeIndex'] as num?)?.toInt();
          if (index != null) activeEpisodeIndex.value = index;
          _session?.onStatusChanged?.call(true, null, null);
          return;
        }
        final position = (map['position'] as num?)?.toInt();
        final error = map['error']?.toString();
        if (position != null && position > 0) {
          await _restoreApplication(position);
        } else if (error != null && error.isNotEmpty) {
          _session?.onStatusChanged?.call(false, error, null);
        }
        _clearSession();
        return;

      case 'iosPipRestoreUI':
        final position = (map['position'] as num?)?.toInt() ?? 0;
        await _restoreApplication(position, allowPageRestore: true);
        return;

      case 'iosPipItemEnded':
        await _advanceToNextEpisode();
        return;

      case 'iosPipItemFailed':
        return;

      case 'iosPipLog':
        debugPrint('[iOS PiP] ${map['message'] ?? arguments}');
        return;
    }
  }

  Future<void> _restoreApplication(
    int positionMs, {
    bool allowPageRestore = false,
  }) async {
    final session = _session;
    if (session == null || _handlingRestore || session.restoreHandled) return;
    _handlingRestore = true;
    session.restoreHandled = true;
    try {
      if (session.playerActive && session.onRestoreCurrent != null) {
        await session.onRestoreCurrent!(positionMs, session.episodeIndex);
        return;
      }

      if (!allowPageRestore) return;

      final routeArguments = session.restoreArguments?.call(positionMs);
      final restored =
          routeArguments != null &&
          _restorePage != null &&
          await _restorePage!(routeArguments);
      if (!restored) {
        debugPrint(
          '[iOS PiP] 无法恢复应用内页面，'
          'position=$positionMs, episode=${session.episodeIndex}',
        );
      }
    } finally {
      isActive.value = false;
      isRequested.value = false;
      _handlingRestore = false;
    }
  }

  Future<void> _advanceToNextEpisode() async {
    final session = _session;
    if (session == null || session.resolveNext == null || _advancing) return;
    _advancing = true;
    final generation = _sessionGeneration;
    final nextIndex = session.nextEpisodeIndex != null
        ? session.nextEpisodeIndex!(session.episodeIndex)
        : session.episodeIndex + 1;
    if (nextIndex == null || nextIndex < 0) return;
    try {
      final media = await session.resolveNext!(nextIndex);
      if (media == null) return;
      if (!identical(_session, session) || generation != _sessionGeneration) {
        return;
      }
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'replacePictureInPictureItem',
        <String, dynamic>{
          'url': media.url,
          if (media.headers.isNotEmpty) 'headers': media.headers,
          'episodeIndex': media.episodeIndex,
          'speed': session.speed,
        },
      );
      if (result?['replaced'] != true ||
          !identical(_session, session) ||
          generation != _sessionGeneration) {
        return;
      }
      session.episodeIndex = media.episodeIndex;
      activeEpisodeIndex.value = media.episodeIndex;
      session.onEpisodeAdvanced?.call(media.episodeIndex);
    } catch (error) {
      debugPrint('[iOS PiP] 自动下一集失败: $error');
    } finally {
      if (generation == _sessionGeneration) _advancing = false;
    }
  }

  void _clearSession() {
    _sessionGeneration++;
    _session = null;
    _advancing = false;
    isActive.value = false;
    isRequested.value = false;
  }
}

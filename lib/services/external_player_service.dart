import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:yuanying/plugin/pl_player/models/external_player_type.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 第三方播放器服务
///
/// 职责：
/// 1. 根据用户配置的路径启动 MPV / VLC / PotPlayer
/// 2. 适配不同播放器的命令行参数（进度续传 + 请求头）
class ExternalPlayerService {
  // ============================================================
  // 单例
  // ============================================================
  static final ExternalPlayerService _instance = ExternalPlayerService._();
  factory ExternalPlayerService() => _instance;
  ExternalPlayerService._();

  // ============================================================
  // 状态查询
  // ============================================================

  /// 是否已配置且路径有效
  bool get isConfigured {
    final path = PlayerPref.externalPlayerPath;
    if (path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 是否至少配置了一个有效播放器
  bool get hasAnyConfigured {
    return ExternalPlayerType.values.any(_isTypeConfigured);
  }

  /// 获取所有已配置且路径有效的播放器（保持枚举顺序：MPV → VLC → PotPlayer）
  List<ExternalPlayerType> getConfiguredPlayers() {
    return ExternalPlayerType.values.where(_isTypeConfigured).toList();
  }

  /// 判断某个类型是否已配置且有效
  bool _isTypeConfigured(ExternalPlayerType type) {
    final path = PlayerPref.getPathForType(type);
    if (path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 获取当前播放器类型
  ExternalPlayerType get currentType => PlayerPref.externalPlayerType;

  /// 获取当前配置的路径
  String get currentPath => PlayerPref.externalPlayerPath;

  // ============================================================
  // 启动
  // ============================================================

  /// 启动第三方播放器
  
  /// 启动指定类型的播放器（不依赖 PlayerPref.externalPlayerType）
  ///
  /// 返回 null 表示成功，返回字符串表示失败原因。
  Future<String?> launchWithType({
    required ExternalPlayerType type,
    required String url,
    required Duration startPosition,
    Map<String, String>? headers,
  }) async {
    final path = PlayerPref.getPathForType(type);
    if (path.isEmpty) {
      return '${type.label} 未配置，请先配置路径';
    }
    if (!File(path).existsSync()) {
      return '${type.label} 配置的路径无效，请重新配置';
    }

    final args = _buildArgs(type, url, startPosition, headers);

    debugPrint('[ExternalPlayer] 类型: ${type.label}');
    debugPrint('[ExternalPlayer] 路径: $path');
    debugPrint('[ExternalPlayer] 参数: ${args.join(" ")}');

    try {
      await Process.start(
        path,
        args,
        mode: ProcessStartMode.detached,
        workingDirectory: File(path).parent.path,
      );
      debugPrint('[ExternalPlayer] 启动成功');
      return null;
    } on ProcessException catch (e) {
      debugPrint('[ExternalPlayer] ProcessException: ${e.message}');
      return '启动失败：${e.message}';
    } catch (e) {
      debugPrint('[ExternalPlayer] 未知异常: $e');
      return '启动失败：$e';
    }
  }

  /// 启动当前配置的播放器（保持向后兼容）
  Future<String?> launch({
    required String url,
    required Duration startPosition,
    Map<String, String>? headers,
  }) {
    return launchWithType(
      type: PlayerPref.externalPlayerType,
      url: url,
      startPosition: startPosition,
      headers: headers,
    );
  }

  // ============================================================
  // 参数构造
  // ============================================================

  List<String> _buildArgs(
    ExternalPlayerType type,
    String url,
    Duration startPosition,
    Map<String, String>? headers,
  ) {
    switch (type) {
      case ExternalPlayerType.mpv:
        return _buildMpvArgs(url, startPosition, headers);
      case ExternalPlayerType.vlc:
        return _buildVlcArgs(url, startPosition, headers);
      case ExternalPlayerType.potPlayer:
        return _buildPotPlayerArgs(url, startPosition, headers);
    }
  }

  /// MPV 参数：支持任意请求头 + 进度续传
  List<String> _buildMpvArgs(
    String url,
    Duration startPosition,
    Map<String, String>? headers,
  ) {
    final args = <String>[
      '--start=${startPosition.inSeconds}',
      '--force-window=yes',
      '--no-terminal',
    ];

    // MPV 的 --http-header-fields 是 STRINGLIST，多次指定会累加
    // 不用逗号分隔的单参数形式，避免 header value 里含逗号被误解析
    if (headers != null && headers.isNotEmpty) {
      for (final entry in headers.entries) {
        args.add('--http-header-fields=${entry.key}: ${entry.value}');
      }
    }

    args.add(url);
    return args;
  }

  /// VLC 参数：仅支持 Referer / User-Agent 等有限请求头
  List<String> _buildVlcArgs(
    String url,
    Duration startPosition,
    Map<String, String>? headers,
  ) {
    final args = <String>[
      '--start-time=${startPosition.inSeconds}',
    ];

    if (headers != null && headers.isNotEmpty) {
      // VLC 只识别 Referer 和 User-Agent 两个请求头
      final referer = headers['Referer'] ?? headers['referer'];
      if (referer != null && referer.isNotEmpty) {
        args.add('--http-referrer=$referer');
      }
      final ua = headers['User-Agent'] ?? headers['user-agent'];
      if (ua != null && ua.isNotEmpty) {
        args.add('--http-user-agent=$ua');
      }
    }

    args.add(url);
    return args;
  }

  /// PotPlayer 参数：仅支持进度续传，不支持命令行传请求头
  ///
  /// 如果视频源需要 Referer / UA 校验，PotPlayer 会播放失败。
  List<String> _buildPotPlayerArgs(
    String url,
    Duration startPosition,
    Map<String, String>? headers,
  ) {
    // PotPlayer 参数顺序：URL 在前，选项在后
    final args = <String>[url];
    if (startPosition.inSeconds > 0) {
      args.add('/seek=${startPosition.inSeconds}');
    }
    // PotPlayer 命令行不支持自定义 HTTP 请求头
    return args;
  }
}
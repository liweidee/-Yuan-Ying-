// lib/core/mdk_init.dart
// 独立的 MDK（libmdk）全局初始化。
// 不接管 VideoPlayerPlatform，与 video_player 插件完全解耦。

import 'package:logging/logging.dart';
import 'package:fvp/mdk.dart' as mdk;

/// fvp 内置的公开默认 key。
/// 如果你有自定义 key，通过 globalOpts 传入 'MDK_KEY'。
const _kDefaultMdkKey =
    '4DF316BC71206BCEECD01559CC0FEDAF32DF8ECAE656BD9999CB821B67DB5B33'
    '2B323F24539BA7172746B8F5A64CA67AF342B16BF4B418F76718B821F77BEA07'
    '22F71DBC8EDF9431132FEAA633F0125072DF8DAC90268C62D0E4BA7D6DF9A6C4'
    '976AB1146EC55FFD1945CAB4125B20D5C77976CF1BCB77B14C563868EA00EA07';

final _mdkLog = Logger('mdk');

bool _inited = false;

/// 初始化 libmdk 全局状态。幂等。
///
/// [globalOpts] 可选全局选项，例如：
/// ```dart
/// initMdk(globalOpts: {'MDK_KEY': '<your key>'});
/// ```
void initMdk({Map<String, Object>? globalOpts}) {
  if (_inited) return;
  _inited = true;

  // 1) 日志
  mdk.setLogHandler((level, msg) {
    if (msg.endsWith('\n')) msg = msg.substring(0, msg.length - 1);
    switch (level) {
      case mdk.LogLevel.error:
        _mdkLog.severe(msg);
      case mdk.LogLevel.warning:
        _mdkLog.warning(msg);
      case mdk.LogLevel.info:
        _mdkLog.info(msg);
      case mdk.LogLevel.debug:
        _mdkLog.fine(msg);
      case mdk.LogLevel.all:
        _mdkLog.finest(msg);
      default:
        break;
    }
  });

  // 2) 默认全局选项（对齐 fvp 内部默认）
  mdk.setGlobalOption('log', 'all');
  mdk.setGlobalOption('d3d11.sync.cpu', 1);

  // 3) 用户自定义选项
  globalOpts?.forEach((key, value) {
    if (key == 'MDK_KEY') return;
    mdk.setGlobalOption(key, value);
  });

  // 4) MDK key（必须，放最后）
  final key = globalOpts?['MDK_KEY'] as String? ?? _kDefaultMdkKey;
  mdk.setGlobalOption('MDK_KEY', key);
}
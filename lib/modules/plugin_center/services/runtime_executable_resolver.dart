import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';

/// 解析运行时插件声明的可执行文件。
///
/// `binaries` / `pyRuntime.pythonBin` 同时存在两种声明形式：
/// - `bin/node.exe`：声明值本身就是相对插件根目录的路径；
/// - `node24-arm64`：声明值不含目录，实际文件位于 `bin/` 下。
///
/// 普通 ZIP 安装会完整保留包内路径，因此两种形式都必须支持。
abstract final class RuntimeExecutableResolver {
  static String? find({
    required String installPath,
    required String declaredPath,
  }) {
    final declared = declaredPath.trim().replaceAll('\\', '/');
    if (declared.isEmpty) return null;

    final installDir = Directory(installPath);
    final normalizedDeclared = p.normalize(declared);
    if (p.isAbsolute(normalizedDeclared) ||
        normalizedDeclared == '..' ||
        normalizedDeclared.startsWith('..${p.separator}')) {
      return null;
    }

    final candidates = <String>{
      p.join(installPath, declared),
      p.join(installPath, 'bin', declared),
      p.join(installPath, p.basename(declared)),
      p.join(installPath, 'bin', p.basename(declared)),
    };

    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (!PluginPaths.isWithin(installDir, normalized) ||
          p.equals(normalized, installDir.path)) {
        continue;
      }
      if (File(normalized).existsSync()) {
        return normalized;
      }
    }
    return null;
  }
}

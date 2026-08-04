import 'dart:io' show Platform;
import 'package:path/path.dart' as path;

abstract final class PathUtils {
  static String buildShadersAbsolutePath(
    String baseDirectory,
    List<String> shaders,
  ) {
    return shaders
        .map((shader) => path.join(baseDirectory, shader))
        .join(Platform.isWindows ? ';' : ':');
  }
}
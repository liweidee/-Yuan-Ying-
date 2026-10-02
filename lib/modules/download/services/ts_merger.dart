// lib/modules/download/services/ts_merger.dart
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// 纯 Dart 二进制合并 TS 切片
///
/// 关键点：
/// - 用 `sink.addStream(stream)` 而不是 `stream.pipe(sink)`
///   `pipe` 会在流结束后关闭 sink，多分片场景第二次写入会抛 `File closed`
/// - 流式复制，内存占用恒定
///
/// 前提：
/// - 切片已解密（若原始为 AES-128 加密流）
/// - 切片按 m3u8 顺序排列
/// - 属于同一 variant，编码参数一致
abstract final class TsMerger {
  /// 合并 tsPaths 到 outputPath
  ///
  /// - [onProgress]：已合并字节数 / 总字节数
  /// - 返回合并后的 File，失败返回 null
  static Future<File?> merge({
    required List<String> tsPaths,
    required String outputPath,
    void Function(int merged, int total)? onProgress,
  }) async {
    final outputFile = File(outputPath);

    // 1. 统计有效分片 + 总大小
    int totalBytes = 0;
    final validPaths = <String>[];
    for (final p in tsPaths) {
      final f = File(p);
      if (await f.exists()) {
        totalBytes += await f.length();
        validPaths.add(p);
      } else {
        debugPrint('TsMerger: missing segment $p');
      }
    }

    if (validPaths.isEmpty) {
      debugPrint('TsMerger: no valid segments');
      return null;
    }

    // 2. 清理旧的输出文件
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    // 3. 打开输出流（追加模式）
    final sink = outputFile.openWrite(mode: FileMode.writeOnlyAppend);
    int mergedBytes = 0;

    try {
      // 4. 逐片流式复制
      //
      // 注意：这里必须用 `sink.addStream()` 而非 `src.openRead().pipe(sink)`
      // 因为 pipe() 会在流消费完成后自动 close 目标 sink，
      // 第一个分片写完后 sink 就关了，第二个分片会抛 FileSystemException。
      for (final p in validPaths) {
        final src = File(p);
        await sink.addStream(src.openRead());
        mergedBytes += await src.length();
        onProgress?.call(mergedBytes, totalBytes);
      }

      // 5. 关闭输出流（会自动 flush）
      await sink.flush();
      await sink.close();

      debugPrint('TsMerger: merged to $outputPath ($mergedBytes bytes)');
      return outputFile;
    } catch (e, s) {
      debugPrint('TsMerger error: $e\n$s');
      try {
        await sink.close();
      } catch (_) {}
      // 失败时清理不完整的输出
      try {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } catch (_) {}
      return null;
    }
  }
}
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:enough_convert/enough_convert.dart';

import '../models/subtitle_file.dart';

/// 支持的字幕扩展名（小写，不带点）
const _subtitleExts = <String>['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// 将原始字节解析为字幕文件列表。
///
/// 自动识别并解压：
/// - ZIP（PK 头 0x50 0x4B）
/// - GZIP（0x1F 0x8B）
/// - 其它视为原始字幕文件
List<SubtitleFile> extractSubtitleFiles(List<int> bytes, String baseName) {
  // ZIP
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <SubtitleFile>[];
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!_isSubtitleExt(file.name)) continue;
      final content = file.content;
      if (content is! List<int>) continue;
      files.add(SubtitleFile(
        name: file.name,
        bytes: content,
        ext: _extOf(file.name),
      ));
    }
    return files;
  }

  // GZIP
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    final decoded = GZipDecoder().decodeBytes(bytes);
    return [
      SubtitleFile(
        name: '$baseName.srt',
        bytes: decoded,
        ext: 'srt',
      ),
    ];
  }

  // 原始
  final ext = _isSubtitleExt(baseName) ? _extOf(baseName) : 'srt';
  return [
    SubtitleFile(
      name: '$baseName.$ext',
      bytes: bytes,
      ext: ext,
    ),
  ];
}

/// 将字节内容解码为字符串，自动处理 BOM、UTF-8、GBK、latin1。
String decodeSubtitleBytes(List<int> bytes) {
  // BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  // UTF-8
  try {
    return utf8.decode(bytes);
  } catch (_) {}
  // GBK
  try {
    return gbk.decode(bytes);
  } catch (_) {}
  // 兜底
  return latin1.decode(bytes);
}

bool _isSubtitleExt(String name) {
  final parts = name.toLowerCase().split('.');
  if (parts.length < 2) return false;
  return _subtitleExts.contains(parts.last);
}

String _extOf(String name) {
  final parts = name.toLowerCase().split('.');
  return parts.length >= 2 ? parts.last : 'srt';
}
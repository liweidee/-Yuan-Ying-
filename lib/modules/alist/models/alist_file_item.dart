import 'package:flutter/material.dart';

enum AlistFileType {
  audio,
  code,
  compress,
  email,
  excel,
  flash,
  html,
  image,
  keynote,
  numbers,
  others,
  pages,
  pdf,
  ppt,
  psd,
  sketch,
  txt,
  video,
  word,
  folder,
  file,
  apk,
  markdown,
}

class AlistFileItem {
  String name;
  String path;
  final int? size;
  final String? sizeDesc;
  final bool isDir;
  final String? modified;
  final int modifiedMilliseconds;
  final String sign;
  final String thumb;
  final int typeInt;
  final AlistFileType type;
  final String? provider;

  AlistFileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.sizeDesc,
    required this.isDir,
    required this.modified,
    required this.modifiedMilliseconds,
    required this.sign,
    required this.thumb,
    required this.typeInt,
    required this.type,
    required this.provider,
  });

  IconData get icon {
    if (isDir) return Icons.folder;
    switch (type) {
      case AlistFileType.audio:
        return Icons.music_note;
      case AlistFileType.image:
        return Icons.image;
      case AlistFileType.video:
        return Icons.movie;
      case AlistFileType.apk:
        return Icons.android;
      case AlistFileType.word:
        return Icons.description;
      case AlistFileType.excel:
      case AlistFileType.numbers:
        return Icons.table_chart;
      case AlistFileType.ppt:
      case AlistFileType.keynote:
        return Icons.slideshow;
      case AlistFileType.txt:
        return Icons.text_snippet;
      case AlistFileType.code:
        return Icons.code;
      case AlistFileType.pdf:
        return Icons.picture_as_pdf;
      case AlistFileType.compress:
        return Icons.archive;
      case AlistFileType.markdown:
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }
}
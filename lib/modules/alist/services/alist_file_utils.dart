import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/alist_server_controller.dart';
import '../controllers/alist_user_controller.dart';
import '../models/alist_file_item.dart';
import '../models/alist_resp_models.dart';
import '../net/alist_dio_utils.dart';

class AlistFileUtils {
  AlistFileUtils._();

  static final _isoDateFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
  static final _dateFormatThisYear = DateFormat("MM/dd HH:mm");
  static final _dateFormatThatYear = DateFormat("yyyy/MM/dd HH:mm");

  // ==================== 类型判断 ====================
  static AlistFileType getFileType(bool isDir, String name) {
    if (isDir) return AlistFileType.folder;
    final extIndex = name.lastIndexOf('.');
    if (extIndex <= 0 || extIndex == name.length - 1) {
      return AlistFileType.others;
    }
    final ext = name.substring(extIndex + 1).toLowerCase();
    switch (ext) {
      case "apk":
        return AlistFileType.apk;
      case "md":
        return AlistFileType.markdown;
      case "mp3":
      case "m4a":
      case "m4r":
      case "wav":
      case "aiff":
      case "wma":
      case "mpv":
      case "amr":
      case "ape":
      case "cue":
      case "au":
      case "midi":
      case "realaudio":
      case "vqf":
      case "ogg":
      case "opus":
      case "flac":
      case "aac":
        return AlistFileType.audio;
      case "zip":
      case "rar":
      case "7z":
      case "tar":
      case "gz":
      case "bz2":
      case "xz":
      case "lzh":
      case "cab":
      case "iso":
        return AlistFileType.compress;
      case "eml":
        return AlistFileType.email;
      case "swf":
        return AlistFileType.flash;
      case "htm":
      case "html":
      case "xhtml":
      case "mht":
        return AlistFileType.html;
      case "png":
      case "gif":
      case "jpg":
      case "jpeg":
      case "bmp":
      case "tif":
      case "tiff":
      case "ico":
      case "raw":
      case "eps":
      case "pcx":
      case "svg":
      case "webp":
        return AlistFileType.image;
      case "key":
        return AlistFileType.keynote;
      case "numbers":
        return AlistFileType.numbers;
      case "pdf":
        return AlistFileType.pdf;
      case "ppt":
      case "pptx":
      case "pps":
      case "pot":
      case "pptm":
      case "potm":
      case "ppam":
      case "ppsx":
      case "ppsm":
      case "sldx":
      case "sldm":
      case "thmx":
      case "dps":
      case "dpt":
      case "potx":
        return AlistFileType.ppt;
      case "xlsx":
      case "xls":
      case "csv":
        return AlistFileType.excel;
      case "psd":
        return AlistFileType.psd;
      case "txt":
      case "log":
      case "xml":
        return AlistFileType.txt;
      case "mov":
      case "mp4":
      case "avi":
      case "wmv":
      case "rmvb":
      case "3gp":
      case "m4v":
      case "rm":
      case "mpg":
      case "mkv":
      case "f4v":
      case "asf":
      case "asx":
      case "mpeg":
      case "mpe":
      case "dat":
      case "vob":
      case "flv":
      case "ts":
        return AlistFileType.video;
      case "doc":
      case "docx":
      case "dot":
      case "dotx":
      case "docm":
      case "dotm":
      case "wps":
      case "wpt":
      case "rtf":
        return AlistFileType.word;
      case "sketch":
        return AlistFileType.sketch;
      case "py":
      case "java":
      case "cpp":
      case "c":
      case "h":
      case "js":
      case "php":
      case "css":
      case "go":
      case "rb":
      case "swift":
      case "kt":
      case "rs":
      case "sh":
      case "vb":
      case "sql":
      case "scala":
      case "r":
      case "psm1":
      case "ps1":
      case "pas":
      case "m":
      case "lua":
      case "jl":
      case "hs":
      case "f95":
      case "f90":
      case "erl":
      case "exs":
      case "ex":
      case "dart":
      case "coffee":
      case "cbl":
      case "cob":
      case "bat":
      case "asm":
      case "as":
      case "arb":
        return AlistFileType.code;
    }
    return AlistFileType.others;
  }

  // ==================== 图标 ====================
  static IconData getFileIcon(bool isDir, String name) {
    final type = getFileType(isDir, name);
    switch (type) {
      case AlistFileType.folder:
        return Icons.folder;
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
      case AlistFileType.numbers:
      case AlistFileType.excel:
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

  // ==================== 文件链接 ====================
  static Future<String?> makeFileLink(String path, String? sign) async {
    final serverCtrl = Get.find<AlistServerController>();
    final userCtrl = Get.find<AlistUserController>();
    final server = serverCtrl.currentServer;
    if (server == null) return null;

    var basePath = userCtrl.user.value.basePath ?? '';
    if (basePath.isEmpty) {
      try {
        await userCtrl.requestBasePath();
        basePath = userCtrl.user.value.basePath ?? '';
      } catch (_) {}
    }

    return AlistDioUtils.buildFileUrl(
      serverUrl: server.serverUrl,
      basePath: basePath.isEmpty ? '/' : basePath,
      path: path,
      sign: sign,
    );
  }

  static Future<void> copyFileLink(String path, String? sign) async {
    final url = await makeFileLink(path, sign);
    if (url == null || url.isEmpty) {
      SmartDialog.showToast('获取文件链接失败');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    SmartDialog.showToast('链接已复制');
  }

  // ==================== 格式化 ====================
  static String formatBytes(int size) {
    if (size <= 0) return "0B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    final i = (log(size) / log(1024)).floor();
    return "${(size / pow(1024, i)).toStringAsFixed(2)}${suffixes[i]}";
  }

  static DateTime? parseModifiedTime(String modified) {
    var modifyTimeStr = modified;
    final indexOnMs = modifyTimeStr.lastIndexOf(".");
    if (indexOnMs > -1) {
      modifyTimeStr = "${modifyTimeStr.substring(0, indexOnMs)}Z";
    }
    try {
      if (modifyTimeStr.contains("+")) {
        return DateTime.parse(modifyTimeStr);
      }
      return _isoDateFormat.parse(modifyTimeStr);
    } catch (_) {
      return null;
    }
  }

  static String getReformatTime(DateTime? modifyTime, String defaultValue) {
    if (modifyTime == null) return defaultValue;
    final now = DateTime.now();
    if (now.year == modifyTime.year) {
      return _dateFormatThisYear.format(modifyTime);
    }
    return _dateFormatThatYear.format(modifyTime);
  }

  static String? getCompleteThumbnail(String? thumbnail) {
    if (thumbnail == null || thumbnail.isEmpty) return null;
    if (!thumbnail.startsWith("http://") && !thumbnail.startsWith("https://")) {
      final serverCtrl = Get.find<AlistServerController>();
      final server = serverCtrl.currentServer;
      if (server == null) return null;
      final uri = Uri.tryParse(server.serverUrl);
      if (uri == null) return null;
      return "${uri.scheme}://${uri.host}:${uri.port}$thumbnail";
    }
    return thumbnail;
  }

  // ==================== 自然排序 ====================
  static int naturalCompare(String a, String b) {
    if (a == b) return 0;
    while (true) {
      final p = _commonPrefix(a, b);
      if (p != 0) {
        a = a.substring(p);
        b = b.substring(p);
      }
      if (a.isEmpty) return b.isNotEmpty ? -1 : 1;
      final ia = _digits(a);
      if (ia > 0) {
        final ib = _digits(b);
        if (ib > 0) {
          final an = int.tryParse(a.substring(0, ia)) ?? 0;
          final bn = int.tryParse(b.substring(0, ib)) ?? 0;
          if (an != bn) return an.compareTo(bn);
          if (ia != a.length && ib != b.length) {
            a = a.substring(ia);
            b = b.substring(ib);
            continue;
          }
        }
      }
      return a.compareTo(b);
    }
  }

  static int _commonPrefix(String a, String b) {
    int m = a.length;
    final n = b.length;
    if (n < m) m = n;
    if (m == 0) return 0;
    for (int i = 0; i < m; i++) {
      final ca = a[i];
      final cb = b[i];
      if ((ca.compareTo('0') >= 0 && ca.compareTo('9') <= 0) ||
          (cb.compareTo('0') >= 0 && cb.compareTo('9') <= 0) ||
          ca != cb) {
        return i;
      }
    }
    return m;
  }

  static int _digits(String s) {
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (c.compareTo('0') < 0 || c.compareTo('9') > 0) return i;
    }
    return s.length;
  }

  // ==================== 转换：响应 → VO ====================
  static String getCompletePath(String? parentPath, String name) {
    if (parentPath == null || parentPath == '/' || parentPath.isEmpty) {
      return '/$name';
    }
    return '$parentPath/$name';
  }

  /// 返回 AlistFileItem（与 models/alist_file_item.dart 保持一致）
  static AlistFileItem respContentToVO(
    String parentPath,
    String provider,
    AlistFileListContent resp,
  ) {
    final modifyTime = parseModifiedTime(resp.modified);
    final modifyTimeStr = getReformatTime(modifyTime, resp.modified);
    return AlistFileItem(
      name: resp.name,
      path: getCompletePath(parentPath, resp.name),
      size: resp.isDir ? null : resp.size,
      sizeDesc: resp.isDir ? null : formatBytes(resp.size ?? 0),
      isDir: resp.isDir,
      modified: modifyTimeStr,
      modifiedMilliseconds: modifyTime?.millisecondsSinceEpoch ?? -1,
      sign: resp.sign,
      thumb: resp.isDir ? '' : resp.thumb,
      typeInt: resp.type,
      type: getFileType(resp.isDir, resp.name),
      provider: provider,
    );
  }
}
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;
import 'package:saver_gallery/saver_gallery.dart';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';

abstract final class ImageUtils {
  static final _suffixRegex = RegExp(
    r'\.(jpg|jpeg|png|webp|gif|avif)$',
    caseSensitive: false,
  );

  // 支持缩略图处理的域名列表
  static const _supportedDomains = [
    'i0.hdslb.com',
    'i1.hdslb.com',
    'i2.hdslb.com',
    'i3.hdslb.com',
    'i0.hdslb.com',
    'i1.hdslb.com',
    'i2.hdslb.com',
    'i3.hdslb.com',
    // 可继续添加其他支持 @xxq.webp 格式的域名
  ];

  static final _thumbRegex = RegExp(
    r'(@(\d+[a-z]_?)*)(\..*)?$',
    caseSensitive: false,
  );

  static String safeThumbnailUrl(String? src) {
    if (src != null && _suffixRegex.hasMatch(src)) {
      return thumbnailUrl(src);
    }
    return src ?? '';
  }

  static String thumbnailUrl(String? src, [int maxQuality = 1]) {
    if (src == null || src.isEmpty) return '';

    // quality >= 100 时直接返回原始 URL（不压缩）
    if (maxQuality >= 100) return src;

    // 检查域名是否支持缩略图处理
    final uri = Uri.tryParse(src);
    if (uri == null) return src;

    final host = uri.host.toLowerCase();
    final isSupported = _supportedDomains.any((domain) => host.contains(domain));

    // 只有支持的域名才应用缩略图处理
    if (isSupported) {
      return _applyThumbnail(src, maxQuality);
    }

    // 其他域名：直接返回原始 URL
    return src;
  }

  static String _applyThumbnail(String src, int maxQuality) {
    maxQuality = math.max(maxQuality, 10);
    bool hasMatch = false;
    final result = src.splitMapJoin(
      _thumbRegex,
      onMatch: (match) {
        hasMatch = true;
        String suffix = match.group(3) ?? '.webp';
        return '${match.group(1)}_${maxQuality}q$suffix';
      },
      onNonMatch: (String str) => str,
    );
    if (!hasMatch) {
      return '$src@${maxQuality}q.webp';
    }
    return result;
  }

  /// 获取当前时间字符串（用于截图文件名）
  static String get time =>
      DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());

  /// 保存字节图片
  static Future<void> saveByteImg({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await SaverGallery.saveImage(
            bytes,
            fileName: fileName,
            albumPath: '源影/截图',
            skipIfExists: false,
          );
          SmartDialog.showToast('截图已保存到相册');
        } catch (e) {
          SmartDialog.showToast('保存失败: $e');
        }
      } else {
        try {
          final downloadsPath = _getDownloadsPath();
          if (downloadsPath != null) {
            final saveFile = File('$downloadsPath/$fileName');
            await file.copy(saveFile.path);
            SmartDialog.showToast('截图已保存到下载目录');
          } else {
            SmartDialog.showToast('截图已保存到临时目录: ${file.path}');
          }
        } catch (e) {
          SmartDialog.showToast('保存失败: $e');
        }
      }
    } catch (e) {
      SmartDialog.showToast('保存失败: $e');
    }
  }

  /// 图片分享
  static Future<void> onShareImg(String url) async {
    try {
      SmartDialog.showLoading();
      final response = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      SmartDialog.dismiss();

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = DateTime.now().millisecondsSinceEpoch.toString();
        final filePath = '${tempDir.path}/$fileName.jpg';
        final bytes = Uint8List.fromList(response.data as List<int>);
        final file = File(filePath)..writeAsBytesSync(bytes);

        await Share.shareXFiles(
          [XFile(filePath)],
          sharePositionOrigin: const ui.Rect.fromLTRB(0, 0, 1, 1),
        );
        await file.delete();
      } else {
        SmartDialog.showToast('分享失败');
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('分享失败: $e');
    }
  }

  /// 下载图片（单张或多张）
  static Future<bool> downloadImg(List<String> imgList) async {
    try {
      SmartDialog.showLoading(msg: '正在下载');
      int successCount = 0;

      for (final url in imgList) {
        try {
          final response = await Dio().get(
            url,
            options: Options(responseType: ResponseType.bytes),
          );

          if (response.statusCode == 200) {
            final bytes = Uint8List.fromList(response.data as List<int>);
            final fileName = DateTime.now().millisecondsSinceEpoch.toString();

            if (Platform.isAndroid || Platform.isIOS) {
              await SaverGallery.saveImage(
                bytes,
                fileName: fileName,
                albumPath: '源影/图片',
                skipIfExists: false,
              );
            } else {
              final downloadsPath = _getDownloadsPath();
              if (downloadsPath != null) {
                final file = File('$downloadsPath/$fileName.jpg')
                  ..writeAsBytesSync(bytes);
              }
            }
            successCount++;
          }
        } catch (e) {
          // 单张失败继续下一张
        }
      }

      SmartDialog.dismiss();
      if (successCount == imgList.length) {
        SmartDialog.showToast('全部保存成功');
        return true;
      } else if (successCount > 0) {
        SmartDialog.showToast('保存成功 $successCount/${imgList.length} 张');
        return true;
      } else {
        SmartDialog.showToast('保存失败');
        return false;
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('保存失败: $e');
      return false;
    }
  }

  static String? _getDownloadsPath() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] != null
          ? '${Platform.environment['USERPROFILE']}\\Downloads'
          : null;
    } else if (Platform.isMacOS || Platform.isLinux) {
      return Platform.environment['HOME'] != null
          ? '${Platform.environment['HOME']}/Downloads'
          : null;
    }
    return null;
  }
}
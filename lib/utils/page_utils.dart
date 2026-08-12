import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/utils/url_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/rendering.dart' show RelativeRect;

abstract final class PageUtils {
  static void toDupNamed(
    String page, {
    dynamic arguments,
    Map<String, String>? parameters,
    bool off = false,
  }) {
    if (off) {
      Get.offNamed(
        page,
        arguments: arguments,
        parameters: parameters,
        preventDuplicates: false,
      );
    } else {
      Get.toNamed(
        page,
        arguments: arguments,
        parameters: parameters,
        preventDuplicates: false,
      );
    }
  }

  static Future<void> handleWebview(
    String url, {
    bool off = false,
    Map? parameters,
  }) async {
    toDupNamed(
      '/webview',
      parameters: {
        'url': url,
        ...?parameters,
      },
      off: off,
    );
  }

  static Future<void> launchURL(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        SmartDialog.showToast('无法打开链接: $url');
      }
    } catch (e) {
      SmartDialog.showToast('打开链接失败: $e');
    }
  }

  /// 计算菜单位置（用于桌面右键菜单）
  static RelativeRect menuPosition(Offset offset) {
    return RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx, 0);
  }

  /// 显示视频底部弹窗
  static Future<void> showVideoBottomSheet({
    required BuildContext context,
    required Widget child,
    double maxWidth = 500,
    bool isPortrait = true,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      constraints: BoxConstraints(
        maxWidth: maxWidth,
      ),
      builder: (context) {
        return Container(
          margin: isPortrait
              ? EdgeInsets.zero
              : const EdgeInsets.only(left: 40, top: 40, bottom: 40),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: isPortrait
                ? const BorderRadius.vertical(top: Radius.circular(18))
                : const BorderRadius.horizontal(left: Radius.circular(18)),
          ),
          child: child,
        );
      },
    );
  }
}
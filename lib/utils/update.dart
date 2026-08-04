import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/utils/storage_manager.dart';

/// 更新检查工具（简化版）
abstract final class Update {
  /// 检查更新
  /// [isAuto] 是否为自动检查（启动时）
  static Future<void> checkUpdate([bool isAuto = true]) async {
    // 模拟检查：假设永远有新版本（演示效果）
    // 真实场景可替换为 GitHub API 请求
    final hasNewVersion = true;

    if (!hasNewVersion) {
      if (!isAuto) {
        SmartDialog.showToast('已是最新版本');
      }
      return;
    }

    // 显示更新弹窗
    SmartDialog.show(
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: colorScheme.surface,
          title: Row(
            children: [
              const Text('🎉 发现新版本 '),
              const Spacer(),
              GestureDetector(
                onTap: SmartDialog.dismiss,
                child: Icon(Icons.close, size: 20, color: colorScheme.outline),
              ),
            ],
          ),
          content: SizedBox(
            height: 200,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'v2.0.0',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• 优化播放体验\n'
                    '• 修复已知问题\n'
                    '• 新增更多接口支持',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (isAuto)
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                  // 关闭自动更新
                  StorageManager.setSetting(SettingBoxKey.autoUpdate, false);
                },
                child: Text(
                  '不再提醒',
                  style: TextStyle(color: colorScheme.outline),
                ),
              ),
            TextButton(
              onPressed: SmartDialog.dismiss,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
                // 跳转到更新页面（可替换为真实下载链接）
                SmartDialog.showToast('请前往 GitHub Releases 下载最新版');
              },
              style: TextButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('去更新'),
            ),
          ],
        );
      },
    );
  }
}
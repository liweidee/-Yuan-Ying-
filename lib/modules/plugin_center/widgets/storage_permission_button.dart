// lib/modules/plugin_center/widgets/storage_permission_button.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 顶部固定「文件访问」按钮。
/// 点击：已授权 → Toast；未授权 → 拉起系统授权页。
/// 仅 Android 显示；其他平台返回 SizedBox.shrink()。
class StoragePermissionButton extends StatefulWidget {
  const StoragePermissionButton({super.key});

  @override
  State<StoragePermissionButton> createState() =>
      _StoragePermissionButtonState();
}

class _StoragePermissionButtonState extends State<StoragePermissionButton>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.yuanying/storage');

  final RxBool _granted = false.obs;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // 监听 App 生命周期：从系统设置页返回（resumed）时刷新授权态。
    // 原实现只在点击后 500ms 刷一次，用户在设置页里授权耗时超过 500ms
    // 就刷不到新状态，需重新进入插件中心才会更新——本 Observer 修复此问题。
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('isExternalStorageManager') ??
              false;
      if (!mounted) return;
      _granted.value = ok;
    } catch (_) {
      if (!mounted) return;
      _granted.value = false;
    }
  }

  Future<void> _onTap() async {
    if (_checking) return;
    _checking = true;
    try {
      final ok =
          await _channel.invokeMethod<bool>('isExternalStorageManager') ??
              false;
      _granted.value = ok;
      if (ok) {
        SmartDialog.showToast('已授权文件访问');
        return;
      }
      await _channel.invokeMethod('requestAllFilesAccess');
      // 500ms 刷新覆盖「用户快速返回」的极小概率路径；
      // 主路径靠 didChangeAppLifecycleState(resumed) 兜底
      Future.delayed(const Duration(milliseconds: 500), _refreshStatus);
    } catch (e) {
      SmartDialog.showToast('授权检查失败：$e');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final granted = _granted.value;
      return IconButton(
        tooltip: granted ? '文件访问已授权' : '文件访问未授权（用于导入本地包/备份恢复）',
        icon: Icon(
          granted ? Icons.gpp_good : Icons.gpp_bad,
          size: 20,
          color: granted ? colorScheme.primary : colorScheme.outline,
        ),
        onPressed: _onTap,
      );
    });
  }
}
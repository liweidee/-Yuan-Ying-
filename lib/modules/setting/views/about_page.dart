import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

import 'package:yuanying/build_config.dart';
import 'package:yuanying/common/assets.dart';
import 'package:yuanying/common/extensions/num_ext.dart';
import 'package:yuanying/common/widgets/dialog/backup_dialog.dart';
import 'package:yuanying/common/widgets/dialog/dialog.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/services/debug_log_service.dart';
import 'package:yuanying/services/system_log_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/cache_manager.dart';
import 'package:yuanying/utils/page_utils.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/update.dart';
import 'package:yuanying/utils/utils.dart';

/// 重置操作的三种粒度
enum _ResetAction { settings, userData, all }

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.showAppBar = true});
  final bool showAppBar;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final String _version = BuildConfig.versionName;
  final RxString cacheSize = ''.obs;
  int _pressCount = 0;

  @override
  void initState() {
    super.initState();
    _getCacheSize();
  }

  @override
  void dispose() {
    cacheSize.close();
    super.dispose();
  }

  Future<void> _getCacheSize() async {
    final size = await CacheManager.loadApplicationCache();
    if (mounted) {
      cacheSize.value = CacheManager.formatSize(size);
    }
  }

  void _showDebugDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        constraints: Style.dialogFixedConstraints,
        content: TextField(
          autofocus: true,
          onSubmitted: (value) {
            Get.back();
            if (value.isNotEmpty) {
              PageUtils.handleWebview(value);
            }
          },
        ),
      ),
    );
  }

  // ============================================================
  // 重置相关
  // ============================================================
  Future<void> _showResetDialog(BuildContext context) async {
    final action = await showDialog<_ResetAction>(
      context: context,
      builder: (ctx) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重置'),
        children: [
          _buildResetOption(
            ctx,
            title: '重置设置',
            subtitle: '主题、播放器、弹幕、服务器、站点等配置',
            action: _ResetAction.settings,
            icon: Icons.tune,
          ),
          _buildResetOption(
            ctx,
            title: '重置用户数据',
            subtitle: '收藏、历史、观看进度、自定义站点',
            action: _ResetAction.userData,
            icon: Icons.folder_delete_outlined,
          ),
          const Divider(height: 1),
          _buildResetOption(
            ctx,
            title: '重置全部',
            subtitle: '清空所有配置与数据',
            action: _ResetAction.all,
            icon: Icons.delete_forever_outlined,
            danger: true,
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;
    await _confirmAndReset(action);
  }

  Widget _buildResetOption(
    BuildContext ctx, {
    required String title,
    required String subtitle,
    required _ResetAction action,
    required IconData icon,
    bool danger = false,
  }) {
    final theme = Theme.of(ctx);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.primary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: danger ? color : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
      ),
      onTap: () => Navigator.of(ctx).pop(action),
    );
  }

  Future<void> _confirmAndReset(_ResetAction action) async {
    String label;
    switch (action) {
      case _ResetAction.settings:
        label = '设置';
        break;
      case _ResetAction.userData:
        label = '用户数据';
        break;
      case _ResetAction.all:
        label = '全部数据';
        break;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认重置？'),
        content: Text('将清空$label，此操作不可撤销。\n\n重置后部分设置需重启应用才能生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    SmartDialog.showLoading(msg: '正在重置...');
    try {
      await _performReset(action);
      if (!mounted) return;
      SmartDialog.dismiss();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('重置完成'),
          content: const Text('请重启应用以完全生效。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      SmartDialog.dismiss();
      if (!mounted) return;
      SmartDialog.showToast('重置失败：$e');
    }
  }

  Future<void> _performReset(_ResetAction action) async {
    Future<void> resetSettings() async {
      // setting Box
      await GStorage.setting.clear();
      // app_settings Box
      await StorageManager.resetSettingBox();
      // video_settings Box
      await Hive.box('video_settings').clear();
    }

    Future<void> resetUserData() async {
      // 收藏
      await GStorage.video.clear();
      // 搜索历史
      await GStorage.historyWord.clear();
      // 观看进度
      await GStorage.watchProgress.clear();
      // 自定义站点
      await GStorage.sitesBox.clear();
      // 本地配置包
      await GStorage.configPackageBox.clear();
    }

    /// 额外清理"缓存类 Box"（仅在"重置全部"时使用）
    Future<void> resetCacheBoxes() async {
      try {
        await Hive.box('tmdb_matches').clear();
      } catch (_) {
        // Box 未打开时忽略
      }
    }

    switch (action) {
      case _ResetAction.settings:
        await resetSettings();
        break;
      case _ResetAction.userData:
        await resetUserData();
        break;
      case _ResetAction.all:
        await resetSettings();
        await resetUserData();
        await resetCacheBoxes();
        break;
    }
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    final subTitleStyle = TextStyle(fontSize: 13, color: outline);
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);

    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('关于')) : null,
      resizeToAvoidBottomInset: false,
      body: ListView(
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        children: [
          // ===== Logo（隐藏调试入口）=====
          GestureDetector(
            onTap: () {
              if (++_pressCount == 5) {
                _pressCount = 0;
                _showDebugDialog();
              }
            },
            onSecondaryTap: PlatformUtils.isDesktop ? _showDebugDialog : null,
            child: Image.asset(
              width: 150,
              height: 150,
              excludeFromSemantics: true,
              cacheWidth: 150.cacheSize(context),
              Assets.logo,
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.broken_image, size: 150, color: Colors.grey);
              },
            ),
          ),

          // ===== 应用名称 + 标语 =====
          ListTile(
            title: Text(
              AppConstants.appName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(height: 2),
            ),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '使用Flutter开发的影视聚合客户端',
                  style: TextStyle(color: outline),
                ),
              ],
            ),
          ),

          // ===== 当前版本 =====
          ListTile(
            onTap: () => Update.checkUpdate(false),
            onLongPress: () => Utils.copyText(_version),
            title: const Text('当前版本'),
            leading: const Icon(Icons.commit_outlined),
            trailing: Text(_version, style: subTitleStyle),
          ),

          // ===== 构建信息 =====
          ListTile(
            title: Text(
              '版本号: $_version (code: ${BuildConfig.versionCode})',
              style: const TextStyle(fontSize: 14),
            ),
            leading: const Icon(Icons.info_outline),
            onLongPress: () => Utils.copyText(_version),
          ),

          Divider(
            thickness: 1,
            height: 30,
            color: theme.colorScheme.outlineVariant,
          ),

          // ===== Android: 打开受支持的链接 =====
          if (Platform.isAndroid)
            ListTile(
              onTap: () => SmartDialog.showToast('请前往系统设置-应用-打开受支持的链接'),
              leading: const Icon(Icons.link_outlined),
              title: const Text('打开受支持的链接'),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            ),

          // ===== 调试日志开关 =====
          Obx(() {
            final enabled = DebugLogService.instance.enabled.value;
            return ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('调试日志'),
              subtitle: Text(
                enabled ? '已开启，正在记录请求日志' : '已关闭',
                style: subTitleStyle,
              ),
              trailing: Switch(
                value: enabled,
                onChanged: (v) {
                  DebugLogService.instance.setEnabled(v);
                  if (Get.isRegistered<SystemLogService>()) {
                    Get.find<SystemLogService>().setEnabled(v);
                  }
                },
              ),
            );
          }),

          // ===== 系统日志入口 =====
          Obx(() {
            final enabled = DebugLogService.instance.enabled.value;
            if (!enabled) return const SizedBox.shrink();

            final count = Get.isRegistered<SystemLogService>()
                ? Get.find<SystemLogService>().logCount.value
                : 0;
            return ListTile(
              onTap: () => Get.toNamed('/systemLog'),
              onLongPress: () async {
                if (Get.isRegistered<SystemLogService>()) {
                  await Get.find<SystemLogService>().clearLogs();
                  SmartDialog.showToast('日志已清除');
                }
              },
              leading: const Icon(Icons.terminal_outlined),
              title: const Text('系统日志'),
              subtitle: Text(
                '共 $count 条日志记录（广告过滤 / 代理 / 播放器等）',
                style: subTitleStyle,
              ),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            );
          }),

          // ===== 接口日志入口 =====
          Obx(() {
            final enabled = DebugLogService.instance.enabled.value;
            if (!enabled) return const SizedBox.shrink();

            final count = DebugLogService.instance.logCount.value;
            return ListTile(
              onTap: () => Get.toNamed('/debugLogs'),
              onLongPress: () async {
                await DebugLogService.instance.clearLogs();
                SmartDialog.showToast('日志已清除');
              },
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('查看日志'),
              subtitle: Text(
                '共 $count 条日志记录',
                style: subTitleStyle,
              ),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            );
          }),

          // ===== 猫影视调试日志 =====
          Obx(() {
            final isCatVod =
                Get.find<SourceManager>().currentConfigType.value == 'catvod';
            if (!isCatVod) return const SizedBox.shrink();

            return ListTile(
              onTap: () => Get.toNamed('/catvodLog'),
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('猫影视日志'),
              subtitle: Text(
                '查看 Node.js 运行日志',
                style: subTitleStyle,
              ),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            );
          }),

          // ===== 清除缓存 =====
          ListTile(
            onTap: () async {
              if (cacheSize.value.isEmpty) return;
              final confirmed = await showConfirmDialog(
                context: context,
                title: const Text('提示'),
                content: const Text('该操作将清除图片及网络请求缓存数据，确认清除？'),
              );
              if (!confirmed) return;
              SmartDialog.showLoading(msg: '正在清除...');
              try {
                await CacheManager.clearLibraryCache();
                SmartDialog.showToast('清除成功');
              } catch (e) {
                SmartDialog.showToast(e.toString());
              } finally {
                SmartDialog.dismiss();
                await _getCacheSize();
              }
            },
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            subtitle: Obx(
              () => Text(
                '应用缓存 ${cacheSize.value}',
                style: subTitleStyle,
              ),
            ),
          ),

          // ===== 备份与恢复（ZIP）=====
          ListTile(
            title: const Text('备份与恢复'),
            subtitle: const Text(
              '导出/导入所有设置为 ZIP 文件',
              style: TextStyle(fontSize: 12),
            ),
            leading: const Icon(Icons.backup_outlined),
            onTap: () => showBackupDialog(context),
          ),

          // ===== 重置所有设置 =====
          ListTile(
            title: const Text('重置所有设置'),
            leading: const Icon(Icons.settings_backup_restore_outlined),
            onTap: () => _showResetDialog(context),
          ),
        ],
      ),
    );
  }
}
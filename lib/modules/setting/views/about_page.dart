import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/build_config.dart';
import 'package:yuanying/common/assets.dart';
import 'package:yuanying/common/widgets/dialog/dialog.dart';
import 'package:yuanying/common/extensions/num_ext.dart';
import 'package:yuanying/core/constants/app_constants.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/services/debug_log_service.dart';
import 'package:yuanying/utils/cache_manager.dart';
import 'package:yuanying/utils/page_utils.dart';
import 'package:yuanying/utils/platform_utils.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:yuanying/utils/update.dart';
import 'package:yuanying/utils/utils.dart';
import 'package:yuanying/common/widgets/dialog/export_import.dart';
import 'package:yuanying/utils/device_utils.dart';
import 'package:yuanying/t4/services/source_manager.dart';

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
          // =============================================================
          // Logo（隐藏调试入口）
          // =============================================================
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

          // =============================================================
          // 应用名称 + 标语
          // =============================================================
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
                // const Icon(Icons.accessibility_new, size: 18),
              ],
            ),
          ),

          // =============================================================
          // 当前版本（点击检查更新，长按复制）
          // =============================================================
          ListTile(
            onTap: () => Update.checkUpdate(false),
            onLongPress: () => Utils.copyText(_version),
            title: const Text('当前版本'),
            leading: const Icon(Icons.commit_outlined),
            trailing: Text(_version, style: subTitleStyle),
          ),

          // =============================================================
          // 构建信息（长按复制版本号）
          // =============================================================
          ListTile(
            title: Text(
              '版本号: $_version (code: ${BuildConfig.versionCode})',
              style: const TextStyle(fontSize: 14),
            ),
            leading: const Icon(Icons.info_outline),
            onLongPress: () => Utils.copyText(_version),
          ),

          Divider(thickness: 1, height: 30, color: theme.colorScheme.outlineVariant),

          // =============================================================
          // Android: 打开受支持的链接
          // =============================================================
          if (Platform.isAndroid)
            ListTile(
              onTap: () => SmartDialog.showToast('请前往系统设置-应用-打开受支持的链接'),
              leading: const Icon(Icons.link_outlined),
              title: const Text('打开受支持的链接'),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            ),

          // =============================================================
          // 调试日志 - 开关（独立，始终显示）
          // =============================================================
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
                onChanged: (v) => DebugLogService.instance.setEnabled(v),
              ),
            );
          }),

          // =============================================================
          // 查看日志入口（仅在开关开启时显示）
          // =============================================================
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

          // 猫影视调试日志
          Obx(() {
            final isCatVod = Get.find<SourceManager>().currentConfigType.value == 'catvod';
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

          // =============================================================
          // 清除缓存
          // =============================================================
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
                '图片及网络缓存 ${cacheSize.value}',
                style: subTitleStyle,
              ),
            ),
          ),

          // =============================================================
          // 导入/导出设置
          // =============================================================
          ListTile(
            title: const Text('导入/导出设置'),
            leading: const Icon(Icons.import_export_outlined),
            onTap: () => showImportExportDialog<String>(
              context,
              title: '设置',
              localFileName: () => 'setting_${DeviceUtils.platformName}',
              onExport: GStorage.exportAllSettings,
              onImport: GStorage.importAllSettings,
            ),
          ),

          // =============================================================
          // 重置所有设置
          // =============================================================
          ListTile(
            title: const Text('重置所有设置'),
            leading: const Icon(Icons.settings_backup_restore_outlined),
            onTap: () => showDialog(
              context: context,
              builder: (context) {
                return SimpleDialog(
                  clipBehavior: Clip.hardEdge,
                  title: const Text('是否重置所有设置？'),
                  children: [
                    ListTile(
                      dense: true,
                      onTap: () async {
                        Get.back();
                        await GStorage.setting.clear();
                        await GStorage.video.clear();
                        SmartDialog.showToast('重置成功');
                      },
                      title: const Text('重置可导出的设置', style: TextStyle(fontSize: 15)),
                    ),
                    ListTile(
                      dense: true,
                      onTap: () async {
                        Get.back();
                        await GStorage.setting.clear();
                        await GStorage.video.clear();
                        await GStorage.historyWord.clear();
                        await GStorage.watchProgress.clear();
                        await GStorage.sitesBox.clear();
                        await GStorage.configPackageBox.clear();
                        SmartDialog.showToast('重置成功');
                      },
                      title: const Text('重置所有数据', style: TextStyle(fontSize: 15)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
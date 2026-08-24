import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yuanying/modules/setting/controllers/tmdb_config_controller.dart';
import 'package:yuanying/modules/setting/views/tmdb_match_page.dart';

class TmdbConfigPage extends StatelessWidget {
  const TmdbConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(TmdbConfigController());
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('TMDB 配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colorScheme.onSurface),
          onPressed: () => Get.back(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.safeSpace, Style.safeSpace, 120),
            children: [
              _buildGlobalSwitch(context, theme, controller),
              const SizedBox(height: Style.cardSpace),
              _buildSourceMatchCard(context, theme, controller),
              const SizedBox(height: Style.cardSpace),
              _buildAccessTokenCard(context, theme, controller),
              const SizedBox(height: Style.cardSpace),
              _buildProxyCard(context, theme, controller),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomActions(context, theme, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalSwitch(BuildContext context, ThemeData theme, TmdbConfigController controller) {
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.movie, color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '启用 TMDB 集成',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '开启后视频详情页将显示 TMDB 剧集等信息',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Obx(() => Switch(
              value: controller.enabled.value,
              onChanged: (v) {
                controller.enabled.value = v;
                controller.saveSettings();
              },
            )),
          ],
        ),
      ),
    );
  }

  // ----- 站源匹配卡片 -----
  Widget _buildSourceMatchCard(
    BuildContext context,
    ThemeData theme,
    TmdbConfigController controller,
  ) {
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      color: colorScheme.surface,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () {
          if (!controller.enabled.value) {
            SmartDialog.showToast('请先开启 TMDB 集成总开关');
            return;
          }
          Get.to(() => const TmdbMatchPage());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_open, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '站源匹配管理',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Obx(() {
                      final enabledCount = controller.getEnabledCount();
                      final totalCount = controller.getSites().length;
                      return Text(
                        '已启用 $enabledCount / $totalCount 个站源',
                        style: TextStyle(fontSize: 13, color: colorScheme.outline),
                      );
                    }),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  // ----- Access Token卡片（使用controller.tokenController）-----
  Widget _buildAccessTokenCard(
    BuildContext context,
    ThemeData theme,
    TmdbConfigController controller,
  ) {
    final colorScheme = theme.colorScheme;
    final obscureText = true.obs;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key, color: Colors.green, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Access Token',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    const url = 'https://www.themoviedb.org/settings/api';
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url));
                    } else {
                      SmartDialog.showToast('无法打开链接');
                    }
                  },
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '获取',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              return TextField(
                controller: controller.tokenController,
                obscureText: obscureText.value,
                style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureText.value ? Icons.visibility_off : Icons.visibility,
                      color: colorScheme.outline,
                    ),
                    onPressed: () => obscureText.toggle(),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ----- 代理设置卡片（使用controller的apiProxyController和imageProxyController）-----
  Widget _buildProxyCard(
    BuildContext context,
    ThemeData theme,
    TmdbConfigController controller,
  ) {
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lan, color: colorScheme.onSurface, size: 22),
                const SizedBox(width: 8),
                Text(
                  '代理设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '国内用户需设置代理才能访问 TMDB，留空则使用官方地址',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
            const SizedBox(height: 16),
            _buildProxySubSection(
              context: context,
              theme: theme,
              label: 'API 代理',
              controller: controller.apiProxyController,
              options: TmdbConfigController.apiProxyOptions,
              onChipTap: controller.setApiProxy,
            ),
            const SizedBox(height: 20),
            _buildProxySubSection(
              context: context,
              theme: theme,
              label: '图片代理',
              controller: controller.imageProxyController,
              options: TmdbConfigController.imageProxyOptions,
              onChipTap: controller.setImageProxy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProxySubSection({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required void Function(String) onChipTap,
  }) {
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: IconButton(
              icon: Icon(Icons.clear, color: colorScheme.outline, size: 18),
              onPressed: () {
                controller.clear();
                // 同步更新Rx（因监听器已绑定，会自动更新）
                // 但清除后需手动触发，因为controller.clear()不会触发listener？
                // 实际上controller.clear()会触发text变化，listener会响应。
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: options.map((url) {
            return ActionChip(
              label: Text(_getOptionLabel(url, options), style: TextStyle(fontSize: 12)),
              onPressed: () => onChipTap(url),
              backgroundColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getOptionLabel(String url, List<String> options) {
    const labels = ['官方地址', 'Proxy 1', 'Proxy 2'];
    final index = options.indexOf(url);
    return index >= 0 && index < labels.length ? labels[index] : url;
  }

  // ----- 底部操作栏（保持不变）-----
  Widget _buildBottomActions(
    BuildContext context,
    ThemeData theme,
    TmdbConfigController controller,
  ) {
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认清除'),
                    content: const Text('确定要清除所有 TMDB 配置吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await controller.clearSettings();
                  SmartDialog.showToast('已清除所有配置');
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green,
                side: BorderSide(color: Colors.green.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('清除配置'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () async {
                await controller.saveSettings();
                SmartDialog.showToast('配置已保存');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text('保存配置'),
            ),
          ),
        ],
      ),
    );
  }
}
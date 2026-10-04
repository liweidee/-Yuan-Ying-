import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/common/widgets/dialog/select_dialog.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/subtitle_translation/services/subtitle_translation_service.dart';
import 'package:yuanying/modules/subtitle_translation/services/translation_engine.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class SubtitleTranslationPage extends StatefulWidget {
  const SubtitleTranslationPage({super.key});

  @override
  State<SubtitleTranslationPage> createState() =>
      _SubtitleTranslationPageState();
}

class _SubtitleTranslationPageState extends State<SubtitleTranslationPage> {
  late bool _enabled;
  late String _targetLang;
  late String _provider;
  late String _baiduModelType;
  late bool _autoApply;

  final _baiduAppIdCtrl = TextEditingController();
  final _baiduSecretCtrl = TextEditingController();
  final _azureKeyCtrl = TextEditingController();
  final _azureRegionCtrl = TextEditingController();

  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _enabled = PlayerPref.subtitleTranslationEnabled;
    _targetLang = PlayerPref.subtitleTranslationTargetLang;
    _provider = PlayerPref.subtitleTranslationProvider;
    _baiduModelType = PlayerPref.subtitleTranslationBaiduModel;
    _autoApply = PlayerPref.subtitleTranslationAutoApply;
    _baiduAppIdCtrl.text = PlayerPref.subtitleTranslationBaiduAppId;
    _baiduSecretCtrl.text = PlayerPref.subtitleTranslationBaiduSecret;
    _azureKeyCtrl.text = PlayerPref.subtitleTranslationAzureKey;
    _azureRegionCtrl.text = PlayerPref.subtitleTranslationAzureRegion;
  }

  @override
  void dispose() {
    _baiduAppIdCtrl.dispose();
    _baiduSecretCtrl.dispose();
    _azureKeyCtrl.dispose();
    _azureRegionCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final engine = SubtitleTranslationService.instance.getActiveEngine();
      if (!engine.isConfigured) {
        SmartDialog.showToast(engine.configurationError ?? '配置不完整');
        return;
      }
      final result = await engine.testConnection();
      SmartDialog.showToast('连接成功：${engine.displayName} → $result');
    } catch (e) {
      SmartDialog.showToast('连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理翻译缓存'),
        content: const Text('确定要删除所有已缓存的翻译结果吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await SubtitleTranslationService.instance.clearAllCache();
    if (!mounted) return;
    SmartDialog.showToast('已清理 $count 份翻译缓存');
  }

  // ============================================================
  // build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('字幕翻译'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Style.safeSpace),
        children: [
          // ============================================================
          // 分组 1：功能开关
          // ============================================================
          _buildSectionTitle('功能开关'),
          _buildSwitchItem(
            icon: Icons.translate,
            title: '启用字幕翻译',
            subtitle: '将外挂字幕文本发送到在线翻译服务',
            value: _enabled,
            onChanged: (v) {
              PlayerPref.subtitleTranslationEnabled = v;
              _enabled = v;
              _refresh();
            },
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            _buildSwitchItem(
              icon: Icons.swap_horiz,
              title: '翻译完成后自动切换',
              subtitle: '翻译结束后自动把译文加载为当前字幕',
              value: _autoApply,
              onChanged: (v) {
                PlayerPref.subtitleTranslationAutoApply = v;
                _autoApply = v;
                _refresh();
              },
            ),
          ],
          const SizedBox(height: 24),

          // 总开关关闭时，后面的所有分组全部收起
          if (!_enabled) ...[
            _buildInfoCard(
              icon: Icons.info_outline,
              content: '开启后可翻译当前已加载的字幕。字幕文本会上传到第三方翻译服务，'
                  '请注意隐私。支持百度翻译与微软 Azure 翻译。',
            ),
          ] else ...[
            // ============================================================
            // 分组 2：翻译目标
            // ============================================================
            _buildSectionTitle('翻译目标'),
            _buildSelectItem<String>(
              icon: Icons.language,
              title: '翻译目标语言',
              subtitle: TranslationLanguage.findByCode(_targetLang).name,
              values: TranslationLanguage.supportedLanguages
                  .map((e) => e.code)
                  .toList(),
              displayValues: TranslationLanguage.supportedLanguages
                  .map((e) => e.name)
                  .toList(),
              currentValue: _targetLang,
              onSelected: (v) {
                PlayerPref.subtitleTranslationTargetLang = v;
                _targetLang = v;
                _refresh();
              },
            ),
            const SizedBox(height: 24),

            // ============================================================
            // 分组 3：在线服务配置
            // ============================================================
            _buildSectionTitle('在线服务配置'),

            // 3.1 服务提供商（顶层选择）
            _buildSelectItem<String>(
              icon: Icons.cloud_outlined,
              title: '服务提供商',
              subtitle: _provider == 'baidu' ? '百度翻译' : '微软 Azure 翻译',
              values: const ['baidu', 'azure'],
              displayValues: const ['百度翻译', '微软 Azure 翻译'],
              currentValue: _provider,
              onSelected: (v) {
                PlayerPref.subtitleTranslationProvider = v;
                _provider = v;
                _refresh();
              },
            ),
            const SizedBox(height: 8),

            // 3.2 提供商的子配置（整体一张卡片，内部按提供商动态渲染）
            _buildProviderConfigCard(),
            const SizedBox(height: 8),

            // 3.3 测试连接
            _buildNavigateItem(
              icon: Icons.wifi_tethering,
              title: '测试连接',
              subtitle: _testing
                  ? '正在测试…'
                  : '发送一条测试文本验证配置是否可用',
              onTap: _testing ? () {} : _testConnection,
            ),
            const SizedBox(height: 24),

            // ============================================================
            // 分组 4：数据管理
            // ============================================================
            _buildSectionTitle('数据管理'),
            _buildNavigateItem(
              icon: Icons.cleaning_services_outlined,
              title: '清理翻译缓存',
              subtitle: '删除全部已缓存的翻译结果',
              onTap: _clearCache,
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ============================================================
  // 分组标题
  // ============================================================
  Widget _buildSectionTitle(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  // ============================================================
  // 提供商子配置卡片
  //
  // 内部按当前提供商动态渲染，所有子项共享一张卡片容器，
  // 用 Divider 分隔，视觉上表达"这是同一个提供商下的配置"。
  // ============================================================
  Widget _buildProviderConfigCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: Style.mdRadius,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_provider == 'baidu') ...[
            // 百度：模式 + APP ID + 密钥
            _buildInnerSelectTile<String>(
              icon: Icons.auto_awesome,
              title: '翻译模式',
              subtitle: _baiduModelType == 'llm' ? '大模型（更贴语境）' : '通用',
              values: const ['llm', 'nmt'],
              displayValues: const ['大模型', '通用'],
              currentValue: _baiduModelType,
              onSelected: (v) {
                PlayerPref.subtitleTranslationBaiduModel = v;
                _baiduModelType = v;
                _refresh();
              },
            ),
            _divider(),
            _buildInnerTextFieldTile(
              icon: Icons.vpn_key_outlined,
              title: 'APP ID',
              hint: '百度翻译开放平台「开发者信息」中的 APP ID',
              controller: _baiduAppIdCtrl,
              onChanged: (v) =>
                  PlayerPref.subtitleTranslationBaiduAppId = v,
            ),
            _divider(),
            _buildInnerTextFieldTile(
              icon: Icons.password,
              title: '密钥',
              hint: '百度翻译开放平台「开发者信息」中的密钥',
              controller: _baiduSecretCtrl,
              obscure: true,
              onChanged: (v) =>
                  PlayerPref.subtitleTranslationBaiduSecret = v,
            ),
          ] else ...[
            // Azure：密钥 + 区域
            _buildInnerTextFieldTile(
              icon: Icons.vpn_key_outlined,
              title: '密钥',
              hint: 'Azure 翻译服务的 Key',
              controller: _azureKeyCtrl,
              obscure: true,
              onChanged: (v) => PlayerPref.subtitleTranslationAzureKey = v,
            ),
            _divider(),
            _buildInnerTextFieldTile(
              icon: Icons.location_on_outlined,
              title: '位置 / 区域',
              hint: '如 eastasia',
              controller: _azureRegionCtrl,
              onChanged: (v) =>
                  PlayerPref.subtitleTranslationAzureRegion = v,
            ),
          ],
          // ===== 底部小字提示：输入自动保存 =====
          _divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '输入后会自动保存，无需手动确认',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 12,
      color: colorScheme.outlineVariant.withOpacity(0.3),
    );
  }

  // ============================================================
  // 卡片内部：select 项（无外层阴影、无 chevron 外框）
  // ============================================================
  Widget _buildInnerSelectTile<T>({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<T> values,
    required List<String> displayValues,
    required T currentValue,
    required ValueChanged<T> onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () async {
        final result = await showDialog<T>(
          context: context,
          builder: (context) => SelectDialog<T>(
            title: title,
            value: currentValue,
            values: values
                .asMap()
                .entries
                .map((e) => (e.value, displayValues[e.key]))
                .toList(),
          ),
        );
        if (result != null && mounted) {
          onSelected(result);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 卡片内部：文本输入项
  // ============================================================
  Widget _buildInnerTextFieldTile({
    required IconData icon,
    required String title,
    required String hint,
    required TextEditingController controller,
    bool obscure = false,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 通用组件（与 play_setting_page.dart 完全一致的视觉）
  // ============================================================

  Widget _buildIconContainer(IconData icon) {
    final colorScheme = ColorScheme.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.2),
        borderRadius: Style.mdRadius,
      ),
      child: Icon(icon, color: colorScheme.primary, size: 24),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: Style.mdRadius,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _buildIconContainer(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigateItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildIconContainer(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectItem<T>({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<T> values,
    required List<String> displayValues,
    required T currentValue,
    required ValueChanged<T> onSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: () async {
        final result = await showDialog<T>(
          context: context,
          builder: (context) => SelectDialog<T>(
            title: title,
            value: currentValue,
            values: values
                .asMap()
                .entries
                .map((e) => (e.value, displayValues[e.key]))
                .toList(),
          ),
        );
        if (result != null && mounted) {
          onSelected(result);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildIconContainer(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String content,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.2),
        borderRadius: Style.mdRadius,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              content,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 字幕网站配置页
class SubtitleSitePage extends StatefulWidget {
  const SubtitleSitePage({super.key});

  @override
  State<SubtitleSitePage> createState() => _SubtitleSitePageState();
}

class _SubtitleSitePageState extends State<SubtitleSitePage> {
  late final TextEditingController _assrtCtrl;
  late final TextEditingController _ostKeyCtrl;
  late final TextEditingController _ostUserCtrl;
  late final TextEditingController _ostPassCtrl;

  bool _xunleiEnabled = true;
  bool _subhdEnabled = true;
  bool _assrtEnabled = false;
  bool _ostEnabled = false;

  @override
  void initState() {
    super.initState();
    _xunleiEnabled = PlayerPref.xunleiEnabled;
    _subhdEnabled = PlayerPref.subhdEnabled;
    _assrtEnabled = PlayerPref.assrtEnabled;
    _ostEnabled = PlayerPref.openSubtitlesEnabled;
    _assrtCtrl = TextEditingController(text: PlayerPref.assrtToken);
    _ostKeyCtrl =
        TextEditingController(text: PlayerPref.openSubtitlesApiKey);
    _ostUserCtrl =
        TextEditingController(text: PlayerPref.openSubtitlesUsername);
    _ostPassCtrl =
        TextEditingController(text: PlayerPref.openSubtitlesPassword);
  }

  @override
  void dispose() {
    _assrtCtrl.dispose();
    _ostKeyCtrl.dispose();
    _ostUserCtrl.dispose();
    _ostPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('字幕网站')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '开启后可在视频详情的「更多设置 → 搜索字幕」中按站点搜索并挂载字幕。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: theme.colorScheme.outline,
              ),
            ),
          ),

          // ===== 迅雷看看（无需配置）=====
          _buildSiteCard(
            theme: theme,
            icon: Icons.bolt,
            title: '迅雷看看',
            subtitle: '中文资源最丰富 · 无需配置',
            enabled: _xunleiEnabled,
            onToggle: (v) {
              PlayerPref.xunleiEnabled = v;
              setState(() => _xunleiEnabled = v);
            },
            children: const [],
          ),
          const SizedBox(height: 12),

          // ===== SubHD =====
          _buildSiteCard(
            theme: theme,
            icon: Icons.subtitles,
            title: 'SubHD',
            subtitle: '中文字幕最多 · 无需账号',
            enabled: _subhdEnabled,
            onToggle: (v) {
              PlayerPref.subhdEnabled = v;
              setState(() => _subhdEnabled = v);
            },
            children: const [],
          ),
          const SizedBox(height: 12),

          // ===== 射手网 =====
          _buildSiteCard(
            theme: theme,
            icon: Icons.movie_filter_outlined,
            title: '射手网 (assrt.net)',
            subtitle: '中文字幕聚合搜索',
            enabled: _assrtEnabled,
            onToggle: (v) {
              PlayerPref.assrtEnabled = v;
              setState(() => _assrtEnabled = v);
            },
            children: [
              _buildInput(
                theme: theme,
                controller: _assrtCtrl,
                label: 'API Token',
                hint: '在 assrt.net 用户中心生成',
                obscure: true,
                icon: Icons.vpn_key_outlined,
              ),
              const SizedBox(height: 12),
              _buildHint(
                theme,
                '在 assrt.net 注册登录后，到「我的信息」页面复制 API Token。',
              ),
              const SizedBox(height: 12),
              _buildSaveButton(theme, () {
                PlayerPref.assrtToken = _assrtCtrl.text.trim();
                SmartDialog.showToast('射手网配置已保存');
              }),
            ],
          ),
          const SizedBox(height: 12),

          // ===== OpenSubtitles =====
          _buildSiteCard(
            theme: theme,
            icon: Icons.public,
            title: 'OpenSubtitles.com',
            subtitle: '外文字幕最全',
            enabled: _ostEnabled,
            onToggle: (v) {
              PlayerPref.openSubtitlesEnabled = v;
              setState(() => _ostEnabled = v);
            },
            children: [
              _buildInput(
                theme: theme,
                controller: _ostKeyCtrl,
                label: 'API Key',
                hint: '在 opensubtitles.com 控制台创建',
                obscure: true,
                icon: Icons.vpn_key_outlined,
              ),
              const SizedBox(height: 10),
              _buildInput(
                theme: theme,
                controller: _ostUserCtrl,
                label: '用户名（可选）',
                hint: '填写后可提升每日下载额度',
                obscure: false,
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 10),
              _buildInput(
                theme: theme,
                controller: _ostPassCtrl,
                label: '密码（可选）',
                hint: '配合用户名使用',
                obscure: true,
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 12),
              _buildHint(
                theme,
                '在 opensubtitles.com 注册后，到 个人资料 > API Consumers '
                '创建应用并复制 API Key。仅填 API Key 也能下载，'
                '但每日额度有限；填入账号密码可提升额度。',
              ),
              const SizedBox(height: 12),
              _buildSaveButton(theme, () {
                PlayerPref.openSubtitlesApiKey =
                    _ostKeyCtrl.text.trim();
                PlayerPref.openSubtitlesUsername =
                    _ostUserCtrl.text.trim();
                PlayerPref.openSubtitlesPassword =
                    _ostPassCtrl.text.trim();
                SmartDialog.showToast('OpenSubtitles 配置已保存');
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSiteCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: Style.mdRadius,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withOpacity(0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(
              height: 1,
              thickness: 0.5,
              color: theme.colorScheme.outline.withOpacity(0.15),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ],
      ),
    );
  }

  Widget _buildInput({
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.outline.withOpacity(0.6),
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.outline,
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest
            .withOpacity(0.4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: 1.5,
          ),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
      ),
    );
  }

  Widget _buildHint(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(ThemeData theme, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('保存'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}
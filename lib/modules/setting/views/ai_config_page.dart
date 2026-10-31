// lib/modules/setting/views/ai_config_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/setting/controllers/ai_config_controller.dart';
import 'package:yuanying/modules/setting/models/ai_config.dart';
import 'package:yuanying/modules/setting/widgets/model_picker_sheet.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  late final AiConfigController _controller;

  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  bool _obscureKey = true;
  bool _testing = false;
  bool _fetchingModels = false;
  double _maxToolCalls = 5;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(AiConfigController());
    final cfg = _controller.config.value;
    _baseUrlCtrl.text = cfg.apiBaseUrl;
    _apiKeyCtrl.text = cfg.apiKey;
    _modelCtrl.text = cfg.model;
    _maxToolCalls = cfg.maxToolCalls.toDouble();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  AiConfig _collect() => AiConfig(
        apiBaseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        model: _modelCtrl.text.trim().isEmpty
            ? 'gpt-4o-mini'
            : _modelCtrl.text.trim(),
        maxToolCalls: _maxToolCalls.round(),
      );

  Future<void> _onTest() async {
    if (_testing) return;
    setState(() => _testing = true);
    SmartDialog.showLoading(msg: '正在测试连接…');
    final r = await _controller.testConnection(_collect());
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _testing = false);
    if (r.ok) {
      SmartDialog.showToast(r.message);
    } else {
      _showError(r.message);
    }
  }

  void _showError(String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('连接失败', style: TextStyle(fontSize: 16)),
        content: SelectableText(msg, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _onSave() {
    _controller.save(_collect());
    SmartDialog.showToast('已保存');
    Navigator.pop(context);
  }

  void _onClear() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('清空凭据', style: TextStyle(fontSize: 16)),
        content: const Text('确定要清空 API 基址、API Key 和模型配置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _controller.clear();
              _baseUrlCtrl.text = 'https://api.openai.com/v1';
              _apiKeyCtrl.text = '';
              _modelCtrl.text = 'gpt-4o-mini';
              setState(() => _maxToolCalls = 5);
              SmartDialog.showToast('已清空');
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  Future<void> _onOpenAgent() async {
    // 先保存当前表单，避免用户填了没点保存就跳走
    _controller.save(_collect());

    if (!_controller.isReady) {
      SmartDialog.showToast('请先填写 API 基址和 Key');
      return;
    }

    // 检查 agent 插件是否已安装
    final plugin = InstallManager.instance.findInstalled('agent');
    if (plugin == null || plugin.installPath.isEmpty) {
      SmartDialog.showToast(
        '请先在「插件中心」安装「AI 助手界面」插件',
      );
      return;
    }

    Get.toNamed(AppPages.agentUi);
  }

  Future<void> _onProbeGateway() async {
    SmartDialog.showLoading(msg: '正在探测本地网关…');
    final r = await _controller.probeLocalGateway();
    SmartDialog.dismiss();
    if (!mounted) return;
    if (r == null) {
      SmartDialog.showToast('未发现本地网关（已尝试常见端口）');
      return;
    }
    setState(() {
      _baseUrlCtrl.text = 'http://127.0.0.1:${r.port}/v1';
      if (r.models.isNotEmpty &&
          !r.models.contains(_modelCtrl.text.trim())) {
        _modelCtrl.text = r.models.first;
      }
    });
    SmartDialog.showToast(
      '发现网关 :${r.port}，模型 ${r.models.length} 个',
    );
  }

  Future<void> _onFetchModels() async {
    if (_fetchingModels) return;
    setState(() => _fetchingModels = true);
    final r = await _controller.fetchModels(_collect());
    if (!mounted) return;
    setState(() => _fetchingModels = false);

    if (!r.ok) {
      SmartDialog.showToast(r.message);
      return;
    }

    if (r.models.isEmpty) {
      SmartDialog.showToast(r.message);
      return;
    }

    final picked = await showModelPickerSheet(
      context: context,
      models: r.models,
      current: _modelCtrl.text.trim(),
    );

    if (picked != null && mounted) {
      setState(() => _modelCtrl.text = picked);
      SmartDialog.showToast('已选择：$picked');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'AI 助手',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Style.safeSpace,
          Style.safeSpace,
          Style.safeSpace,
          100,
        ),
        children: [
          // ===== 顶部：打开 AI 助手 =====
          _card(
            colorScheme: colorScheme,
            child: InkWell(
              borderRadius: Style.mdRadius,
              onTap: _onOpenAgent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy_outlined,
                        color: colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '打开 AI 助手',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '对话式遥控：换源、播放、切台等',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colorScheme.outline),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Style.cardSpace),

          // ===== LLM 接入 =====
          _card(
            colorScheme: colorScheme,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LLM 接入（OpenAI 兼容）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // API 基址
                  TextField(
                    controller: _baseUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'API 基址',
                      hintText: 'https://api.openai.com/v1',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: '探测本地网关',
                        icon: const Icon(Icons.radar, size: 20),
                        onPressed: _onProbeGateway,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // API Key
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 模型：手填 + 右侧从 API 拉取
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _modelCtrl,
                          decoration: const InputDecoration(
                            labelText: '模型',
                            hintText: '如 gpt-4o-mini（需支持 Function calling）',
                            border: OutlineInputBorder(),
                            isDense: true,
                            helperText: '需支持 Function calling，否则工具调用不可用',
                            helperMaxLines: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 不再套 SizedBox(height: 48)，用 Padding 让它和输入框顶部视觉对齐
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconButton.outlined(
                          tooltip: '从 API 拉取模型列表',
                          onPressed: _fetchingModels ? null : _onFetchModels,
                          icon: _fetchingModels
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 测试连接
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '测试连接',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '验证基址与 Key 是否可用',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '测试连接',
                        onPressed: _testing ? null : _onTest,
                        icon: _testing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.radar),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 工具使用次数
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '工具使用次数',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '${_maxToolCalls.round()} 次',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '限制单轮对话中模型可调用工具的最大轮数（默认 5）',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                      Slider(
                        value: _maxToolCalls,
                        min: 1,
                        max: 20,
                        divisions: 19,
                        label: '${_maxToolCalls.round()}',
                        onChanged: (v) =>
                            setState(() => _maxToolCalls = v),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 清空凭据
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '清空凭据',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '清除已保存的基址、Key 与模型',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '清空凭据',
                        onPressed: _onClear,
                        icon: Icon(
                          Icons.delete_outline,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (ctx) {
          // 底部安全区：iOS 刘海/手势条、Android 手势条都会计入 viewPadding.bottom
          final bottomInset = MediaQuery.viewPaddingOf(ctx).bottom;
          return Container(
            color: colorScheme.surface,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + bottomInset,
            ),
            child: SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _onSave,
                child: const Text('保存'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card({
    required ColorScheme colorScheme,
    required Widget child,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.mdRadius,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
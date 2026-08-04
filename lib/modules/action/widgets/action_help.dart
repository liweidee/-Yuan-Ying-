// lib/modules/action/widgets/action_help.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../models/button_type.dart';
import '../utils/action_parser.dart';

/// 帮助信息 Action
/// 严格对应 DrPlayer 的 HelpAction.vue
///
/// 功能：
/// - 消息区域
/// - 键值对数据展示
/// - 图片/二维码
/// - 详细信息卡片
/// - 操作步骤
/// - FAQ（展开/折叠）
/// - 链接列表
/// - 联系信息
class HelpAction extends StatefulWidget {
  const HelpAction({
    super.key,
    required this.config,
    required this.visible,
    this.module = '',
    this.extend,
    this.apiUrl,
    this.onSubmit,
    this.onCancel,
    this.onClose,
    this.onAction,
    this.onSpecialAction,
    this.onToast,
    this.onReset,
  });

  final ActionConfig config;
  final bool visible;
  final String module;
  final dynamic extend;
  final String? apiUrl;

  final void Function(dynamic)? onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final void Function(dynamic)? onAction;
  final void Function(String, dynamic)? onSpecialAction;
  final void Function(String, String)? onToast;
  final VoidCallback? onReset;

  @override
  State<HelpAction> createState() => _HelpActionState();
}

class _HelpActionState extends State<HelpAction> {
  Timer? _timeoutTimer;
  int _timeLeft = 0;
  int _expandedFaqIndex = -1;

  bool get _showOkButton => widget.config.button.showOk;
  bool get _showCancelButton => widget.config.button.showCancel;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _startTimeout();
    }
  }

  @override
  void didUpdateWidget(HelpAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _startTimeout();
      } else {
        _stopTimeout();
      }
    }
  }

  @override
  void dispose() {
    _stopTimeout();
    super.dispose();
  }

  void _startTimeout() {
    _stopTimeout();
    if (widget.config.timeout <= 0) return;

    _timeLeft = widget.config.timeout;
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          timer.cancel();
          _handleClose();
        }
      });
    });
  }

  void _stopTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeLeft = 0;
  }

  void _handleClose() {
    widget.onClose?.call();
  }

  void _toggleFaq(int index) {
    setState(() {
      _expandedFaqIndex = _expandedFaqIndex == index ? -1 : index;
    });
  }

  void _copyContent() async {
    // 收集所有文本内容
    final buffer = StringBuffer();
    if (widget.config.msg != null) buffer.writeln(widget.config.msg);
    if (widget.config.detail != null) buffer.writeln(widget.config.detail);
    if (widget.config.list != null) {
      buffer.writeln('\n详细信息:');
      for (final item in widget.config.list!) {
        buffer.writeln('  - $item');
      }
    }
    if (widget.config.faq != null) {
      buffer.writeln('\n常见问题:');
      for (final item in widget.config.faq!) {
        buffer.writeln('Q: ${item.question}');
        buffer.writeln('A: ${item.answer}');
      }
    }

    try {
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      widget.onToast?.call('内容已复制到剪贴板', 'success');
    } catch (_) {
      widget.onToast?.call('复制失败', 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 收集所有内容组件（不包含底部固定的超时和按钮）
    final contentChildren = <Widget>[
      // 消息
      if (widget.config.msg != null && widget.config.msg!.isNotEmpty)
        _buildMessage(context),
      // 数据键值对
      if (widget.config.data != null && widget.config.data!.isNotEmpty)
        _buildData(context),
      // 图片
      if (widget.config.imageUrl != null && widget.config.imageUrl!.isNotEmpty)
        _buildImage(context),
      // 二维码
      if (widget.config.qrcode != null && widget.config.qrcode!.isNotEmpty)
        _buildQrcode(context),
      // 详细信息
      if (widget.config.detail != null && widget.config.detail!.isNotEmpty)
        _buildDetail(context),
      // 步骤
      if (widget.config.steps != null && widget.config.steps!.isNotEmpty)
        _buildSteps(context),
      // FAQ
      if (widget.config.faq != null && widget.config.faq!.isNotEmpty)
        _buildFaq(context),
      // 链接
      if (widget.config.links != null && widget.config.links!.isNotEmpty)
        _buildLinks(context),
      // 联系信息
      if (widget.config.contact != null) _buildContact(context),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 内容区域 - 自适应高度，不会强制拉伸，内容多时可滚动
        Flexible(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            shrinkWrap: true,
            children: contentChildren,
          ),
        ),
        // 超时提示（固定在底部）
        if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),
        // 按钮区（固定在底部）
        _buildButtons(context),
      ],
    );
  }

  Widget _buildMessage(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: SelectableText(
        widget.config.msg!,
        style: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurface,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildData(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.config.data!.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    entry.value?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          widget.config.imageUrl!,
          height: widget.config.imageHeight ?? 200,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              height: widget.config.imageHeight ?? 200,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: widget.config.imageHeight ?? 200,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 48, color: colorScheme.outline),
                  const SizedBox(height: 8),
                  Text('图片加载失败',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQrcode(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final qrcodeUrl = ActionParser.generateQRCodeUrl(
      widget.config.qrcode!,
      widget.config.qrcodeSize ?? '200x200',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network(
            qrcodeUrl,
            width: 150,
            height: 150,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 48, color: colorScheme.outline),
                    const SizedBox(height: 8),
                    Text('二维码加载失败',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            widget.config.qrcode!,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description, size: 16, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                '详细信息',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            widget.config.detail!,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSteps(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final steps = widget.config.steps!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_list_numbered, size: 16, color: colorScheme.tertiary),
              const SizedBox(width: 8),
              Text(
                '操作步骤',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final title = step['title']?.toString();
            final content = step['content']?.toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2, right: 8),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        if (content != null)
                          Text(
                            content,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFaq(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final faq = widget.config.faq!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help, size: 16, color: colorScheme.tertiary),
              const SizedBox(width: 8),
              Text(
                '常见问题',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...faq.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isExpanded = _expandedFaqIndex == index;

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isExpanded
                    ? colorScheme.primaryContainer.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => _toggleFaq(index),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.question,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isExpanded ? FontWeight.w600 : FontWeight.normal,
                                color: isExpanded ? colorScheme.primary : colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: SelectableText(
                        item.answer,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLinks(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '相关链接',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...widget.config.links!.map((link) {
            return InkWell(
              onTap: () {
                // 打开链接，可以使用 url_launcher
                widget.onToast?.call('打开链接: ${link.title}', 'info');
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        link.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: colorScheme.outline),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildContact(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final contact = widget.config.contact!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.contact_mail, size: 16, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                '联系我们',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (contact.email != null)
            _buildContactItem(Icons.email, '邮箱', contact.email!),
          if (contact.phone != null)
            _buildContactItem(Icons.phone, '电话', contact.phone!),
          if (contact.website != null)
            _buildContactItem(Icons.language, '网站', contact.website!),
          if (contact.address != null)
            _buildContactItem(Icons.location_on, '地址', contact.address!),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: colorScheme.outline),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            '$_timeLeft秒后自动关闭',
            style: TextStyle(fontSize: 11, color: colorScheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final children = <Widget>[];

    // 复制按钮
    children.add(
      TextButton.icon(
        onPressed: _copyContent,
        icon: const Icon(Icons.copy, size: 18),
        label: const Text('复制内容'),
      ),
    );

    if (_showCancelButton) {
      children.add(
        TextButton(
          onPressed: _handleClose,
          child: const Text('取消'),
        ),
      );
    }

    if (_showOkButton) {
      children.add(
        ElevatedButton(
          onPressed: _handleClose,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: const Text('确定'),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: children,
      ),
    );
  }
}
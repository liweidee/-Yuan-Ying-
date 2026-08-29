// lib/modules/novel/widgets/purify_sheet.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 净化规则管理弹窗
Future<List<Map<String, dynamic>>?> showPurifySheet(
  BuildContext context, {
  required List<Map<String, dynamic>> rules,
  required Future<void> Function(List<Map<String, dynamic>>) onSave,
}) {
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return _PurifySheetContent(
        initialRules: rules,
        onSave: onSave,
      );
    },
  );
}

class _PurifySheetContent extends StatefulWidget {
  final List<Map<String, dynamic>> initialRules;
  final Future<void> Function(List<Map<String, dynamic>>) onSave;

  const _PurifySheetContent({
    required this.initialRules,
    required this.onSave,
  });

  @override
  State<_PurifySheetContent> createState() => _PurifySheetContentState();
}

class _PurifySheetContentState extends State<_PurifySheetContent> {
  late List<Map<String, dynamic>> _rules;
  final TextEditingController _patternCtrl = TextEditingController();
  final TextEditingController _replaceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rules = widget.initialRules.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  void _addRule() {
    final pattern = _patternCtrl.text.trim();
    if (pattern.isEmpty) {
      SmartDialog.showToast('请输入正则表达式');
      return;
    }
    try {
      RegExp(pattern); // 验证合法性
    } catch (_) {
      SmartDialog.showToast('正则表达式无效');
      return;
    }
    setState(() {
      _rules.add({
        'pattern': pattern,
        'replace': _replaceCtrl.text,
        'enabled': true,
      });
      _patternCtrl.clear();
      _replaceCtrl.clear();
    });
    _save();
  }

  void _toggleEnabled(int index, bool value) {
    setState(() {
      _rules[index]['enabled'] = value;
    });
    _save();
  }

  void _deleteRule(int index) {
    setState(() {
      _rules.removeAt(index);
    });
    _save();
  }

  Future<void> _save() async {
    await widget.onSave(_rules);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Text(
                  '净化规则',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '共 ${_rules.length} 条',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _patternCtrl,
                    decoration: const InputDecoration(
                      hintText: '正则，如 请记住本书首发.*',
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _replaceCtrl,
                    decoration: const InputDecoration(
                      hintText: '替换为（可空）',
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addRule,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    minimumSize: const Size(48, 40),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _rules.isEmpty
                ? Center(
                    child: Text(
                      '还没有规则',
                      style: TextStyle(color: colorScheme.outline, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: _rules.length,
                    itemBuilder: (context, i) {
                      final r = _rules[i];
                      final enabled = r['enabled'] != false;
                      return ListTile(
                        dense: true,
                        title: Text(
                          r['pattern']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: enabled ? colorScheme.onSurface : colorScheme.outline,
                          ),
                        ),
                        subtitle: Text(
                          '→ ${r['replace'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                        ),
                        leading: Switch(
                          value: enabled,
                          onChanged: (v) => _toggleEnabled(i, v),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteRule(i),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
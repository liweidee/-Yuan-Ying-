// lib/modules/web_tab/widgets/web_source_switch_dialog.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/manual_source/models/manual_source_item.dart';

class WebSourceSwitchDialog extends StatefulWidget {
  final String currentId;
  final List<ManualSourceItem> items;
  final void Function(ManualSourceItem) onSelect;

  const WebSourceSwitchDialog({
    super.key,
    required this.currentId,
    required this.items,
    required this.onSelect,
  });

  @override
  State<WebSourceSwitchDialog> createState() => _WebSourceSwitchDialogState();
}

class _WebSourceSwitchDialogState extends State<WebSourceSwitchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = widget.items
        .where((e) => _query.isEmpty || e.name.contains(_query))
        .toList();

    // 与首页 _showSourceSwitchDialog 保持一致的宽度策略
    final double screenWidth = MediaQuery.of(context).size.width;
    final double dialogWidth =
        screenWidth > 600 ? 400.0 : screenWidth * 0.85;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 60),
      child: SizedBox(
        width: dialogWidth,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.language, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      '切换 Web 源',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    // 唯一入口：去手动源管理
                    IconButton(
                      tooltip: '管理',
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      onPressed: () {
                        Navigator.pop(context);
                        Get.toNamed(AppPages.manualSource);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: '搜索源...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open,
                                size: 40, color: cs.outline),
                            const SizedBox(height: 8),
                            Text('无匹配源',
                                style: TextStyle(color: cs.outline)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final src = list[i];
                          final isCur = src.id == widget.currentId;
                          return ListTile(
                            leading: Icon(Icons.web,
                                color: isCur ? cs.primary : cs.outline),
                            title: Text(
                              src.name,
                              style: TextStyle(
                                fontWeight: isCur
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              src.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: isCur
                                ? Icon(Icons.check_circle,
                                    color: cs.primary, size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(context);
                              widget.onSelect(src);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
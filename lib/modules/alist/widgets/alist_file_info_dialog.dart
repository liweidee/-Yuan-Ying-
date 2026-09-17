import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import '../services/alist_file_utils.dart';

/// 通用文件信息弹窗，替代 PDF/Office/Markdown/TXT 等阅读器
class AlistFileInfoDialog {
  static Future<void> show(
    BuildContext context, {
    required String name,
    required String path,
    String? size,
    String? modified,
    String? provider,
    String? sign,
    bool isDir = false,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: Theme.of(ctx).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(height: 24),
              _row(ctx, '路径', path),
              if (size != null) _row(ctx, '大小', size),
              if (modified != null) _row(ctx, '修改时间', modified),
              if (provider != null && provider.isNotEmpty)
                _row(ctx, '挂载类型', provider),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (!isDir)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('复制链接'),
                        onPressed: () {
                          AlistFileUtils.copyFileLink(path, sign);
                        },
                      ),
                    ),
                  if (!isDir) const SizedBox(width: 12),
                  if (!isDir)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('下载'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          SmartDialog.showToast('请通过文件菜单下载');
                        },
                      ),
                    ),
                  if (isDir)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('打开'),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
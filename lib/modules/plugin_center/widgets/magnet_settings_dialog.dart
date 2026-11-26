import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/services/magnet/magnet_cache_manager.dart';
import 'package:yuanying/services/magnet/magnet_models.dart';
import 'package:yuanying/services/magnet/magnet_plugin_service.dart';

Future<void> showMagnetSettingsDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _MagnetSettingsDialog(plugin: plugin),
  );
}

class _MagnetSettingsDialog extends StatefulWidget {
  final InstalledPlugin plugin;

  const _MagnetSettingsDialog({required this.plugin});

  @override
  State<_MagnetSettingsDialog> createState() => _MagnetSettingsDialogState();
}

class _MagnetSettingsDialogState extends State<_MagnetSettingsDialog> {
  static const _limits = [1, 2, 4, 8, 16];

  late int _cacheGb;
  late bool _deleteOnStop;
  bool _saving = false;

  MagnetCacheManager get _cache => MagnetCacheManager.instance;

  @override
  void initState() {
    super.initState();
    final value = widget.plugin.extras['magnetCacheGb'];
    _cacheGb = value is num ? value.toInt().clamp(1, 16) : 4;
    if (!_limits.contains(_cacheGb)) _cacheGb = 4;
    final deleteValue = widget.plugin.extras['magnetDeleteOnStop'];
    _deleteOnStop = deleteValue is bool ? deleteValue : true;
    unawaited(_cache.init());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('磁力播放设置'),
      content: SizedBox(
        width: 420,
        child: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '磁力缓存与普通下载共用同一个下载根目录，但存放在独立的 magnet 子目录。',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                initialValue: _cacheGb,
                decoration: const InputDecoration(
                  labelText: '磁力缓存上限',
                  border: OutlineInputBorder(),
                ),
                items: _limits
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value GB'),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _cacheGb = value);
                        }
                      },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('停止播放时删除媒体'),
                subtitle: const Text('关闭后会保留已下载媒体并计入缓存配额'),
                value: _deleteOnStop,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _deleteOnStop = value),
              ),
              const Divider(),
              Text(
                '当前磁力缓存：${formatMagnetBytes(_cache.totalBytes)}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                '清理时保留 .torrent 元数据，不删除普通下载。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : _clearCache,
                child: const Text('清理'),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final extras = Map<String, dynamic>.from(widget.plugin.extras)
        ..['magnetCacheGb'] = _cacheGb
        ..['magnetDeleteOnStop'] = _deleteOnStop;
      await InstallManager.instance.updateExtras(widget.plugin.id, extras);
      await _cache.reloadSettings();
      if (mounted) Navigator.of(context).pop();
      SmartDialog.showToast('磁力播放设置已保存');
    } catch (e) {
      SmartDialog.showToast('保存失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除磁力缓存'),
        content: const Text('将停止当前磁力播放，并删除磁力媒体文件。普通下载不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await MagnetPluginService.instance.disposeAll(deleteMedia: true);
      await _cache.clearAllMedia();
      SmartDialog.showToast('磁力缓存已清除');
    } catch (e) {
      SmartDialog.showToast('清除失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

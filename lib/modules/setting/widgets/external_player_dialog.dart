import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:yuanying/plugin/pl_player/models/external_player_type.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

/// 第三方播放器配置弹窗
///
/// 用户交互：
///   1. 选择播放器类型（MPV / VLC / PotPlayer）
///   2. 通过文件选择器选择对应的可执行文件
///   3. 保存后写入 PlayerPref
class ExternalPlayerDialog extends StatefulWidget {
  const ExternalPlayerDialog({super.key});

  /// 打开弹窗
  ///
  /// 返回 true 表示用户保存了配置，返回 false / null 表示取消。
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const ExternalPlayerDialog(),
    );
  }

  @override
  State<ExternalPlayerDialog> createState() => _ExternalPlayerDialogState();
}

class _ExternalPlayerDialogState extends State<ExternalPlayerDialog> {
  late ExternalPlayerType _type;
  late String _path;

  @override
  void initState() {
    super.initState();
    _type = PlayerPref.externalPlayerType;
    _path = PlayerPref.getPathForType(_type);
  }

  /// 切换播放器类型：保留已配置的路径
  void _onTypeChanged(ExternalPlayerType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _path = PlayerPref.getPathForType(type);
    });
  }

  /// 通过文件选择器选择可执行文件
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
        dialogTitle: '选择 ${_type.label} 可执行文件',
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first.path;
        if (picked != null && picked.isNotEmpty) {
          setState(() => _path = picked);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e')),
      );
    }
  }

  /// 清空当前路径输入（仅修改 UI 状态，需点击"保存"才真正生效）
  void _clearPath() {
    setState(() => _path = '');
  }

  /// 保存配置
  void _save() {
    PlayerPref.externalPlayerType = _type;
    PlayerPref.setPathForType(_type, _path);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 固定宽度：避免切换选项时弹窗宽度变化
    const double dialogWidth = 380.0;

    return AlertDialog(
      title: const Text('第三方播放器'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- 播放器类型选择 ----
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '播放器类型',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<ExternalPlayerType>(
                segments: ExternalPlayerType.values.map((type) {
                  return ButtonSegment<ExternalPlayerType>(
                    value: type,
                    label: Text(type.label),
                  );
                }).toList(),
                selected: {_type},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    _onTypeChanged(selection.first);
                  }
                },
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ---- 播放器路径选择 ----
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '播放器路径',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickFile,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _path.isEmpty ? '点击选择可执行文件…' : _path,
                          style: TextStyle(
                            fontSize: 12,
                            color: _path.isEmpty
                                ? colorScheme.outline
                                : colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.folder_open,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ---- 类型提示 ----
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _hintForType(_type),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                    height: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ---- 底部操作栏：清除（左） | 取消 + 保存（右） ----
              Row(
                children: [
                  // 左侧：清除当前播放器
                  TextButton.icon(
                    onPressed: _path.isEmpty ? null : _clearPath,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清除'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    // 即使 _path 为空也允许保存（= 清除该类型配置）
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hintForType(ExternalPlayerType type) {
    switch (type) {
      case ExternalPlayerType.mpv:
        return '提示：MPV 支持完整的请求头传递与进度续传，兼容性最佳。';
      case ExternalPlayerType.vlc:
        return '提示：VLC 支持 Referer / User-Agent 请求头与进度续传。';
      case ExternalPlayerType.potPlayer:
        return '提示：PotPlayer 支持进度续传，但不支持从命令行传递请求头，'
            '需要校验 Referer/UA 的源可能播放失败。';
    }
  }
}
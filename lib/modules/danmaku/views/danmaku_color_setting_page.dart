import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/danmaku/models/danmaku_color_palette.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/utils/storage_utils.dart';

class DanmakuColorSettingPage extends StatefulWidget {
  const DanmakuColorSettingPage({super.key});

  @override
  State<DanmakuColorSettingPage> createState() =>
      _DanmakuColorSettingPageState();
}

class _DanmakuColorSettingPageState extends State<DanmakuColorSettingPage> {
  late final RxList<String> _randomColors;
  late final RxList<String> _gradientColors;
  int _tabIndex = 0;

  RxList<String> get _current =>
      _tabIndex == 0 ? _randomColors : _gradientColors;

  bool get _isRandomTab => _tabIndex == 0;
  String get _paletteLabel => _isRandomTab ? '随机彩色' : '渐变基色';
  String get _preferKey => _isRandomTab ? 'random' : 'gradient';

  @override
  void initState() {
    super.initState();
    _randomColors = PlayerPref.danmakuRandomColors.obs;
    _gradientColors = PlayerPref.danmakuGradientColors.obs;
  }

  void _persist() {
    if (_tabIndex == 0) {
      PlayerPref.danmakuRandomColors = _randomColors.toList();
    } else {
      PlayerPref.danmakuGradientColors = _gradientColors.toList();
    }
  }

  // ===== 新增 / 编辑 / 删除 =====
  Future<void> _addColor() async {
    final result = _isRandomTab
        ? await _showSingleColorEditor()
        : await _showPairColorEditor();
    if (result == null || !mounted) return;
    if (_current.contains(result)) {
      SmartDialog.showToast('该颜色已在色盘中');
      return;
    }
    _current.add(result);
    _persist();
  }

  Future<void> _editColor(int index) async {
    final initial = _current[index];
    final result = _isRandomTab
        ? await _showSingleColorEditor(initialHex: initial)
        : await _showPairColorEditor(initialEntry: initial);
    if (result == null || !mounted) return;
    if (result == initial) return;
    if (_current.contains(result)) {
      SmartDialog.showToast('该颜色已在色盘中');
      return;
    }
    _current[index] = result;
    _persist();
  }

  Future<void> _deleteColor(int index) async {
    if (_current.length == 1) {
      final ok = await _confirmClear();
      if (ok != true || !mounted) return;
    }
    _current.removeAt(index);
    _persist();
  }

  Future<void> _clearAll() async {
    if (_current.isEmpty) return;
    final ok = await _confirmClear();
    if (ok != true || !mounted) return;
    _current.clear();
    _persist();
  }

  Future<bool?> _confirmClear() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空「$_paletteLabel」'),
        content: Text(
          _isRandomTab
              ? '清空后，随机彩色模式将按全色相完全随机取色，不再受色盘限制。确定清空吗？'
              : '清空后，渐变模式将回退为按时间旋转色相。确定清空吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定清空'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreDefault() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认'),
        content: Text(
          '将「$_paletteLabel」恢复为内置预设'
          '（${_isRandomTab ? 49 : 24} 组），当前修改会丢失。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _current.assignAll(_isRandomTab
        ? DanmakuColorPalette.defaultRandomColors
        : DanmakuColorPalette.defaultGradientColors);
    _persist();
  }

  // ===== 导入 / 导出 =====
  Future<void> _importColors() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (picked == null || !mounted) return;
      final content = await picked.xFile.readAsString();
      final colors = DanmakuColorPalette.parseInput(
        content,
        preferKey: _preferKey,
      );
      if (colors.isEmpty) {
        SmartDialog.showToast('未识别到有效颜色');
        return;
      }
      if (!mounted) return;
      final mode = await _askImportMode(colors.length);
      if (mode == null || !mounted) return;
      if (mode == 'append') {
        final set = _current.toSet();
        final added = <String>[];
        for (final c in colors) {
          if (set.add(c)) added.add(c);
        }
        _current.addAll(added);
        SmartDialog.showToast('导入成功，新增 ${added.length} 组');
      } else {
        _current.assignAll(colors);
        SmartDialog.showToast('导入成功，共 ${colors.length} 组');
      }
      _persist();
    } catch (e) {
      SmartDialog.showToast('导入失败：$e');
    }
  }

  Future<String?> _askImportMode(int count) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入颜色'),
        content: Text('识别到 $count 组颜色，是否覆盖当前「$_paletteLabel」色盘？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'append'),
            child: const Text('追加'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'overwrite'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportColors() async {
    if (_current.isEmpty) {
      SmartDialog.showToast('当前色盘为空，无可导出内容');
      return;
    }
    final data = <String, dynamic>{
      'app': 'danmaku-color-config',
      'version': 1,
      _preferKey: _current.toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final name =
        'danmaku_${_preferKey}_${DateTime.now().millisecondsSinceEpoch}.json';
    try {
      await StorageUtils.saveBytes2File(
        name: name,
        bytes: Uint8List.fromList(utf8.encode(jsonStr)),
      );
      SmartDialog.showToast('已导出：$name');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: jsonStr));
      SmartDialog.showToast('保存失败，已复制到剪贴板');
    }
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('弹幕颜色设置'),
        actions: [
          IconButton(
            tooltip: '导入',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _importColors,
          ),
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _exportColors,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildTabSwitcher(),
          _buildPreview(),
          _buildActionRow(),
          Expanded(
            child: Obx(() {
              if (_current.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      '当前色盘为空\n运行时将回退为完全随机取色',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.outline, height: 1.6),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: _current.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) =>
                    _buildColorTile(_current[index], index, cs),
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addColor,
        tooltip: '新增颜色',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Obx(() {
        return SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              label: Text('随机彩色（${_randomColors.length}）'),
              icon: const Icon(Icons.color_lens_outlined, size: 18),
            ),
            ButtonSegment(
              value: 1,
              label: Text('渐变基色（${_gradientColors.length}）'),
              icon: const Icon(Icons.gradient, size: 18),
            ),
          ],
          selected: {_tabIndex},
          onSelectionChanged: (s) {
            setState(() => _tabIndex = s.first);
          },
        );
      }),
    );
  }

  Widget _buildPreview() {
    return Obx(() {
      final colors = _current.toList();
      final isEmpty = colors.isEmpty;

      final samples = <(String, String)>[];
      if (!isEmpty) {
        for (var i = 0; i < 3; i++) {
          final entry = colors[i % colors.length];
          if (_isRandomTab) {
            samples.add((entry, entry));
          } else {
            final pair = DanmakuColorPalette.parsePair(entry);
            samples.add((
              DanmakuColorPalette.colorToHex(pair.$1),
              DanmakuColorPalette.colorToHex(pair.$2),
            ));
          }
        }
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF14151F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _isRandomTab ? '随机彩色预览' : '渐变基色预览',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    isEmpty ? '色盘为空' : '作用于「$_paletteLabel」',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '暂无颜色',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
              )
            else
              ...samples.map((pair) {
                final startColor =
                    DanmakuColorPalette.parseHex(pair.$1) ?? Colors.white;
                final endColor =
                    DanmakuColorPalette.parseHex(pair.$2) ?? Colors.white;
                final textStyle = TextStyle(
                  fontSize: 14,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 2),
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient:
                              LinearGradient(colors: [startColor, endColor]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isRandomTab
                          ? Text(
                              '这条弹幕会从色盘中取色',
                              style: textStyle.copyWith(color: startColor),
                            )
                          : ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [startColor, endColor],
                              ).createShader(bounds),
                              child: Text(
                                '这条弹幕会按基色渐变',
                                style: textStyle.copyWith(color: Colors.white),
                              ),
                            ),
                    ],
                  ),
                );
              }),
          ],
        ),
      );
    });
  }

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _addColor,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增'),
          ),
          Obx(() => OutlinedButton.icon(
                onPressed: _current.isEmpty ? null : _clearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('清空'),
              )),
          OutlinedButton.icon(
            onPressed: _restoreDefault,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('恢复默认'),
          ),
        ],
      ),
    );
  }

  Widget _buildColorTile(String entry, int index, ColorScheme cs) {
    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: () => _editColor(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _buildColorIndicator(entry, cs),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isRandomTab ? entry : entry.replaceAll('|', '  →  '),
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: entry));
                  SmartDialog.showToast('已复制');
                },
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _deleteColor(index),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorIndicator(String entry, ColorScheme cs) {
    if (_isRandomTab) {
      final c = DanmakuColorPalette.parseHex(entry) ?? Colors.white;
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    final pair = DanmakuColorPalette.parsePair(entry);
    return Container(
      width: 56,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(colors: [pair.$1, pair.$2]),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  // ===== 编辑器入口 =====
  Future<String?> _showSingleColorEditor({String? initialHex}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SingleColorEditorSheet(initialHex: initialHex),
    );
  }

  Future<String?> _showPairColorEditor({String? initialEntry}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PairColorEditorSheet(initialEntry: initialEntry),
    );
  }
}

// ============================================================================
// 单色编辑器（随机彩色）
// ============================================================================
class _SingleColorEditorSheet extends StatefulWidget {
  final String? initialHex;
  const _SingleColorEditorSheet({this.initialHex});

  @override
  State<_SingleColorEditorSheet> createState() =>
      _SingleColorEditorSheetState();
}

class _SingleColorEditorSheetState extends State<_SingleColorEditorSheet> {
  late final TextEditingController _hexController;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = widget.initialHex != null
        ? (DanmakuColorPalette.parseHex(widget.initialHex!) ?? Colors.white)
        : Colors.white;
    _hexController =
        TextEditingController(text: DanmakuColorPalette.colorToHex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyColor(Color c) {
    setState(() {
      _color = c;
      _hexController.text = DanmakuColorPalette.colorToHex(c);
    });
  }

  void _tryParseHex(String text) {
    final c = DanmakuColorPalette.parseHex(text);
    if (c != null) setState(() => _color = c);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = (_color.r * 255).round();
    final g = (_color.g * 255).round();
    final b = (_color.b * 255).round();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.initialHex == null ? '新增颜色' : '编辑颜色',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF14151F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '这条弹幕会使用该颜色',
                        style: TextStyle(
                          color: _color,
                          fontSize: 14,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.tag, size: 18),
                        hintText: '#RRGGBB',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: _tryParseHex,
                      onChanged: _tryParseHex,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text;
                      if (text != null && text.isNotEmpty) {
                        _tryParseHex(text);
                        _hexController.text = text;
                      }
                    },
                    child: const Text('粘贴'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 110,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 16),
              _rgbRow('R', r, Colors.red,
                  (v) => _applyColor(Color.fromARGB(255, v, g, b))),
              _rgbRow('G', g, Colors.green,
                  (v) => _applyColor(Color.fromARGB(255, r, v, b))),
              _rgbRow('B', b, Colors.blue,
                  (v) => _applyColor(Color.fromARGB(255, r, g, v))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        DanmakuColorPalette.colorToHex(_color),
                      ),
                      child: const Text('应用'),
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

  Widget _rgbRow(
    String label,
    int value,
    Color color,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              min: 0,
              max: 255,
              value: value.toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 成对颜色编辑器（渐变基色）
// ============================================================================
class _PairColorEditorSheet extends StatefulWidget {
  final String? initialEntry;
  const _PairColorEditorSheet({this.initialEntry});

  @override
  State<_PairColorEditorSheet> createState() => _PairColorEditorSheetState();
}

class _PairColorEditorSheetState extends State<_PairColorEditorSheet> {
  late Color _start;
  late Color _end;
  int _editTarget = 0; // 0=起始色, 1=结束色
  late final TextEditingController _hexController;

  Color get _current => _editTarget == 0 ? _start : _end;

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      final pair = DanmakuColorPalette.parsePair(widget.initialEntry!);
      _start = pair.$1;
      _end = pair.$2;
    } else {
      _start = Colors.red;
      _end = Colors.blue;
    }
    _hexController = TextEditingController(
      text: DanmakuColorPalette.colorToHex(_start),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _switchTarget(int target) {
    if (target == _editTarget) return;
    setState(() {
      _editTarget = target;
      _hexController.text = DanmakuColorPalette.colorToHex(_current);
    });
  }

  void _applyColor(Color c) {
    setState(() {
      if (_editTarget == 0) {
        _start = c;
      } else {
        _end = c;
      }
      _hexController.text = DanmakuColorPalette.colorToHex(c);
    });
  }

  void _tryParseHex(String text) {
    final c = DanmakuColorPalette.parseHex(text);
    if (c != null) {
      setState(() {
        if (_editTarget == 0) {
          _start = c;
        } else {
          _end = c;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = (_current.r * 255).round();
    final g = (_current.g * 255).round();
    final b = (_current.b * 255).round();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.initialEntry == null ? '新增渐变基色' : '编辑渐变基色',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),

              // 预览条
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF14151F),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '渐变预览',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${DanmakuColorPalette.colorToHex(_start)}  →  '
                          '${DanmakuColorPalette.colorToHex(_end)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          LinearGradient(colors: [_start, _end])
                              .createShader(bounds),
                      child: const Text(
                        '这条弹幕会按基色渐变',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 起止色块并排
              Row(
                children: [
                  Expanded(
                    child: _buildColorPicker(
                      label: '起始色',
                      color: _start,
                      selected: _editTarget == 0,
                      onTap: () => _switchTarget(0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildColorPicker(
                      label: '结束色',
                      color: _end,
                      selected: _editTarget == 1,
                      onTap: () => _switchTarget(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // HEX 输入 + 粘贴
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        hintText: '#RRGGBB',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: _editTarget == 0 ? '编辑起始色' : '编辑结束色',
                      ),
                      onSubmitted: _tryParseHex,
                      onChanged: _tryParseHex,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text;
                      if (text != null && text.isNotEmpty) {
                        _tryParseHex(text);
                        _hexController.text = text;
                      }
                    },
                    child: const Text('粘贴'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 大色块（当前编辑目标）
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: _current,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 12),

              _rgbRow('R', r, Colors.red,
                  (v) => _applyColor(Color.fromARGB(255, v, g, b))),
              _rgbRow('G', g, Colors.green,
                  (v) => _applyColor(Color.fromARGB(255, r, v, b))),
              _rgbRow('B', b, Colors.blue,
                  (v) => _applyColor(Color.fromARGB(255, r, g, v))),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        DanmakuColorPalette.serializePair(_start, _end),
                      ),
                      child: const Text('应用'),
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

  Widget _buildColorPicker({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: cs.primary),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DanmakuColorPalette.colorToHex(color),
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rgbRow(
    String label,
    int value,
    Color color,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              min: 0,
              max: 255,
              value: value.toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
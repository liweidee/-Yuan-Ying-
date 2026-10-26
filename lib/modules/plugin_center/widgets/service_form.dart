// lib/modules/plugin_center/widgets/service_form.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/plugin_paths.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';

Future<void> showServiceForm(
  BuildContext context, {
  ServiceConfig? existing,
  ServiceConfig? copyFrom,
}) async {
  assert(existing == null || copyFrom == null);
  await showDialog<void>(
    context: context,
    builder: (_) => _ServiceFormDialog(
      existing: existing,
      copyFrom: copyFrom,
    ),
  );
}

/// 内置运行时 id 白名单（含 -win 与 Android 无后缀版本 + mediaProxy 系列）
const _knownRuntimes = <String>[
  'nodejs',
  'nodejs-win',
  'php',
  'php-win',
  'python',
  'python-win',
  'mediaProxy',
  'mediaProxy-win',
  'qjs',
  'qjs-win',
];

const _customRuntimeKey = 'custom';

const _runtimeArgTemplates = <String, String>{
  'nodejs': 'index.js',
  'nodejs-win': 'index.js',
  'php': '-S 0.0.0.0:{port} -t {cwd}',
  'php-win': '-S 0.0.0.0:{port} -t {cwd}',
  'python': 'app.py',
  'python-win': 'app.py',
  'mediaProxy': '-port {port}',
  'mediaProxy-win': '-port {port}',
};

const _runtimeHints = <String, String>{
  'nodejs': 'Node.js 模板：index.js，或 --port <端口> index.js',
  'nodejs-win': 'Node.js 模板：index.js，或 --port <端口> index.js',
  'php': 'PHP 模板：-S 0.0.0.0:<端口> -t <工作目录>',
  'php-win': 'PHP 模板：-S 0.0.0.0:<端口> -t <工作目录>',
  'python': 'Python 模板：app.py，或 -m flask run --port <端口>',
  'python-win': 'Python 模板：app.py，或 -m flask run --port <端口>',
  'mediaProxy': 'mediaProxy 模板：-port <端口>',
  'mediaProxy-win': 'mediaProxy 模板：-port <端口>',
  'custom': '自定义：请填写完整启动参数',
};

String _runtimeLabel(String id) {
  switch (id) {
    case 'nodejs':
      return 'Node.js 运行时';
    case 'nodejs-win':
      return 'Node.js 运行时（Windows）';
    case 'php':
      return 'PHP 运行时';
    case 'php-win':
      return 'PHP 运行时（Windows）';
    case 'python':
      return 'Python 运行时';
    case 'python-win':
      return 'Python 运行时（Windows）';
    case 'mediaProxy':
      return '媒体代理服务';
    case 'mediaProxy-win':
      return '媒体代理服务（Windows）';
    case 'qjs':
      return 'QJS 爬虫引擎';
    case 'qjs-win':
      return 'QJS 爬虫引擎（Windows）';
    case _customRuntimeKey:
      return '自定义（手动指定可执行文件）';
    default:
      return id;
  }
}

String? _exeNameFor(String runtime) {
  if (runtime.startsWith('nodejs')) return Platform.isWindows ? 'node.exe' : 'node';
  if (runtime.startsWith('php')) return Platform.isWindows ? 'php.exe' : 'php';
  if (runtime.startsWith('python')) {
    return Platform.isWindows ? 'python.exe' : 'python3.12';
  }
  if (runtime.startsWith('mediaProxy')) {
    return Platform.isWindows ? 'mediaProxy-win.exe' : 'mediaProxy';
  }
  return null;
}

class _EnvEntry {
  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;
  final FocusNode keyFocus;
  final FocusNode valueFocus;

  _EnvEntry({String key = '', String value = ''})
      : keyCtrl = TextEditingController(text: key),
        valueCtrl = TextEditingController(text: value),
        keyFocus = FocusNode(),
        valueFocus = FocusNode();

  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
    keyFocus.dispose();
    valueFocus.dispose();
  }
}

class _ServiceFormDialog extends StatefulWidget {
  final ServiceConfig? existing;
  final ServiceConfig? copyFrom;

  const _ServiceFormDialog({this.existing, this.copyFrom});

  @override
  State<_ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<_ServiceFormDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _argsCtrl;
  late TextEditingController _cwdCtrl;
  late TextEditingController _exeCtrl;
  late TextEditingController _healthPathCtrl;
  late TextEditingController _pidFileCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _portFocus = FocusNode();
  final FocusNode _argsFocus = FocusNode();
  final FocusNode _cwdFocus = FocusNode();
  final FocusNode _exeFocus = FocusNode();
  final FocusNode _healthPathFocus = FocusNode();
  final FocusNode _pidFileFocus = FocusNode();

  String? _selectedRuntime;
  bool _autostart = false;
  bool _keepForeground = false;
  String _healthType = 'process';
  String _lastRenderedArgs = '';
  List<_EnvEntry> _envEntries = [];
  TextEditingController? _lastFocusedController;
  FocusNode? _lastFocusedNode;
  List<InstalledPlugin> _availableRuntimes = [];

  /// 只有「新建」才启用自动模板替换（编辑/复制时用户值优先）
  bool _autoTemplateEnabled = false;

  late String _serviceId;

  bool get _isCustomRuntime => _selectedRuntime == _customRuntimeKey;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;
    final copyFrom = widget.copyFrom;

    _serviceId = existing?.id ?? 'svc-${DateTime.now().millisecondsSinceEpoch}';

    if (existing != null) {
      _nameCtrl = TextEditingController(text: existing.name);
      _portCtrl = TextEditingController(
          text: existing.port != null ? '${existing.port}' : '');
      _argsCtrl = TextEditingController(text: existing.args.join(' '));
      _cwdCtrl = TextEditingController(text: existing.cwd);
      _exeCtrl = TextEditingController(text: existing.executable ?? '');
      _healthPathCtrl = TextEditingController(text: existing.healthPath);
      _pidFileCtrl = TextEditingController(text: existing.pidFile ?? '');
      _selectedRuntime = existing.runtime;
      _autostart = existing.autostart;
      _keepForeground = existing.keepForeground;
      _healthType = existing.healthType;
      for (final e in existing.env.entries) {
        _envEntries.add(_EnvEntry(key: e.key, value: e.value));
      }
    } else if (copyFrom != null) {
      _nameCtrl = TextEditingController(text: '${copyFrom.name} - 副本');
      _portCtrl = TextEditingController(
          text: copyFrom.port != null ? '${copyFrom.port! + 1}' : '');
      _argsCtrl = TextEditingController(text: copyFrom.args.join(' '));
      _cwdCtrl = TextEditingController(text: '');
      _exeCtrl = TextEditingController(text: copyFrom.executable ?? '');
      _healthPathCtrl = TextEditingController(text: copyFrom.healthPath);
      _pidFileCtrl = TextEditingController(text: '');
      _selectedRuntime = copyFrom.runtime;
      _autostart = false;
      _keepForeground = false;
      _healthType = copyFrom.healthType;
      for (final e in copyFrom.env.entries) {
        _envEntries.add(_EnvEntry(key: e.key, value: e.value));
      }
    } else {
      _nameCtrl = TextEditingController();
      _portCtrl = TextEditingController();
      _argsCtrl = TextEditingController();
      _cwdCtrl = TextEditingController();
      _exeCtrl = TextEditingController();
      _healthPathCtrl = TextEditingController(text: '/');
      _pidFileCtrl = TextEditingController();
      _healthType = 'process';
    }

    _lastRenderedArgs = _argsCtrl.text;
    _autoTemplateEnabled = widget.existing == null && widget.copyFrom == null;

    _loadRuntimes();

    _portCtrl.addListener(_onPortOrCwdChanged);
    _cwdCtrl.addListener(_onPortOrCwdChanged);

    for (final entry in [
      (ctrl: _nameCtrl, focus: _nameFocus),
      (ctrl: _portCtrl, focus: _portFocus),
      (ctrl: _argsCtrl, focus: _argsFocus),
      (ctrl: _cwdCtrl, focus: _cwdFocus),
      (ctrl: _exeCtrl, focus: _exeFocus),
      (ctrl: _healthPathCtrl, focus: _healthPathFocus),
      (ctrl: _pidFileCtrl, focus: _pidFileFocus),
    ]) {
      entry.focus.addListener(() {
        if (entry.focus.hasFocus) {
          _lastFocusedController = entry.ctrl;
          _lastFocusedNode = entry.focus;
        }
      });
    }
    for (final e in _envEntries) {
      _bindEnvFocus(e);
    }

    if (existing == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _ensureDefaultCwd();
        if (copyFrom == null && _selectedRuntime != null) {
          _applyRuntimeDefaults(_selectedRuntime!, force: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _portCtrl.removeListener(_onPortOrCwdChanged);
    _cwdCtrl.removeListener(_onPortOrCwdChanged);
    _nameCtrl.dispose();
    _portCtrl.dispose();
    _argsCtrl.dispose();
    _cwdCtrl.dispose();
    _exeCtrl.dispose();
    _healthPathCtrl.dispose();
    _pidFileCtrl.dispose();
    _nameFocus.dispose();
    _portFocus.dispose();
    _argsFocus.dispose();
    _cwdFocus.dispose();
    _exeFocus.dispose();
    _healthPathFocus.dispose();
    _pidFileFocus.dispose();
    for (final e in _envEntries) {
      e.dispose();
    }
    super.dispose();
  }

  void _bindEnvFocus(_EnvEntry e) {
    e.keyFocus.addListener(() {
      if (e.keyFocus.hasFocus) {
        _lastFocusedController = e.keyCtrl;
        _lastFocusedNode = e.keyFocus;
      }
    });
    e.valueFocus.addListener(() {
      if (e.valueFocus.hasFocus) {
        _lastFocusedController = e.valueCtrl;
        _lastFocusedNode = e.valueFocus;
      }
    });
  }

  Future<void> _loadRuntimes() async {
    final all = InstallManager.instance.getAllInstalled();
    // 列出所有已装的运行时（含关闭的，下拉里灰色显示）
    // 用 id Set 去重，防止同 id 被重复加入
    final seenIds = <String>{};
    final standard = <InstalledPlugin>[];
    for (final p in all) {
      if (!_knownRuntimes.contains(p.id)) continue;
      if (!seenIds.add(p.id)) continue;
      standard.add(p);
    }

    final result = <InstalledPlugin>[...standard];
    final currentRuntime = widget.existing?.runtime ?? widget.copyFrom?.runtime;
    if (currentRuntime != null &&
        currentRuntime.isNotEmpty &&
        currentRuntime != _customRuntimeKey &&
        !result.any((p) => p.id == currentRuntime)) {
      final existing = InstallManager.instance.findInstalled(currentRuntime);
      if (existing != null && seenIds.add(existing.id)) {
        result.add(existing);
      }
    }

    if (!mounted) return;
    setState(() {
      _availableRuntimes = result;
      // 默认优先选第一个「已开启」的运行时，避免默认选中关闭的
      if (_selectedRuntime == null && result.isNotEmpty) {
        final firstEnabled = result.firstWhere(
          (p) => p.enabled,
          orElse: () => result.first,
        );
        _selectedRuntime = firstEnabled.id;
      }
      // 兜底：_selectedRuntime 不在 items 中则清空，避免 Dropdown 断言
      if (_selectedRuntime != null &&
          _selectedRuntime != _customRuntimeKey &&
          !_availableRuntimes.any((p) => p.id == _selectedRuntime)) {
        _selectedRuntime = null;
      }
    });
  }

  /// 默认工作目录用占位符（跨设备可移植）
  /// 不在这里创建目录——start 时才会创建
  Future<void> _ensureDefaultCwd() async {
    if (_cwdCtrl.text.trim().isNotEmpty) return;
    if (!mounted) return;
    setState(() {
      _cwdCtrl.text = '__filesDir__/services/$_serviceId';
    });
  }

  void _onPortOrCwdChanged() {
    if (!_autoTemplateEnabled) return;

    final runtime = _selectedRuntime;
    if (runtime == null || runtime == _customRuntimeKey) return;
    final template = _runtimeArgTemplates[runtime];
    if (template == null) return;

    final current = _argsCtrl.text;
    if (current.isNotEmpty && current != _lastRenderedArgs) return;

    final rendered = _renderTemplate(template);
    if (rendered != current) {
      _argsCtrl.text = rendered;
      _lastRenderedArgs = rendered;
    }
  }

  String _renderTemplate(String template) {
    final port = _portCtrl.text.trim();
    final cwd = _cwdCtrl.text.trim();
    var out = template;
    if (port.isNotEmpty) {
      out = out.replaceAll('{port}', port);
    }
    if (cwd.isNotEmpty) {
      out = out.replaceAll('{cwd}', cwd);
    }
    return out;
  }

  Future<void> _applyRuntimeDefaults(String runtime,
      {bool force = false}) async {
    if (runtime == _customRuntimeKey) {
      if (force) {
        setState(() => _healthType = 'process');
      }
      return;
    }

    // 可执行文件：用占位符（跨设备可移植）
    final exeName = _exeNameFor(runtime);
    if (exeName != null) {
      _exeCtrl.text = '__plugin:${runtime}__/bin/$exeName';
    }

    // 启动参数
    final template = _runtimeArgTemplates[runtime];
    if (template != null) {
      final current = _argsCtrl.text;
      final rendered = _renderTemplate(template);
      if (force ||
          (current.isEmpty ||
              (current == _lastRenderedArgs && rendered != current))) {
        _argsCtrl.text = rendered;
        _lastRenderedArgs = rendered;
      }
    }

    if (force) {
      setState(() => _healthType = 'process');
    }
  }

  Future<void> _pickExe() async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null || file.path == null) return;
      setState(() => _exeCtrl.text = file.path!);
    } catch (e) {
      SmartDialog.showToast('选择文件失败：$e');
    }
  }

  Future<void> _pickCwd() async {
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null || path.isEmpty) return;
      setState(() => _cwdCtrl.text = path);
    } catch (e) {
      SmartDialog.showToast('选择目录失败：$e');
    }
  }

  Future<void> _pickPidFile() async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: 'service.pid',
        bytes: Uint8List(0),
      );
      if (uri == null) return;
      final path = uri.toFilePath();
      setState(() => _pidFileCtrl.text = path);
    } catch (e) {
      SmartDialog.showToast('选择 PID 文件失败：$e');
    }
  }

  void _addEnvEntry() {
    final e = _EnvEntry();
    _bindEnvFocus(e);
    setState(() => _envEntries.add(e));
  }

  void _removeEnvEntry(int index) {
    setState(() {
      _envEntries[index].dispose();
      _envEntries.removeAt(index);
    });
  }

  static const _placeholders = [
    '__filesDir__',
    '__sdcard__',
    '__pkg__',
    '__plugin:nodejs-win__',
    '__plugin:php-win__',
    '__plugin:python-win__',
    '__plugin:mediaProxy-win__',
    '__plugin:nodejs__',
    '__plugin:php__',
    '__plugin:python__',
    '__plugin:mediaProxy__',
  ];

  void _insertPlaceholder(String placeholder) {
    final ctrl = _lastFocusedController ?? _argsCtrl;
    final focusNode = _lastFocusedNode ?? _argsFocus;

    final text = ctrl.text;
    final sel = ctrl.selection;
    if (sel.isValid && sel.start >= 0 && sel.end <= text.length) {
      ctrl.text = text.replaceRange(sel.start, sel.end, placeholder);
      ctrl.selection =
          TextSelection.collapsed(offset: sel.start + placeholder.length);
    } else {
      ctrl.text = text + placeholder;
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }

    try {
      Future.microtask(() => focusNode.requestFocus());
    } catch (_) {}

    SmartDialog.showToast('已插入 $placeholder');
  }

  /// 下拉框当前值：不在 items 中时返回 null，避免断言
  String? get _dropdownValue {
    final v = _selectedRuntime;
    if (v == null) return null;
    if (v == _customRuntimeKey) return v;
    if (_availableRuntimes.any((p) => p.id == v)) return v;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final title = widget.existing != null
        ? '编辑服务'
        : widget.copyFrom != null
            ? '复制服务'
            : '添加服务';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: Style.mdRadius,
                ),
                child: Text(
                  widget.copyFrom != null
                      ? '已预填原配置，名称/端口已重新生成。确认无误后保存即可。'
                      : '只需三步：起个名字 → 点选运行时 → 填启动参数，其余保持默认即可。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                decoration: const InputDecoration(
                  labelText: '名称 *',
                  hintText: '如：php-t4',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _dropdownValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '运行时插件 *',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ..._availableRuntimes.map((pl) {
                    final isDisabled = !pl.enabled;
                    return DropdownMenuItem<String>(
                      value: pl.id,
                      // 仍可选（创建不拦截，启动时拦截）
                      child: Text(
                        isDisabled
                            ? '${_runtimeLabel(pl.id)}[已关闭]'
                            : _runtimeLabel(pl.id),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: isDisabled
                              ? colorScheme.outline
                              : colorScheme.onSurface,
                        ),
                      ),
                    );
                  }),
                  const DropdownMenuItem(
                    value: _customRuntimeKey,
                    child: Text(
                      '自定义（手动指定可执行文件）',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _selectedRuntime = v);
                  _applyRuntimeDefaults(v ?? '', force: true);
                },
              ),
              if (_availableRuntimes.isEmpty && !_isCustomRuntime)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '暂无可用运行时，请先到市场安装',
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),

              TextField(
                controller: _portCtrl,
                focusNode: _portFocus,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口（选填）',
                  hintText: '如：5787',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _argsCtrl,
                focusNode: _argsFocus,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '启动参数 *',
                  hintText: _selectedRuntime != null
                      ? _runtimeHints[_selectedRuntime] ?? '按运行时模板填写'
                      : '请先选择运行时',
                  border: const OutlineInputBorder(),
                  helperText: _selectedRuntime != null
                      ? _runtimeHints[_selectedRuntime]
                      : null,
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自启动', style: TextStyle(fontSize: 14)),
                subtitle: const Text('App 冷启动时自动拉起',
                    style: TextStyle(fontSize: 12)),
                value: _autostart,
                onChanged: (v) => setState(() => _autostart = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('常驻前台服务',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('App 关闭时不杀，下次启动自动收养',
                    style: TextStyle(fontSize: 12)),
                value: _keepForeground,
                onChanged: (v) => setState(() => _keepForeground = v),
              ),

              const SizedBox(height: 8),

              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                title: const Text(
                  '高级选项',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _exeCtrl,
                          focusNode: _exeFocus,
                          decoration: InputDecoration(
                            labelText:
                                _isCustomRuntime ? '可执行文件 *' : '可执行文件',
                            hintText: _isCustomRuntime
                                ? '点击右侧浏览选择 .exe'
                                : '自动从插件解析',
                            helperText: _isCustomRuntime
                                ? '自定义环境必填'
                                : '默认 __plugin:<运行时>__/bin/<exe>，可改',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '浏览',
                        icon: const Icon(Icons.folder_open),
                        onPressed: _pickExe,
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cwdCtrl,
                          focusNode: _cwdFocus,
                          decoration: const InputDecoration(
                            labelText: '工作目录',
                            hintText: '默认 __filesDir__/services/{id}',
                            helperText: '支持占位符',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '选择目录',
                        icon: const Icon(Icons.folder_open),
                        onPressed: _pickCwd,
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildHealthTypeSection(colorScheme),
                  const SizedBox(height: 12),

                  if (_isCustomRuntime) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pidFileCtrl,
                            focusNode: _pidFileFocus,
                            decoration: const InputDecoration(
                              labelText: 'PID 文件（选填）',
                              hintText: '留空自动生成 __filesDir__/services/{id}.pid',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '选择文件',
                          icon: const Icon(Icons.insert_drive_file_outlined),
                          onPressed: _pickPidFile,
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        '环境变量',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addEnvEntry,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加'),
                      ),
                    ],
                  ),
                  if (_envEntries.isNotEmpty)
                    ..._envEntries.asMap().entries.map((e) {
                      final idx = e.key;
                      final entry = e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: entry.keyCtrl,
                                focusNode: entry.keyFocus,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'KEY',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '=',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: entry.valueCtrl,
                                focusNode: entry.valueFocus,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'VALUE（支持占位符）',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close,
                                  size: 18, color: colorScheme.error),
                              onPressed: () => _removeEnvEntry(idx),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '快捷占位符（点击插入到当前焦点输入框）',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 6,
                      runSpacing: 6,
                      children: _placeholders.map((ph) {
                        return InkWell(
                          onTap: () => _insertPlaceholder(ph),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colorScheme.primary
                                    .withValues(alpha: 0.5),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ph,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildHealthTypeSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '探活方式',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildHealthChip('process', '进程', colorScheme),
              _buildHealthChip('tcp', 'TCP', colorScheme),
              _buildHealthChip('http', 'HTTP', colorScheme),
            ],
          ),
        ),
        if (_healthType == 'tcp') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _portCtrl,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'TCP 探活端口（自动联动/不需要修改）',
              hintText: '请在上方填写端口',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon:
                  Icon(Icons.link, size: 18, color: colorScheme.outline),
            ),
          ),
        ],
        if (_healthType == 'http') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _healthPathCtrl,
            focusNode: _healthPathFocus,
            decoration: InputDecoration(
              labelText: 'HTTP 探活路径',
              hintText: '/',
              isDense: true,
              prefixText: _portCtrl.text.isEmpty
                  ? 'http://127.0.0.1:?'
                  : 'http://127.0.0.1:${_portCtrl.text}',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (_healthType == 'process')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '仅检查进程存活（适合纯后台任务 / 自定义环境）',
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
          ),
      ],
    );
  }

  Widget _buildHealthChip(String value, String label, ColorScheme colorScheme) {
    final selected = _healthType == value;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _healthType = value),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? null
              : Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 14, color: colorScheme.onPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    selected ? colorScheme.onPrimary : colorScheme.primary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      SmartDialog.showToast('请输入名称');
      return;
    }
    if (_selectedRuntime == null || _selectedRuntime!.isEmpty) {
      SmartDialog.showToast('请选择运行时插件');
      return;
    }
    if (_isCustomRuntime && _exeCtrl.text.trim().isEmpty) {
      SmartDialog.showToast('自定义环境必须填写可执行文件');
      return;
    }
    final args = _argsCtrl.text.trim();
    if (args.isEmpty) {
      SmartDialog.showToast('请填写启动参数');
      return;
    }

    int? port;
    if (_portCtrl.text.trim().isNotEmpty) {
      port = int.tryParse(_portCtrl.text.trim());
      if (port == null) {
        SmartDialog.showToast('端口必须是数字');
        return;
      }
    }

    // cwd 保留占位符原文（start 时替换）
    // 不调 PluginPaths.serverDir，避免保存时创建空目录
    String cwd = _cwdCtrl.text.trim();
    if (cwd.isEmpty) {
      cwd = '__filesDir__/services/$_serviceId';
    } else if (!p.isAbsolute(cwd) &&
        !cwd.contains('__') &&
        !cwd.startsWith('.')) {
      final servicesRoot = await PluginPaths.servicesRoot();
      cwd = p.join(servicesRoot.path, cwd);
    }

    final env = <String, String>{};
    for (final e in _envEntries) {
      final k = e.keyCtrl.text.trim();
      final v = e.valueCtrl.text.trim();
      if (k.isNotEmpty) env[k] = v;
    }

    final config = ServiceConfig(
      id: _serviceId,
      name: name,
      port: port,
      runtime: _selectedRuntime!,
      args: args.split(RegExp(r'\s+')),
      cwd: cwd,
      autostart: _autostart,
      keepForeground: _keepForeground,
      env: env,
      executable: _exeCtrl.text.trim().isEmpty ? null : _exeCtrl.text.trim(),
      healthType: _healthType,
      healthPath: _healthPathCtrl.text.trim().isEmpty
          ? '/'
          : _healthPathCtrl.text.trim(),
      pidFile: _isCustomRuntime && _pidFileCtrl.text.trim().isNotEmpty
          ? _pidFileCtrl.text.trim()
          : null,
    );

    await ServiceManager.instance.addOrUpdate(config);

    if (mounted) Navigator.pop(context);
    SmartDialog.showToast(widget.copyFrom != null ? '副本已创建' : '已保存');
  }
}
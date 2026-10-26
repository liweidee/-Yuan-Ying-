// lib/modules/plugin_center/widgets/python_deps_sheet.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';

/// 展示 Python 依赖管理 BottomSheet
Future<void> showPythonDepsSheet(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PythonDepsSheet(plugin: plugin),
  );
}

class _DepItem {
  final String name;
  final String version;
  const _DepItem(this.name, this.version);
}

class _PyPiSource {
  final String label;
  final String url;
  const _PyPiSource(this.label, this.url);
}

const _pypiSources = <_PyPiSource>[
  _PyPiSource('清华', 'https://pypi.tuna.tsinghua.edu.cn/simple'),
  _PyPiSource('阿里', 'https://mirrors.aliyun.com/pypi/simple'),
  _PyPiSource('官方', 'https://pypi.org/simple'),
];

const _crawlerPreset = [
  'requests',
  'lxml',
  'pycryptodome',
  'pyquery',
  'bs4',
  'jsonpath',
  'json5',
  'jinja2',
  'cachetools',
];

class _PythonDepsSheet extends StatefulWidget {
  final InstalledPlugin plugin;

  const _PythonDepsSheet({required this.plugin});

  @override
  State<_PythonDepsSheet> createState() => _PythonDepsSheetState();
}

class _PythonDepsSheetState extends State<_PythonDepsSheet> {
  final TextEditingController _pkgCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  int _selectedSourceIdx = 0;
  String _searchQuery = '';

  bool _loading = true;
  bool _busy = false;
  List<_DepItem> _installed = [];

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  @override
  void dispose() {
    _pkgCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // 路径 / 环境
  // ============================================================

  /// python.exe 路径：{installPath}/bin/python.exe
  String get _pythonExePath =>
      p.join(widget.plugin.installPath, 'bin', 'python.exe');

  /// site-packages 路径：{installPath}/bin/Lib/site-packages
  String get _sitePackagesPath =>
      p.join(widget.plugin.installPath, 'bin', 'Lib', 'site-packages');

  Map<String, String> _buildEnv() {
    return {
      ...Platform.environment,
      'PYTHONPATH': _sitePackagesPath,
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUTF8': '1',
    };
  }

  // ============================================================
  // 依赖列表读取（读盘 *.dist-info / *.egg-info）
  // ============================================================

  Future<void> _loadInstalled() async {
    setState(() => _loading = true);
    final items = <_DepItem>[];
    try {
      final sitePackages = Directory(_sitePackagesPath);
      if (sitePackages.existsSync()) {
        final entities = sitePackages.listSync(recursive: false);
        for (final e in entities) {
          final baseName = p.basename(e.path);
          if (baseName.endsWith('.dist-info')) {
            final metadata = File(p.join(e.path, 'METADATA'));
            if (metadata.existsSync()) {
              final item = await _parseMetadata(
                await metadata.readAsString(),
                fallbackName: _stripSuffix(baseName, '.dist-info'),
              );
              if (item != null) items.add(item);
            } else {
              final fb = _parseNameVersionFromDirName(
                _stripSuffix(baseName, '.dist-info'),
              );
              if (fb != null) items.add(fb);
            }
          } else if (baseName.endsWith('.egg-info')) {
            if (e is Directory) {
              final pkgInfo = File(p.join(e.path, 'PKG-INFO'));
              if (pkgInfo.existsSync()) {
                final item = await _parseMetadata(
                  await pkgInfo.readAsString(),
                  fallbackName: _stripSuffix(baseName, '.egg-info'),
                );
                if (item != null) items.add(item);
              } else {
                final fb = _parseNameVersionFromDirName(
                  _stripSuffix(baseName, '.egg-info'),
                );
                if (fb != null) items.add(fb);
              }
            } else if (e is File) {
              final item = await _parseMetadata(
                await e.readAsString(),
                fallbackName: _stripSuffix(baseName, '.egg-info'),
              );
              if (item != null) items.add(item);
            }
          }
        }
      }
    } catch (err) {
      debugPrint('[python_deps] load installed failed: $err');
    }
    items.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _installed = items;
      _loading = false;
    });
  }

  Future<_DepItem?> _parseMetadata(
    String content, {
    required String fallbackName,
  }) async {
    String? name;
    String? version;
    final lines = content.split('\n');
    final limit = lines.length < 30 ? lines.length : 30;
    for (int i = 0; i < limit; i++) {
      final line = lines[i].trimRight();
      final lower = line.toLowerCase();
      if (lower.startsWith('name:')) {
        name = line.substring(5).trim();
      } else if (lower.startsWith('version:')) {
        version = line.substring(8).trim();
      }
      if (name != null && version != null) break;
    }
    if (name == null || name.isEmpty) {
      return _parseNameVersionFromDirName(fallbackName);
    }
    return _DepItem(name, version ?? '');
  }

  _DepItem? _parseNameVersionFromDirName(String raw) {
    if (raw.isEmpty) return null;
    final parts = raw.split('-');
    for (int i = parts.length - 1; i >= 1; i--) {
      final seg = parts[i];
      if (seg.isNotEmpty && RegExp(r'^\d').hasMatch(seg)) {
        final name = parts.sublist(0, i).join('-');
        final version = parts.sublist(i).join('-');
        if (name.isNotEmpty) return _DepItem(name, version);
      }
    }
    return _DepItem(raw, '');
  }

  String _stripSuffix(String s, String suffix) {
    return s.endsWith(suffix) ? s.substring(0, s.length - suffix.length) : s;
  }

  List<_DepItem> get _filteredDeps {
    if (_searchQuery.isEmpty) return _installed;
    final q = _searchQuery.toLowerCase();
    return _installed
        .where((d) =>
            d.name.toLowerCase().contains(q) ||
            d.version.toLowerCase().contains(q))
        .toList();
  }

  // ============================================================
  // pip 执行
  // ============================================================

  /// 执行 pip 命令，返回 (success, outputText)
  Future<({bool success, String output})> _runPip(
    List<String> args,
  ) async {
    final pythonExe = File(_pythonExePath);
    if (!pythonExe.existsSync()) {
      return (success: false, output: '找不到 python.exe：$_pythonExePath');
    }
    try {
      final result = await Process.run(
        _pythonExePath,
        ['-m', 'pip', ...args],
        workingDirectory: p.join(widget.plugin.installPath, 'bin'),
        environment: _buildEnv(),
        stdoutEncoding: Utf8Codec(allowMalformed: true),
        stderrEncoding: Utf8Codec(allowMalformed: true),
      );
      final stdoutText = result.stdout.toString().trim();
      final stderrText = result.stderr.toString().trim();
      final combined = [
        if (stdoutText.isNotEmpty) stdoutText,
        if (stderrText.isNotEmpty) stderrText,
      ].join('\n');
      return (success: result.exitCode == 0, output: combined);
    } catch (e) {
      return (success: false, output: 'pip 执行异常：$e');
    }
  }

  /// 安装依赖
  Future<void> _doInstall(String pkgSpec, String mirrorUrl) async {
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '正在安装 $pkgSpec…');
    final r = await _runPip([
      'install',
      pkgSpec,
      '-i',
      mirrorUrl,
    ]);
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.success) {
      SmartDialog.showToast('安装成功：$pkgSpec');
      await _loadInstalled();
    } else {
      _showErrorDialog('安装失败：$pkgSpec', r.output);
    }
  }

  /// 批量安装（爬虫九件套）
  Future<void> _doInstallBatch(List<String> pkgs, String mirrorUrl) async {
    setState(() => _busy = true);
    SmartDialog.showLoading(
      msg: '正在安装 ${pkgs.length} 个依赖…',
    );
    final r = await _runPip([
      'install',
      ...pkgs,
      '-i',
      mirrorUrl,
    ]);
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.success) {
      SmartDialog.showToast('爬虫依赖安装完成');
      await _loadInstalled();
    } else {
      _showErrorDialog('批量安装失败', r.output);
    }
  }

  /// 卸载依赖
  Future<void> _doUninstall(String pkgName) async {
    setState(() => _busy = true);
    SmartDialog.showLoading(msg: '正在卸载 $pkgName…');
    final r = await _runPip(['uninstall', '-y', pkgName]);
    SmartDialog.dismiss();
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.success) {
      SmartDialog.showToast('已卸载 $pkgName');
      await _loadInstalled();
    } else {
      _showErrorDialog('卸载失败：$pkgName', r.output);
    }
  }

  /// 错误详情弹窗（含 pip 输出，可滚动复制）
  void _showErrorDialog(String title, String detail) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              detail.isEmpty ? '（无输出）' : detail,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: Style.bottomSheetRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Python 依赖管理',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    widget.plugin.id,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pkgCtrl,
                            enabled: !_busy,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText:
                                  '包名或 包名==版本（如 flask、requests==2.32）',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _busy ? null : _onInstall,
                          icon: _busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download, size: 16),
                          label: const Text('安装'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            children: [
                              for (int i = 0; i < _pypiSources.length; i++)
                                _buildSourceChip(i),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _onCrawlerPreset,
                          icon: const Icon(Icons.bolt, size: 16),
                          label: const Text('爬虫一键装'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '已装依赖 (${_installed.length})',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_loading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            tooltip: '刷新',
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _busy ? null : _loadInstalled,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '搜索已装依赖（名称/版本）',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_filteredDeps.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            _installed.isEmpty
                                ? '未检测到已装依赖'
                                : '未找到匹配的依赖',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                      )
                    else
                      ..._filteredDeps.map((d) => _buildDepItem(d)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceChip(int idx) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = idx == _selectedSourceIdx;
    final src = _pypiSources[idx];
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _busy ? null : () => setState(() => _selectedSourceIdx = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.15)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 12, color: colorScheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              src.label,
              style: TextStyle(
                fontSize: 12,
                color:
                    selected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepItem(_DepItem dep) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.settings_outlined,
            size: 18,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dep.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  dep.version.isEmpty ? '未知版本' : dep.version,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '卸载',
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: colorScheme.error,
            ),
            onPressed: _busy ? null : () => _onUninstall(dep),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 动作
  // ============================================================

  void _onInstall() {
    final pkg = _pkgCtrl.text.trim();
    if (pkg.isEmpty) {
      SmartDialog.showToast('请输入包名');
      return;
    }
    final src = _pypiSources[_selectedSourceIdx];
    _doInstall(pkg, src.url);
  }

  void _onCrawlerPreset() {
    final src = _pypiSources[_selectedSourceIdx];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('爬虫一键装'),
        content: Text(
          '将安装以下 ${_crawlerPreset.length} 个依赖（源：${src.label}）：\n\n'
          '${_crawlerPreset.join('、')}',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doInstallBatch(_crawlerPreset, src.url);
            },
            child: const Text('开始安装'),
          ),
        ],
      ),
    );
  }

  void _onUninstall(_DepItem dep) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载依赖'),
        content: Text(
          '确定要卸载 ${dep.name}'
          '${dep.version.isNotEmpty ? ' (${dep.version})' : ''} 吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doUninstall(dep.name);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }
}
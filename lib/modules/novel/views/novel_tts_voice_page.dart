import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/novel/services/novel_tts_service.dart';

class NovelTtsVoicePage extends StatefulWidget {
  const NovelTtsVoicePage({super.key});

  @override
  State<NovelTtsVoicePage> createState() => _NovelTtsVoicePageState();
}

class _NovelTtsVoicePageState extends State<NovelTtsVoicePage> {
  late final NovelTtsService _service;
  final TextEditingController _serviceUrl = TextEditingController();
  final TextEditingController _testText = TextEditingController(
    text: '永远相信美好的事情即将发生。',
  );

  NovelTtsServiceStatus? _status;
  bool _checking = false;
  bool _starting = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _service = Get.find<NovelTtsService>();
    if (NovelTtsService.isSupportedPlatform) {
      _refreshStatus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SmartDialog.showToast(
            NovelTtsService.unsupportedPlatformMessage,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    if (_previewing) {
      unawaited(_service.stop());
    }
    _serviceUrl.dispose();
    _testText.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (mounted) setState(() => _checking = true);
    try {
      final status = await _service.raTtsStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        if (_serviceUrl.text.trim().isEmpty) {
          _serviceUrl.text = status.baseUrl;
        }
      });
    } catch (e) {
      SmartDialog.showToast('检测朗读服务失败：$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _startService() async {
    setState(() => _starting = true);
    try {
      final status = await _service.startRaTts();
      if (mounted) {
        setState(() {
          _status = status;
          _serviceUrl.text = status.baseUrl;
        });
      }
      SmartDialog.showToast('Edge 朗读 TTS 已启动');
    } catch (e) {
      SmartDialog.showToast('启动失败：$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<bool> _ensureServiceReady() async {
    try {
      await _service.ensureRaTtsReady();
      return true;
    } catch (e) {
      SmartDialog.showToast('$e');
      return false;
    }
  }

  Future<void> _openQuickAdd() async {
    if (!await _ensureServiceReady()) return;
    final baseUrl = _serviceUrl.text.trim();
    if (baseUrl.isEmpty) {
      SmartDialog.showToast('请先填写朗读服务地址');
      return;
    }
    SmartDialog.showLoading(msg: '加载音色中...');
    try {
      final remote = await _service.fetchRaTtsVoices(baseUrl: baseUrl);
      SmartDialog.dismiss();
      if (!mounted) return;
      if (remote.isEmpty) {
        SmartDialog.showToast('服务未返回可用音色');
        return;
      }
      final selected = await showModalBottomSheet<List<NovelTtsVoice>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _QuickAddVoicesSheet(
          voices: remote,
          existingIds: _service.networkVoices.map((voice) => voice.id).toSet(),
          service: _service,
          baseUrl: baseUrl,
        ),
      );
      if (selected == null || selected.isEmpty) return;
      final result = await _service.addNetworkVoices(selected);
      if (!mounted) return;
      setState(() {});
      SmartDialog.showToast(
        '已添加 ${result.added} 个音色'
        '${result.skipped > 0 ? '，跳过 ${result.skipped} 个' : ''}',
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('获取音色失败：$e');
    }
  }

  Future<void> _showImportMenu() async {
    final action = await showModalBottomSheet<_VoiceImportAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴 JSON'),
              subtitle: const Text('从剪贴板导入音色包'),
              onTap: () => Navigator.pop(
                context,
                _VoiceImportAction.paste,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('从文件导入'),
              subtitle: const Text('选择本地 JSON 文件'),
              onTap: () => Navigator.pop(
                context,
                _VoiceImportAction.file,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('从 URL 导入'),
              subtitle: const Text('下载 legado HttpTTS 音色 JSON'),
              onTap: () => Navigator.pop(
                context,
                _VoiceImportAction.url,
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case _VoiceImportAction.paste:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim() ?? '';
        if (text.isEmpty) {
          SmartDialog.showToast('剪贴板为空');
          return;
        }
        await _importText(text);
      case _VoiceImportAction.file:
        await _importFile();
      case _VoiceImportAction.url:
        await _importUrl();
    }
  }

  Future<void> _importFile() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      final path = picked?.path;
      if (path == null || path.isEmpty) return;
      await _importText(await File(path).readAsString());
    } catch (e) {
      SmartDialog.showToast('读取音色文件失败：$e');
    }
  }

  Future<void> _importUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 URL 导入音色包'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/voices.json',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    try {
      final result = await _service.importVoiceUrl(url);
      _afterImport(result);
    } catch (e) {
      SmartDialog.showToast('URL 导入失败：$e');
    }
  }

  Future<void> _importText(String text) async {
    try {
      final result = await _service.importVoiceText(text);
      _afterImport(result);
    } catch (e) {
      SmartDialog.showToast('音色包解析失败：$e');
    }
  }

  void _afterImport(NovelTtsImportResult result) {
    if (!mounted) return;
    setState(() {});
    SmartDialog.showToast(
      result.added == 0
          ? '没有新增音色（可能已存在）'
          : '已导入 ${result.added} 个音色'
                '${result.skipped > 0 ? '，跳过 ${result.skipped} 个' : ''}',
    );
  }

  Future<void> _preview(NovelTtsVoice voice) async {
    if (_previewing) return;
    if (!await _ensureServiceReady()) return;
    setState(() => _previewing = true);
    try {
      await _service.previewVoice(voice, _testText.text);
    } catch (e) {
      SmartDialog.showToast('试听失败：$e');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _editVoice(NovelTtsVoice voice) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(voice.toJson()),
    );
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑音色 JSON'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 18,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    final parsed = _service.parseSingleVoice(text);
    if (parsed == null || parsed.id.isEmpty) {
      SmartDialog.showToast('请输入一个完整的音色 JSON 对象');
      return;
    }
    try {
      await _service.updateNetworkVoice(
        NovelTtsVoice(
          id: voice.id,
          name: parsed.name,
          contentType: parsed.contentType,
          url: parsed.url,
        ),
      );
      if (!mounted) return;
      setState(() {});
      SmartDialog.showToast('音色已保存');
    } catch (e) {
      SmartDialog.showToast('保存失败：$e');
    }
  }

  Future<void> _exportVoice(NovelTtsVoice voice) async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(voice.toJson()),
      ),
    );
    SmartDialog.showToast('音色 JSON 已复制');
  }

  Future<void> _deleteVoice(NovelTtsVoice voice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除音色'),
        content: Text('确定删除「${voice.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.removeNetworkVoice(voice.id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showVoiceActions(NovelTtsVoice voice) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('设为当前音色'),
              onTap: () => Navigator.pop(context, 'select'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑 JSON'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('导出 JSON'),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'select':
        await _service.setNetworkVoice(voice.id);
        if (mounted) setState(() {});
      case 'edit':
        await _editVoice(voice);
      case 'export':
        await _exportVoice(voice);
      case 'delete':
        await _deleteVoice(voice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!NovelTtsService.isSupportedPlatform) {
      return Scaffold(
        appBar: AppBar(title: const Text('朗读音色包')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              NovelTtsService.unsupportedPlatformMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.outline),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('朗读音色包')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _serviceCard(colorScheme),
          const SizedBox(height: 12),
          _quickAddCard(colorScheme),
          const SizedBox(height: 12),
          _testCard(colorScheme),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '已导入音色包（${_service.networkVoices.length}）',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _showImportMenu,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('导入'),
              ),
            ],
          ),
          if (_service.networkVoices.isEmpty)
            _emptyVoiceCard(colorScheme)
          else
            for (final voice in _service.networkVoices)
              _voiceCard(voice, colorScheme),
        ],
      ),
    );
  }

  Widget _serviceCard(ColorScheme colorScheme) {
    final status = _status;
    final running = status?.running == true;
    final bool installed = status?.pluginInstalled ?? false;
    final String statusText;
    if (status == null) {
      statusText = '检测中…';
    } else if (!installed) {
      statusText = '未安装 Edge 朗读 TTS';
    } else if (!status.pluginEnabled) {
      statusText = '插件已关闭';
    } else if (!status.serviceConfigured) {
      statusText = '服务配置缺失';
    } else if (running) {
      statusText = '服务运行中';
    } else {
      statusText = status.message ?? '服务未启动';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.cloud_done : Icons.cloud_off,
                  color: running ? Colors.green : colorScheme.outline,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Edge 朗读 TTS 服务',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '重新检测',
                  onPressed: _checking ? null : _refreshStatus,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12.5,
                color: running ? Colors.green : colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serviceUrl,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'http://127.0.0.1:38080',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (!installed || status?.pluginEnabled != true)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Get.toNamed(AppPages.pluginCenter);
                      await _refreshStatus();
                    },
                    icon: const Icon(Icons.extension_outlined, size: 18),
                    label: const Text('前往插件中心'),
                  )
                else if (!running)
                  FilledButton.icon(
                    onPressed: _starting ? null : _startService,
                    icon: _starting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('启动服务'),
                  ),
                const SizedBox(width: 12),
                Text(
                  '需先安装 nodejs 运行时',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAddCard(ColorScheme colorScheme) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.auto_awesome, color: colorScheme.primary),
        title: const Text('快捷添加音色'),
        subtitle: const Text('从 ra-tts 获取全部音色，搜索、分组并批量添加'),
        trailing: FilledButton(
          onPressed: _openQuickAdd,
          child: const Text('选择音色'),
        ),
      ),
    );
  }

  Widget _testCard(ColorScheme colorScheme) {
    final current = _service.currentNetworkVoice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '朗读测试',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _testText,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '输入试听文本',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '恢复默认',
                      onPressed: () {
                        _testText.text = '永远相信美好的事情即将发生。';
                      },
                      icon: const Icon(Icons.restart_alt),
                    ),
                    IconButton(
                      tooltip: '试听当前音色',
                      onPressed: current == null || _previewing
                          ? null
                          : () => _preview(current),
                      icon: _previewing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.headphones),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              current == null ? '请先选择或导入网络音色' : '当前：${current.name}',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyVoiceCard(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.record_voice_over_outlined, color: colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              '还没有网络音色',
              style: TextStyle(color: colorScheme.outline),
            ),
            const SizedBox(height: 4),
            Text(
              '可快捷添加 Edge 音色，或导入 legado HttpTTS 音色包',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceCard(NovelTtsVoice voice, ColorScheme colorScheme) {
    final selected = voice.id == _service.networkVoiceId;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await _service.setNetworkVoice(voice.id);
          if (mounted) setState(() {});
        },
        onLongPress: () => _showVoiceActions(voice),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            voice.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '使用中',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _endpointSummary(voice.url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '试听',
                onPressed: _previewing ? null : () => _preview(voice),
                icon: const Icon(Icons.headphones, size: 20),
              ),
              PopupMenuButton<String>(
                onSelected: (action) async {
                  switch (action) {
                    case 'select':
                      await _service.setNetworkVoice(voice.id);
                      if (mounted) setState(() {});
                    case 'edit':
                      await _editVoice(voice);
                    case 'export':
                      await _exportVoice(voice);
                    case 'delete':
                      await _deleteVoice(voice);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'select', child: Text('设为当前音色')),
                  PopupMenuItem(value: 'edit', child: Text('编辑 JSON')),
                  PopupMenuItem(value: 'export', child: Text('导出 JSON')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _endpointSummary(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host}$port${uri.path}';
  }
}

enum _VoiceImportAction { paste, file, url }

class _QuickAddVoicesSheet extends StatefulWidget {
  final List<RaTtsRemoteVoice> voices;
  final Set<String> existingIds;
  final NovelTtsService service;
  final String baseUrl;

  const _QuickAddVoicesSheet({
    required this.voices,
    required this.existingIds,
    required this.service,
    required this.baseUrl,
  });

  @override
  State<_QuickAddVoicesSheet> createState() => _QuickAddVoicesSheetState();
}

class _QuickAddVoicesSheetState extends State<_QuickAddVoicesSheet> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _selected = {};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<RaTtsRemoteVoice> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.voices;
    return widget.voices.where((voice) {
      return voice.label.toLowerCase().contains(q) ||
          voice.shortName.toLowerCase().contains(q) ||
          voice.locale.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<RaTtsRemoteVoice>>{};
    for (final voice in _filtered) {
      groups.putIfAbsent(voice.locale, () => []).add(voice);
    }
    final locales = groups.keys.toList()
      ..sort((a, b) {
        final aZh = a.toLowerCase().startsWith('zh');
        final bZh = b.toLowerCase().startsWith('zh');
        if (aZh != bZh) return aZh ? -1 : 1;
        return a.compareTo(b);
      });
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '快捷添加音色',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${widget.voices.length} 个',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '搜索名称 / ShortName / 语言',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
              children: [
                for (final locale in locales) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                    child: Text(
                      locale.isEmpty ? '未知语言' : locale,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  for (final voice in groups[locale]!) _voiceRow(voice),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final voices = widget.voices
                              .where(
                                (voice) => _selected.contains(voice.shortName),
                              )
                              .map(
                                (voice) => widget.service.createRaTtsVoice(
                                  voice,
                                  baseUrl: widget.baseUrl,
                                ),
                              )
                              .toList();
                          Navigator.pop(context, voices);
                        },
                  child: Text(
                    _selected.isEmpty ? '请先勾选音色' : '添加 ${_selected.length} 个音色',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceRow(RaTtsRemoteVoice voice) {
    final exists = widget.existingIds.contains(voice.shortName);
    final checked = _selected.contains(voice.shortName);
    final sub = [
      voice.shortName,
      if (voice.gender.isNotEmpty) voice.gender,
      if (voice.personalities.isNotEmpty) voice.personalities,
    ].join(' · ');
    return CheckboxListTile(
      value: exists || checked,
      onChanged: exists
          ? null
          : (value) {
              setState(() {
                if (value == true) {
                  _selected.add(voice.shortName);
                } else {
                  _selected.remove(voice.shortName);
                }
              });
            },
      title: Text(
        voice.label.isEmpty ? voice.shortName : voice.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5),
      ),
      subtitle: Text(
        exists ? '$sub · 已添加' : sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

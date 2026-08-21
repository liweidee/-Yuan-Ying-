import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:yuanying/services/catvod_log_service.dart';
import 'package:yuanying/nodejs/nodejs_service.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'dart:convert';

class CatVodLogPage extends StatefulWidget {
  const CatVodLogPage({super.key});

  @override
  State<CatVodLogPage> createState() => _CatVodLogPageState();
}

class _CatVodLogPageState extends State<CatVodLogPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isAutoScroll = true;
  late CatVodLogService _logService;

  @override
  void initState() {
    super.initState();
    _logService = Get.find<CatVodLogService>();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 50) {
      if (_isAutoScroll) {
        setState(() => _isAutoScroll = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除日志'),
        content: const Text('确定要清除所有猫影视日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _logService.clearLogs();
      SmartDialog.showToast('日志已清除');
    }
  }

  void _copyAllLogs() async {
    final text = _logService.getAllLogsText();
    await Clipboard.setData(ClipboardData(text: text));
    SmartDialog.showToast('已复制到剪贴板');
  }

  /// 诊断蜘蛛源
  Future<void> _diagnoseSpider() async {
    SmartDialog.showToast('正在诊断...');
    try {
      final result = await NodeJSService.instance.diagnoseSpider();
      final text = const JsonEncoder.withIndent('  ').convert(result);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('蜘蛛源诊断结果'),
            content: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  SmartDialog.showToast('已复制到剪贴板');
                },
                child: const Text('复制'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      SmartDialog.showToast('诊断失败: $e');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('猫影视日志'),
        backgroundColor: isDark ? Colors.grey[800] : null,
        actions: [
          IconButton(
            icon: Icon(_isAutoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
            tooltip: _isAutoScroll ? '自动滚动已开启' : '自动滚动已关闭',
            onPressed: () {
              setState(() {
                _isAutoScroll = !_isAutoScroll;
                if (_isAutoScroll) _scrollToBottom();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制所有日志',
            onPressed: _copyAllLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '清除日志',
            onPressed: _clearLogs,
          ),
          IconButton(
            icon: Icon(Icons.bug_report, color: Theme.of(context).colorScheme.primary),
            tooltip: '诊断蜘蛛源',
            onPressed: _diagnoseSpider,
          ),
        ],
      ),
      body: Container(
        color: isDark ? Colors.black87 : Colors.grey[100],
        child: Column(
          children: [
            // 顶部提示横幅（完全复制 tvbox_flutter）
            Container(
              padding: const EdgeInsets.all(12),
              color: isDark ? Colors.blueGrey[900] : Colors.blueGrey[100],
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '提示: 点击右上角的复制按钮可以将日志复制到剪贴板，然后发给我分析问题',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white70),
                    onPressed: _copyAllLogs,
                    tooltip: '复制日志',
                  ),
                ],
              ),
            ),
            // 日志列表
            Expanded(
              child: Obx(() {
                final logs = _logService.logs;
                // 自动滚动到最新
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_isAutoScroll && logs.isNotEmpty) {
                    _scrollToBottom();
                  }
                });

                if (logs.isEmpty) {
                  return const Center(
                    child: Text(
                      '暂无猫影视日志',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final line = logs[index];
                    Color textColor;
                    if (line.contains('[ERROR]') || line.contains('❌')) {
                      textColor = Colors.red[300]!;
                    } else if (line.contains('[WARN]') || line.contains('⚠️')) {
                      textColor = Colors.orange[300]!;
                    } else if (line.contains('[INFO]') || line.contains('✅')) {
                      textColor = Colors.green[300]!;
                    } else {
                      textColor = isDark ? Colors.white70 : Colors.black87;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
            // 底部状态栏
            Container(
              padding: const EdgeInsets.all(8),
              color: isDark ? Colors.grey[900] : Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Obx(() => Text(
                        '日志条目: ${_logService.logCount.value}',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 12,
                        ),
                      )),
                  Text(
                    '自动滚动: ${_isAutoScroll ? "开启" : "关闭"}',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // 底部诊断按钮（与 tvbox_flutter 一致）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: isDark ? Colors.grey[850] : Colors.grey[300],
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bug_report),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                label: const Text('诊断蜘蛛源'),
                onPressed: _diagnoseSpider,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
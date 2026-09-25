import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../utils/lx_logger.dart';

class LxDebugLogPage extends StatefulWidget {
  const LxDebugLogPage({super.key});

  @override
  State<LxDebugLogPage> createState() => _LxDebugLogPageState();
}

class _LxDebugLogPageState extends State<LxDebugLogPage> {
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logText = LxLogger.text;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('调试日志', style: TextStyle(fontSize: 18)),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => setState(() => _version++),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logText));
              SmartDialog.showToast('日志已复制');
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () {
              LxLogger.clear();
              setState(() => _version++);
            },
          ),
        ],
      ),
      body: logText.isEmpty
          ? Center(
              child: Text('暂无日志',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                logText,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
    );
  }
}
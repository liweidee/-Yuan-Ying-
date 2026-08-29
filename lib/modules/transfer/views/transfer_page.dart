// lib/modules/transfer/views/transfer_page.dart
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/modules/transfer/services/transfer_server.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/core/constants/storage_keys.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final TransferServer _server = TransferServer.instance;
  bool _busy = false;
  final List<String> _events = [];
  late QrImage _qrImage;

  @override
  void initState() {
    super.initState();

    // 初始化二维码（占位数据）
    _qrImage = QrImage(
      QrCode.fromData(
        data: 'http://127.0.0.1:12346',
        errorCorrectLevel: QrErrorCorrectLevel.H,
      ),
    );

    _server.onFileUploaded = (path) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, '文件已保存: ${path.split('/').last}');
        if (_events.length > 30) _events.removeLast();
      });
    };

    if (StorageManager.getSetting<bool>(SettingBoxKey.transferAutoStart) ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _toggleServer();
      });
    }
  }

  void _updateQrCode(String url) {
    setState(() {
      _qrImage = QrImage(
        QrCode.fromData(
          data: url,
          errorCorrectLevel: QrErrorCorrectLevel.H,
        ),
      );
    });
  }

  Future<void> _toggleServer() async {
    setState(() => _busy = true);
    try {
      if (_server.running) {
        await _server.stop();
        await StorageManager.setSetting(SettingBoxKey.transferAutoStart, false);
      } else {
        await _server.start();
        await StorageManager.setSetting(SettingBoxKey.transferAutoStart, true);
        _updateQrCode(_server.url);
      }
      setState(() {});
    } catch (e) {
      SmartDialog.showToast('启动失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _server.running;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi 互传'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      running ? Icons.wifi : Icons.wifi_off,
                      color: running ? Colors.green : colorScheme.outline,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      running ? '服务已开启' : '服务未开启',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: running ? Colors.green : colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (running) ...[
                  // 使用 SizedBox 控制大小，不传 decoration 使用默认样式
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: PrettyQrView(
                      qrImage: _qrImage,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    _server.url,
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在同一网络下用浏览器扫描二维码或访问上方地址',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.outline,
                      fontSize: 12.5,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildPathInfo(context),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    '开启后可通过浏览器上传文件到本机',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.outline,
                      fontSize: 13,
                      height: 1.9,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _toggleServer,
                    icon: Icon(
                      running ? Icons.stop_circle_outlined : Icons.wifi,
                      size: 20,
                    ),
                    label: Text(
                      _busy ? '请稍候…' : (running ? '停止服务' : '开启服务'),
                      style: const TextStyle(fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: running ? colorScheme.error : colorScheme.primary,
                      foregroundColor: running ? colorScheme.onError : colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_events.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '传输记录',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            ..._events.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPathInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final configPath = StorageManager.getSetting<String>(SettingBoxKey.downloadPath);
    final displayPath = configPath?.isNotEmpty == true ? configPath : '默认目录（文档/transfers）';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 16,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '保存位置: $displayPath',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
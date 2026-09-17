import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/network_media/widgets/server_form_kit.dart';

import '../controllers/ftp_server_controller.dart';
import '../models/ftp_server.dart';
import '../services/ftp_service.dart';

class FtpServerConfigPage extends StatelessWidget {
  const FtpServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<FtpServerController>()) {
      Get.put(FtpServerController());
    }
    final c = Get.find<FtpServerController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP / SFTP 服务器'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加服务器',
            onPressed: () => _openForm(context, c),
          ),
        ],
      ),
      body: Obx(() {
        if (c.servers.isEmpty) {
          return _emptyState(context, cs, () => _openForm(context, c));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Style.safeSpace),
          itemCount: c.servers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _serverCard(context, c, c.servers[i]),
        );
      }),
    );
  }

  Widget _emptyState(
      BuildContext ctx, ColorScheme cs, VoidCallback onAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('暂无 FTP/SFTP 服务器', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加服务器'),
          ),
        ],
      ),
    );
  }

  Widget _serverCard(
      BuildContext ctx, FtpServerController c, FtpServer s) {
    final theme = Theme.of(ctx);
    final cs = theme.colorScheme;
    final isCurrent = c.currentId.value == s.id;
    final isSftp = s.isSftp;

    return Card(
      color: cs.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isSftp ? Icons.lock_outline : Icons.folder_outlined,
            color: cs.primary,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '当前',
                  style: TextStyle(fontSize: 10, color: cs.onPrimary),
                ),
              ),
          ],
        ),
        subtitle: Text(
          s.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: cs.outline),
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                _openForm(ctx, c, existing: s);
                break;
              case 'delete':
                final ok = await _confirmDelete(ctx, s);
                if (ok == true) await c.deleteServer(s.id);
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: () async {
          await c.selectServer(s.id);
          Get.toNamed(AppPages.ftpMain, arguments: {'serverId': s.id});
        },
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext ctx, FtpServer s) {
    final cs = Theme.of(ctx).colorScheme;
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('删除服务器'),
        content: Text('确认删除 "${s.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('删除', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext ctx, FtpServerController c,
      {FtpServer? existing}) {
    final isEdit = existing != null;
    showDialog<bool>(
      context: ctx,
      builder: (_) => _ServerFormDialog(
        existing: existing,
        onSave: (server) async {
          if (isEdit) {
            await c.updateServer(server);
          } else {
            await c.addServer(server);
          }
        },
        newId: c.newId,
      ),
    );
  }
}

class _ServerFormDialog extends StatefulWidget {
  const _ServerFormDialog({
    this.existing,
    required this.onSave,
    required this.newId,
  });

  final FtpServer? existing;
  final Future<void> Function(FtpServer server) onSave;
  final String Function() newId;

  @override
  State<_ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends State<_ServerFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _path;
  late String _protocol;

  bool _testing = false;
  bool _saving = false;
  String? _resultMessage;
  bool? _resultSuccess;

  bool get _isEdit => widget.existing != null;
  bool get _isSftp => _protocol == 'sftp';

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '');
    _port = TextEditingController(text: (s?.port ?? 21).toString());
    _username = TextEditingController(text: s?.username ?? '');
    _password = TextEditingController(text: '');
    _path = TextEditingController(text: s?.initialPath ?? '/');
    _protocol = s?.protocol ?? 'ftp';
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _path.dispose();
    super.dispose();
  }

  FtpServer _collect() {
    final port = int.tryParse(_port.text.trim()) ?? (_isSftp ? 22 : 21);
    return FtpServer(
      id: widget.existing?.id ?? widget.newId(),
      name: _name.text.trim().isEmpty
          ? _host.text.trim()
          : _name.text.trim(),
      host: _host.text.trim(),
      port: port,
      protocol: _protocol,
      username: _username.text.trim(),
      password: _password.text.isEmpty && _isEdit
          ? (widget.existing?.password ?? '')
          : _password.text,
      initialPath: _path.text.trim().isEmpty ? '/' : _path.text.trim(),
    );
  }

  String? _validate() {
    if (_host.text.trim().isEmpty) return '主机不能为空';
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      return '端口必须是 1-65535';
    }
    return null;
  }

  Future<void> _test() async {
    final err = _validate();
    if (err != null) {
      setState(() {
        _resultSuccess = false;
        _resultMessage = err;
      });
      return;
    }
    setState(() {
      _testing = true;
      _resultMessage = null;
      _resultSuccess = null;
    });
    final result = await FtpService.instance.testConnection(_collect());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _resultSuccess = result.ok;
      _resultMessage = result.ok ? '连接成功' : (result.error ?? '连接失败');
    });
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() {
        _resultSuccess = false;
        _resultMessage = err;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_collect());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _resultSuccess = false;
        _resultMessage = '保存失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return serverDialog(
      title: ServerDialogTitle(
        icon: _isEdit ? Icons.edit_outlined : Icons.folder_outlined,
        title: _isEdit ? '编辑 FTP/SFTP' : '添加 FTP/SFTP',
        subtitle: 'FTP / SFTP',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 协议选择
                    DropdownButtonFormField<String>(
                      value: _protocol,
                      decoration: serverFieldDecoration(
                        context,
                        label: '协议',
                        icon: Icons.swap_horiz,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ftp', child: Text('FTP')),
                        DropdownMenuItem(value: 'sftp', child: Text('SFTP')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _protocol = v;
                          // 端口默认值联动
                          final current = _port.text.trim();
                          if (current.isEmpty ||
                              current == '21' ||
                              current == '22') {
                            _port.text = v == 'sftp' ? '22' : '21';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    ServerTextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: serverFieldDecoration(
                        context,
                        label: '服务器名称',
                        hint: '例如：家庭 NAS',
                        icon: Icons.badge_outlined,
                        optional: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: ServerTextField(
                            controller: _host,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            decoration: serverFieldDecoration(
                              context,
                              label: '主机',
                              hint: '192.168.1.100',
                              icon: Icons.lan_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: ServerTextField(
                            controller: _port,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: serverFieldDecoration(
                              context,
                              label: '端口',
                              hint: _isSftp ? '22' : '21',
                              icon: Icons.settings_ethernet,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ServerTextField(
                      controller: _username,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: serverFieldDecoration(
                        context,
                        label: '用户名',
                        hint: 'admin',
                        icon: Icons.person_outline,
                        optional: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ServerPasswordField(
                      icon: Icons.lock_outline,
                      controller: _password,
                      label: _isEdit ? '密码（留空保持不变）' : '密码',
                      hint: '••••••••',
                    ),
                    const SizedBox(height: 14),
                    ServerTextField(
                      controller: _path,
                      textInputAction: TextInputAction.done,
                      decoration: serverFieldDecoration(
                        context,
                        label: '初始路径',
                        hint: '/',
                        icon: Icons.folder_open_outlined,
                        optional: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_resultMessage != null)
              ServerResultBanner(
                success: _resultSuccess == true,
                message: _resultMessage!,
                margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: theme.colorScheme.outline),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _testing || _saving ? null : _test,
          icon: _testing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering, size: 16),
          label: const Text('测试'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _testing || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: const Text('保存'),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/network_media/widgets/server_form_kit.dart';
import '../controllers/webdav_server_controller.dart';
import '../models/webdav_server.dart';
import '../services/webdav_service.dart';

class WebDavServerConfigPage extends StatelessWidget {
  const WebDavServerConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<WebDavServerController>()) {
      Get.put(WebDavServerController());
    }
    final c = Get.find<WebDavServerController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 服务器'),
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
          Icon(Icons.cloud_outlined, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('暂无 WebDAV 服务器', style: TextStyle(color: cs.outline)),
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
      BuildContext ctx, WebDavServerController c, WebDavServer s) {
    final theme = Theme.of(ctx);
    final cs = theme.colorScheme;
    final isCurrent = c.currentId.value == s.id;

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
          child: Icon(Icons.cloud, color: cs.primary),
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
          Get.toNamed(AppPages.webdavMain, arguments: {'serverId': s.id});
        },
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext ctx, WebDavServer s) {
    final cs = Theme.of(ctx).colorScheme;
    return showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('删除服务器'),
        content: Text('确认删除 "${s.name}" 吗？此操作不影响服务器本身。'),
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

  /// 打开添加/编辑表单弹窗
  void _openForm(BuildContext ctx, WebDavServerController c,
      {WebDavServer? existing}) {
    final isEdit = existing != null;
    showDialog<bool>(
      context: ctx,
      builder: (_) => _ServerFormDialog(
        existing: existing,
        onSave: ({
          required name,
          required url,
          required username,
          required password,
          required allowSelfSigned,
        }) async {
          if (isEdit) {
            await c.updateServer(
              existing.id,
              name: name,
              url: url,
              username: username,
              password: password,
              allowSelfSigned: allowSelfSigned,
            );
          } else {
            await c.addServer(
              name: name,
              url: url,
              username: username,
              password: password,
              allowSelfSigned: allowSelfSigned,
            );
          }
        },
      ),
    );
  }
}

/// 服务器添加/编辑弹窗（DreamPlayer 风格）
class _ServerFormDialog extends StatefulWidget {
  const _ServerFormDialog({
    this.existing,
    required this.onSave,
  });

  final WebDavServer? existing;
  final Future<void> Function({
    required String name,
    required String url,
    required String username,
    required String password,
    required bool allowSelfSigned,
  }) onSave;

  @override
  State<_ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends State<_ServerFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late bool _allowSelfSigned;

  bool _testing = false;
  bool _saving = false;
  String? _resultMessage;
  bool? _resultSuccess;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _url = TextEditingController(text: s?.url ?? '');
    _username = TextEditingController(text: s?.username ?? '');
    _password = TextEditingController(text: '');
    _allowSelfSigned = s?.allowSelfSigned ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_url.text.trim().isEmpty) return '地址不能为空';
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme) {
      return '地址格式不正确（需要 http:// 或 https://）';
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
    final result = await WebDavService.instance.testConnection(
      url: _url.text.trim(),
      username: _username.text.trim(),
      password: _password.text.isEmpty && _isEdit
          ? (widget.existing?.password ?? '')
          : _password.text,
      allowSelfSigned: _allowSelfSigned,
    );
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
      await widget.onSave(
        name: _name.text.trim(),
        url: _url.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        allowSelfSigned: _allowSelfSigned,
      );
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
        icon: _isEdit ? Icons.edit_outlined : Icons.cloud_outlined,
        title: _isEdit ? '编辑 WebDAV' : '添加 WebDAV',
        subtitle: 'WebDAV',
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
                    ServerTextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: serverFieldDecoration(
                        context,
                        label: '地址',
                        hint: 'http://192.168.1.100:8080/dav',
                        icon: Icons.lan_outlined,
                      ),
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
                      label: _isEdit
                          ? '密码（留空保持不变）'
                          : '密码',
                      hint: '••••••••',
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(top: 4),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      activeColor: theme.colorScheme.primary,
                      title: Text(
                        '允许自签名证书',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        '信任无 CA 证书的 HTTPS 服务器（NAS、Nextcloud 等）',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _allowSelfSigned,
                      onChanged: (v) =>
                          setState(() => _allowSelfSigned = v),
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
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/webdav/controllers/webdav_controller.dart';
import 'package:yuanying/utils/storage_manager.dart';

class WebDavSettingPage extends StatefulWidget {
  const WebDavSettingPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<WebDavSettingPage> createState() => _WebDavSettingPageState();
}

class _WebDavSettingPageState extends State<WebDavSettingPage> {
  late final WebDavController _controller;
  final _uriCtr = TextEditingController(text: SettingPref.webdavUri);
  final _usernameCtr = TextEditingController(text: SettingPref.webdavUsername);
  final _passwordCtr = TextEditingController(text: SettingPref.webdavPassword);
  final _directoryCtr = TextEditingController(text: SettingPref.webdavDirectory);
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(WebDavController());
  }

  @override
  void dispose() {
    _uriCtr.dispose();
    _usernameCtr.dispose();
    _passwordCtr.dispose();
    _directoryCtr.dispose();
    super.dispose();
  }

  void _saveConfig() {
    StorageManager.setSetting('webdav_uri', _uriCtr.text);
    StorageManager.setSetting('webdav_username', _usernameCtr.text);
    StorageManager.setSetting('webdav_password', _passwordCtr.text);
    StorageManager.setSetting('webdav_directory', _directoryCtr.text);
    SmartDialog.showToast('配置已保存');
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: showAppBar
          ? AppBar(
              title: const Text('WebDAV 设置'),
              centerTitle: false,
              elevation: 0,
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurface,
            )
          : null,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          ListView(
            padding: EdgeInsets.only(
              top: 20,
              left: 20 + (showAppBar ? padding.left : 0),
              right: 20 + (showAppBar ? padding.right : 0),
              bottom: padding.bottom + 100,
            ),
            children: [
              // 地址
              TextField(
                controller: _uriCtr,
                decoration: const InputDecoration(
                  labelText: '地址',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              // 用户名
              TextField(
                controller: _usernameCtr,
                decoration: const InputDecoration(
                  labelText: '用户',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              // 密码（带可见性切换）
              TextField(
                controller: _passwordCtr,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureText = !_obscureText),
                    icon: _obscureText
                        ? const Icon(Icons.visibility)
                        : const Icon(Icons.visibility_off),
                  ),
                ),
                obscureText: _obscureText,
              ),
              const SizedBox(height: 20),
              // 路径
              TextField(
                controller: _directoryCtr,
                decoration: const InputDecoration(
                  labelText: '路径',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              // 操作按钮（三列：测试连接、备份、恢复）
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: Style.mdRadius,
                        ),
                      ),
                      onPressed: () async {
                        final success = await _controller.init();
                        if (success) {
                          SmartDialog.showToast('连接成功');
                        } else {
                          SmartDialog.showToast('连接失败，请检查配置');
                        }
                      },
                      child: const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: Style.mdRadius,
                        ),
                      ),
                      onPressed: () => _controller.backup(),
                      child: const Text('备份'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: Style.mdRadius,
                        ),
                      ),
                      onPressed: () => _controller.restore(),
                      child: const Text('恢复'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 右下角保存按钮（FAB）
          Positioned(
            right: 16 + (showAppBar ? padding.right : 0),
            bottom: 16 + padding.bottom,
            child: FloatingActionButton(
              onPressed: _saveConfig,
              child: const Icon(Icons.save),
            ),
          ),
        ],
      ),
    );
  }
}
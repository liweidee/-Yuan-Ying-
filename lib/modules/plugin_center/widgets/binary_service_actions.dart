// lib/modules/plugin_center/widgets/binary_service_actions.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/modules/plugin_center/controllers/plugin_center_controller.dart';
import 'package:yuanying/modules/plugin_center/models/installed_plugin.dart';
import 'package:yuanying/modules/plugin_center/models/service_config.dart';
import 'package:yuanying/modules/plugin_center/services/install_manager.dart';
import 'package:yuanying/modules/plugin_center/services/service_manager.dart';
import 'package:yuanying/modules/webview/views/webview_page.dart';

// ============================================================
// 路径常量
// ============================================================

/// Android 标准外部存储挂载点（所有 App 通用，不是 DsPlayer 专用）
const String _externalRoot = '/storage/emulated/0';

/// 本应用的公开数据根目录
///
/// ⚠️ 不能照抄 DsPlayer 的 `/storage/emulated/0/dsplayer`，
/// 那是 DsPlayer 的专属目录名。源影用自己的 `yuanying`。
///
/// 想改目录名？只改这一行即可。
const String _publicDataDir = '$_externalRoot/yuanying';

// ============================================================
// Go 二进制插件（runtime=binary）的服务预设
// ============================================================

class BinaryServicePreset {
  final String pluginId;
  final String displayName;
  final int defaultPort;
  final String healthType;
  final String healthPath;
  final List<String> defaultArgs;
  final Map<String, String> defaultEnv;

  /// 需要在 _publicDataDir 下预创建的子目录（如 `server/frpc`）
  /// 为 null 表示不需要访问 sdcard
  final String? publicSubDir;

  /// 若设置，此 env 键的值在保存时自动同步为端口值
  /// （用于 PORT 这类必须与监听端口一致的变量）
  final String? syncPortEnvKey;

  const BinaryServicePreset({
    required this.pluginId,
    required this.displayName,
    required this.defaultPort,
    this.healthType = 'http',
    this.healthPath = '/',
    required this.defaultArgs,
    this.defaultEnv = const {},
    this.publicSubDir,
    this.syncPortEnvKey,
  });

  String get serviceId => 'svc-binary-$pluginId';
  String get defaultCwd => '__filesDir__/services/$serviceId';
}

/// ============================================================
/// 插件预设参数
///
/// 对照基准：市场包内的 plugin.json（逐字）
/// 改动范围：仅 dsplayer → yuanying，其他参数原样保留
/// ============================================================
const Map<String, BinaryServicePreset> _presets = {
  // ------------------------------------------------------------
  // 1. frp v0.71.0
  // ------------------------------------------------------------
  'frp': BinaryServicePreset(
    pluginId: 'frp',
    displayName: 'frp 内网穿透客户端',
    defaultPort: 7400,
    healthType: 'http',
    healthPath: '/healthz',
    publicSubDir: 'server/frpc',
    defaultArgs: [
      '-c',
      '$_publicDataDir/server/frpc/frpc.toml',
    ],
    defaultEnv: const {},
  ),

  // ------------------------------------------------------------
  // 2. OpenList v1.3.0
  // ------------------------------------------------------------
  'OpenList': BinaryServicePreset(
    pluginId: 'OpenList',
    displayName: 'OpenList 网盘服务',
    defaultPort: 5244,
    healthType: 'http',
    healthPath: '/',
    publicSubDir: 'server/openlist',
    defaultArgs: [
      'server',
      '--data',
      '$_publicDataDir/server/openlist',
    ],
    defaultEnv: {
      'CNB2API_DNS': '223.5.5.5,119.29.29.29,114.114.114.114,1.1.1.1,8.8.8.8',
      // ⚠️ 带 +1，与 go-music-dl 的 netdns=go 不同
      'GODEBUG': 'netdns=go+1',
      'OPENLIST_ADMIN_PASSWORD': '123456',
      'OPENLIST_SCHEME_ADDRESS': '0.0.0.0',
      'OPENLIST_SCHEME_HTTP_PORT': '5244',
    },
  ),

  // ------------------------------------------------------------
  // 3. filebrowser v2.63.25
  // ------------------------------------------------------------
  'filebrowser': BinaryServicePreset(
    pluginId: 'filebrowser',
    displayName: 'FileBrowser 文件管理器',
    defaultPort: 8080,
    healthType: 'http',
    healthPath: '/health',
    publicSubDir: 'server/filebrowser',
    defaultArgs: [
      '-a', '0.0.0.0',
      '-p', '8080',
      '-r', '$_externalRoot',       // /storage/emulated/0（真实 sdcard 根，通用）
      '-d', 'filebrowser.db',        // 相对路径，落 cwd（私有目录，避 FUSE mmap）
      '--username', 'admin',
      // ⚠️ bcrypt 哈希含 $，必须 raw string
      '--password',
      r'$2a$10$4n8wTVqWLxykd4b5ic5R0OjTv0vT3VzUDpKY58n1JXkY7mQrIpelq',
    ],
    defaultEnv: {
      'HOME': '$_publicDataDir/server/filebrowser',
    },
  ),

  // ------------------------------------------------------------
  // 4. go-music-dl v1.1.1
  // ------------------------------------------------------------
  'go-music-dl': BinaryServicePreset(
    pluginId: 'go-music-dl',
    displayName: 'Go Music DL 音乐下载',
    defaultPort: 37777,
    healthType: 'http',
    healthPath: '/music/healthz',
    // 无 sdcard 依赖
    defaultArgs: [
      'web',
      '--port', '37777',
      '--no-browser',
    ],
    defaultEnv: {
      // ⚠️ 注意不带 +1，与 OpenList 不同
      'GODEBUG': 'netdns=go',
      'CNB2API_DNS': '223.5.5.5,119.29.29.29,114.114.114.114,1.1.1.1,8.8.8.8',
    },
  ),

  // ------------------------------------------------------------
  // 5. clash-meta v1.19.32
  // ------------------------------------------------------------
  // plugin.json 原值：
  //   params: "-f /storage/emulated/0/dsplayer/server/clash-meta/config.yaml
  //            -ext-ctl 127.0.0.1:9090 -ext-ui ui"
  //   env: {}
  //   binaries.android: "clash-meta-android"
  //   healthCheck: { type: http, path: /version, port: 9090 }
  //
  // 路径分离设计（保持市场包原样）：
  //   - config.yaml → sdcard（用户可编辑，改完面板重载生效）
  //   - ui/ 面板    → cwd（应用私有目录，补丁自动解压）
  //   - 9090        → 控制端口，也是健康检查端口
  'clash-meta': BinaryServicePreset(
    pluginId: 'clash-meta',
    displayName: 'Clash Meta 代理内核',
    defaultPort: 9090, // 控制面板端口（兼作健康检查）
    healthType: 'http',
    healthPath: '/version',
    publicSubDir: 'server/clash-meta',
    defaultArgs: [
      '-f',
      '$_publicDataDir/server/clash-meta/config.yaml',
      '-ext-ctl', '127.0.0.1:9090',
      '-ext-ui', 'ui', // 相对 cwd（应用私有目录）
    ],
    defaultEnv: const {},
  ),

  // ------------------------------------------------------------
  // 6. captcha-bypass v1.0.0
  // ------------------------------------------------------------
  // plugin.json 原值：
  //   params: "server"
  //   env: { "PORT": "7788" }
  //   binaries.android: "captcha-bypass-android-arm64"
  //   healthCheck: { type: http, path: /, port: 7788 }
  //
  // ⚠️ PORT 环境变量必须与端口一致（服务监听 7788）。
  //    用户改端口时 syncPortEnvKey 会自动同步 PORT，避免踩坑。
  'captcha-bypass': BinaryServicePreset(
    pluginId: 'captcha-bypass',
    displayName: '验证码识别服务',
    defaultPort: 7788,
    healthType: 'http',
    healthPath: '/',
    // 无 sdcard 依赖（纯服务，无配置文件）
    defaultArgs: ['server'],
    defaultEnv: {
      'PORT': '7788',
    },
    syncPortEnvKey: 'PORT',
  ),
};

BinaryServicePreset? getBinaryPreset(String pluginId) => _presets[pluginId];

bool isBinaryPlugin(String pluginId) => _presets.containsKey(pluginId);

// ============================================================
// 读最新 extras
// ============================================================

int _getPort(InstalledPlugin plugin, BinaryServicePreset preset) {
  final latest = InstallManager.instance.findInstalled(plugin.id);
  final extras = latest?.extras ?? plugin.extras;
  final v = extras['binaryServicePort'];
  if (v is int && v > 0 && v <= 65535) return v;
  return preset.defaultPort;
}

List<String> _getArgs(InstalledPlugin plugin, BinaryServicePreset preset) {
  final latest = InstallManager.instance.findInstalled(plugin.id);
  final extras = latest?.extras ?? plugin.extras;
  final v = extras['binaryServiceArgs'];
  if (v is List) return v.map((e) => e.toString()).toList();
  return List<String>.from(preset.defaultArgs);
}

Map<String, String> _getEnv(
    InstalledPlugin plugin, BinaryServicePreset preset) {
  final latest = InstallManager.instance.findInstalled(plugin.id);
  final extras = latest?.extras ?? plugin.extras;
  final v = extras['binaryServiceEnv'];
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val.toString()));
  }
  return Map<String, String>.from(preset.defaultEnv);
}

// ============================================================
// sdcard 目录预创建
// ============================================================

Future<bool> _ensurePublicDir(String subPath) async {
  try {
    final dir = Directory(p.join(_publicDataDir, subPath));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return true;
  } catch (_) {
    return false;
  }
}

// ============================================================
// 打开 Web
// ============================================================

Future<void> openBinaryServiceWeb(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final preset = getBinaryPreset(plugin.id);
  if (preset == null) return;
  final port = _getPort(plugin, preset);

  bool alive = false;
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(milliseconds: 800),
    );
    await socket.close();
    alive = true;
  } catch (_) {
    alive = false;
  }

  if (!alive) {
    SmartDialog.showToast('服务未运行或端口 $port 不可达');
    return;
  }

  final url = 'http://localhost:$port/';
  Get.to(() => WebviewPage(url: url, title: preset.displayName));
}

// ============================================================
// 编辑配置
// ============================================================

Future<void> showBinaryServiceConfigDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final preset = getBinaryPreset(plugin.id);
  if (preset == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _BinaryServiceConfigDialog(plugin: plugin, preset: preset),
  );
}

class _BinaryServiceConfigDialog extends StatefulWidget {
  final InstalledPlugin plugin;
  final BinaryServicePreset preset;

  const _BinaryServiceConfigDialog({
    required this.plugin,
    required this.preset,
  });

  @override
  State<_BinaryServiceConfigDialog> createState() =>
      _BinaryServiceConfigDialogState();
}

class _BinaryServiceConfigDialogState
    extends State<_BinaryServiceConfigDialog> {
  late final TextEditingController _portCtrl;
  late final TextEditingController _argsCtrl;
  late final Map<String, TextEditingController> _envCtrls;
  late final Set<String> _presetKeys;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    final port = _getPort(widget.plugin, preset);
    final args = _getArgs(widget.plugin, preset);
    final env = _getEnv(widget.plugin, preset);

    _portCtrl = TextEditingController(text: '$port');
    _argsCtrl = TextEditingController(text: args.join(' '));
    _presetKeys = preset.defaultEnv.keys.toSet();
    _envCtrls = {
      for (final e in env.entries)
        e.key: TextEditingController(text: e.value),
    };

    // 端口变化时联动 syncPortEnvKey（如 captcha-bypass 的 PORT）
    _portCtrl.addListener(_syncPortEnv);
  }

  @override
  void dispose() {
    _portCtrl.removeListener(_syncPortEnv);
    _portCtrl.dispose();
    _argsCtrl.dispose();
    for (final c in _envCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 端口变化时，把 syncPortEnvKey 对应的 env 值同步为新端口
  void _syncPortEnv() {
    final key = widget.preset.syncPortEnvKey;
    if (key == null) return;
    final ctrl = _envCtrls[key];
    if (ctrl == null) return;
    final newPort = _portCtrl.text.trim();
    if (ctrl.text != newPort) {
      ctrl.text = newPort;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final preset = widget.preset;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
      backgroundColor: colorScheme.surface,
      title: Text(
        '${preset.displayName} · 配置',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '启动参数用空格分隔；环境变量按 KEY=VALUE 注入子进程。\n'
                '占位符 __filesDir__ 会替换为应用私有目录（不是真实 sdcard）。',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.outline,
                  height: 1.5,
                ),
              ),
              if (preset.publicSubDir != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.folder_special,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '此插件需要访问 sdcard 目录：\n'
                          '$_publicDataDir/${preset.publicSubDir}\n'
                          '若启动失败提示目录不可写，请先在插件中心顶部点'
                          '「文件访问」授权，再启动服务。',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (preset.syncPortEnvKey != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer.withValues(alpha: 0.25),
                    borderRadius: Style.mdRadius,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.sync,
                          size: 14, color: colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '环境变量 ${preset.syncPortEnvKey} 会随端口自动同步。',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // 端口
              TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // 启动参数
              TextField(
                controller: _argsCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '启动参数',
                  hintText: '空格分隔',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 环境变量
              Row(
                children: [
                  Text(
                    '环境变量',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addEnv,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加'),
                  ),
                ],
              ),
              if (_envCtrls.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '无环境变量',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                )
              else
                ..._envCtrls.entries.map((e) => _buildEnvRow(e.key, e.value)),
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
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildEnvRow(String key, TextEditingController valueCtrl) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPreset = _presetKeys.contains(key);
    final isSynced = widget.preset.syncPortEnvKey == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: isPreset ? 0.5 : 0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      key,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isPreset
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSynced)
                    Icon(Icons.sync,
                        size: 12, color: colorScheme.tertiary),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('='),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: valueCtrl,
              readOnly: isSynced, // 联动端口，禁止手改
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                helperText: isSynced ? '随端口自动同步' : null,
                helperStyle: TextStyle(fontSize: 10, color: colorScheme.tertiary),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: isSynced
                ? '随端口自动同步，不可删除'
                : isPreset
                    ? '预设变量（可清空值但不可删除）'
                    : '删除',
            icon: Icon(
              Icons.close,
              size: 18,
              color: colorScheme.error
                  .withValues(alpha: (isPreset || isSynced) ? 0.3 : 1),
            ),
            onPressed: (isPreset || isSynced) ? null : () => _removeEnv(key),
          ),
        ],
      ),
    );
  }

  Future<void> _addEnv() async {
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
          title: const Text('添加环境变量'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '变量名',
              hintText: '大写字母/数字/下划线',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
    if (key == null || key.trim().isEmpty) return;
    final name = key.trim();
    if (_envCtrls.containsKey(name)) {
      SmartDialog.showToast('变量已存在：$name');
      return;
    }
    setState(() {
      _envCtrls[name] = TextEditingController();
    });
  }

  void _removeEnv(String key) {
    setState(() {
      _envCtrls.remove(key)?.dispose();
    });
  }

  Future<void> _save() async {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      SmartDialog.showToast('端口无效（1-65535）');
      return;
    }
    final argsText = _argsCtrl.text.trim();
    final args = argsText.isEmpty
        ? <String>[]
        : argsText.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (args.isEmpty) {
      SmartDialog.showToast('启动参数不能为空');
      return;
    }

    // 兜底同步 syncPortEnvKey（理论上 listener 已处理，防极端时序）
    if (widget.preset.syncPortEnvKey != null) {
      final key = widget.preset.syncPortEnvKey!;
      _envCtrls[key]?.text = '$port';
    }

    final env = <String, String>{};
    for (final e in _envCtrls.entries) {
      final k = e.key.trim();
      final v = e.value.text.trim();
      if (k.isNotEmpty) env[k] = v;
    }

    final latest = InstallManager.instance.findInstalled(widget.plugin.id);
    final extras = Map<String, dynamic>.from(
      latest?.extras ?? widget.plugin.extras,
    );
    extras['binaryServicePort'] = port;
    extras['binaryServiceArgs'] = args;
    extras['binaryServiceEnv'] = env;
    await InstallManager.instance.updateExtras(widget.plugin.id, extras);

    if (Get.isRegistered<PluginCenterController>()) {
      Get.find<PluginCenterController>().reloadInstalled();
    }

    final status = ServiceManager.instance.getStatus(widget.preset.serviceId);
    final wasRunning =
        status == ServiceStatus.running || status == ServiceStatus.starting;

    if (mounted) Navigator.pop(context);
    SmartDialog.showToast(
      wasRunning ? '已保存，需停止并重新启动服务才能生效' : '已保存',
    );
  }
}

// ============================================================
// 启动 / 停止服务
// ============================================================

Future<void> startBinaryService(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final preset = getBinaryPreset(plugin.id);
  if (preset == null) return;

  final controller = Get.find<PluginCenterController>();
  final port = _getPort(plugin, preset);
  final args = _getArgs(plugin, preset);
  final env = _getEnv(plugin, preset);

  // 1. 预创建 sdcard 子目录
  if (preset.publicSubDir != null) {
    final ok = await _ensurePublicDir(preset.publicSubDir!);
    if (!ok) {
      SmartDialog.showToast(
        '无法创建目录：$_publicDataDir/${preset.publicSubDir}\n'
        '请先在插件中心顶部授权「文件访问」后重试',
      );
      return;
    }
  }

  // 2. 探测可执行文件
  final exePath = _findBinary(plugin);
  if (exePath == null) {
    SmartDialog.showToast('找不到可执行文件，请检查插件包完整性或从市场重装');
    return;
  }

  final config = ServiceConfig(
    id: preset.serviceId,
    name: preset.displayName,
    port: port,
    runtime: plugin.id,
    args: args,
    cwd: preset.defaultCwd,
    autostart: false,
    keepForeground: true,
    env: env,
    executable: exePath,
    healthType: preset.healthType,
    healthPath: preset.healthPath,
  );

  await ServiceManager.instance.addOrUpdate(config);
  controller.reloadServices();

  final currentStatus = ServiceManager.instance.getStatus(preset.serviceId);
  if (currentStatus == ServiceStatus.running ||
      currentStatus == ServiceStatus.starting) {
    await ServiceManager.instance.stop(preset.serviceId);
  }

  try {
    await ServiceManager.instance.start(preset.serviceId);
  } catch (_) {
    // 错误由 ServiceManager.onEvent 统一处理
  }
}

Future<void> stopBinaryService(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final preset = getBinaryPreset(plugin.id);
  if (preset == null) return;
  await ServiceManager.instance.stop(preset.serviceId);
}

// ============================================================
// 内部：解析可执行文件
// ============================================================
//
// 已知二进制名（来自实际 plugin.json）：
//   frp             → frpc-android
//   filebrowser     → filebrowser-android
//   OpenList        → openlist-arm64
//   go-music-dl     → music-dl-android
//   clash-meta      → clash-meta-android
//   captcha-bypass  → captcha-bypass-android-arm64
//
String? _findBinary(InstalledPlugin plugin) {
  // 1. plugin.json.binaries.{android|win32}
  final pluginJson = File(p.join(plugin.installPath, 'plugin.json'));
  if (pluginJson.existsSync()) {
    try {
      final j = jsonDecode(pluginJson.readAsStringSync()) as Map;
      final binaries = j['binaries'];
      final key = Platform.isWindows ? 'win32' : 'android';
      if (binaries is Map && binaries[key] is String) {
        final rel = binaries[key] as String;
        final candidates = [
          p.join(plugin.installPath, rel),
          p.join(plugin.installPath, 'bin', rel),
          p.join(plugin.installPath, p.basename(rel)),
          p.join(plugin.installPath, 'bin', p.basename(rel)),
        ];
        for (final c in candidates) {
          if (File(c).existsSync()) return c;
        }
      }
    } catch (_) {}
  }

  // 2. 兜底：按实际 plugin.json 中声明的二进制名
  final knownNames = <String, String>{
    'frp': 'frpc-android',
    'filebrowser': 'filebrowser-android',
    'OpenList': 'openlist-arm64',
    'go-music-dl': 'music-dl-android',
    'clash-meta': 'clash-meta-android',
    'captcha-bypass': 'captcha-bypass-android-arm64',
  }[plugin.id];

  final names = <String>[
    if (knownNames != null) knownNames,
    plugin.id,
    '${plugin.id}-android',
  ];
  for (final n in names) {
    for (final sub in ['', 'bin/']) {
      final f = File(p.join(plugin.installPath, '$sub$n'));
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}
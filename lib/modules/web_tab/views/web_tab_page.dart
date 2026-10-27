// lib/modules/web_tab/views/web_tab_page.dart
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/main.dart' show webViewEnvironment;
import 'package:yuanying/modules/manual_source/controllers/manual_source_controller.dart';
import 'package:yuanying/modules/manual_source/models/manual_source_item.dart';
import 'package:yuanying/modules/web_tab/models/ds_env.dart';
import 'package:yuanying/modules/web_tab/services/ds_bridge_service.dart';
import 'package:yuanying/modules/web_tab/services/ds_handlers.dart';
import 'package:yuanying/modules/web_tab/widgets/web_source_switch_dialog.dart';
import 'package:yuanying/modules/web_tab/widgets/web_tab_topbar.dart';
import 'package:yuanying/utils/storage_manager.dart';

class WebTabPage extends StatefulWidget {
  const WebTabPage({super.key});
  @override
  State<WebTabPage> createState() => _WebTabPageState();
}

class _WebTabPageState extends State<WebTabPage>
    with AutomaticKeepAliveClientMixin {
  static const String _currentIdKey = 'web_tab_current_id';

  String? _currentId;
  InAppWebViewController? _web;
  DsHandlers? _handlers;

  final _pageTitle = ''.obs;
  final _pageUrl = ''.obs;
  final _progress = 0.0.obs;
  final _isLoading = false.obs;

  ManualSourceController get _mgr => Get.find<ManualSourceController>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentId = StorageManager.getSetting<String>(_currentIdKey);
  }

  void _setCurrent(String id) {
    if (_currentId == id) return;
    setState(() => _currentId = id);
    StorageManager.setSetting(_currentIdKey, id);
  }

  // ===== 通用底部弹窗外壳（带拖拽条 + 标题 + 圆角） =====
  Widget _buildSheet({
    required BuildContext context,
    String? title,
    Widget? trailing,
    required Widget child,
    double maxSize = 0.85,
  }) {
    final cs = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * maxSize;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
              ),
              Divider(height: 0.5, thickness: 0.5,
                  color: cs.outline.withValues(alpha: 0.15)),
            ],
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

  // ===== 更多菜单 =====
  void _showMenu() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) => _buildSheet(
        context: ctx,
        title: '更多',
        maxSize: 0.6,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            _menuItem(
              icon: Icons.phone_android,
              title: '切换 UA',
              color: cs,
              onTap: () {
                Navigator.pop(ctx);
                _showUaPicker();
              },
            ),
            _menuItem(
              icon: Icons.cleaning_services_outlined,
              title: '清除缓存',
              color: cs,
              onTap: () async {
                Navigator.pop(ctx);
                await InAppWebViewController.clearAllCache();
                await _web?.clearHistory();
                SmartDialog.showToast('已清理');
              },
            ),
            _menuItem(
              icon: Icons.code,
              title: '查看页面源码',
              color: cs,
              onTap: () {
                Navigator.pop(ctx);
                _showSourceDialog();
              },
            ),
            _menuItem(
              icon: Icons.folder_open_outlined,
              title: '去手动源管理',
              color: cs,
              onTap: () {
                Navigator.pop(ctx);
                Get.toNamed(AppPages.manualSource);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    required ColorScheme color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, size: 22, color: color.primary),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    );
  }

  // ===== UA 切换 =====
  void _showUaPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) => _buildSheet(
        context: ctx,
        title: '选择 UA',
        maxSize: 0.55,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final entry in {
              '默认（按平台）': BrowserUa.platform,
              'PC Chrome': BrowserUa.pc,
              '移动 Chrome': BrowserUa.mob,
              'iOS Safari': BrowserUa.mobSafari,
            }.entries)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                title: Text(entry.key,
                    style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _web?.setSettings(
                    settings:
                        InAppWebViewSettings(userAgent: entry.value),
                  );
                  await _web?.reload();
                },
              ),
          ],
        ),
      ),
    );
  }

  // ===== 查看源码（service_log_sheet 风格：外壳主题色 + 内容区黑色） =====
  Future<void> _showSourceDialog() async {
    final c = _web;
    if (c == null) return;
    final html = await c.evaluateJavascript(
      source: 'document.documentElement.outerHTML',
    );
    final code = html?.toString() ?? '';
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) => _buildSourceCodeSheet(ctx, code),
    );
  }

  Widget _buildSourceCodeSheet(BuildContext ctx, String code) {
    final cs = Theme.of(ctx).colorScheme;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽条
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '页面源码',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                    tooltip: '复制全部',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      SmartDialog.showToast('已复制 ${code.length} 字符');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容区：黑色容器（参考 service_log_sheet）
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: code.isEmpty
                      ? Center(
                          child: Text(
                            '页面内容为空',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        )
                      : Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              code,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFFD4D4D4),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const Divider(height: 1),
            // 底部操作栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      SmartDialog.showToast('已复制');
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSwitchDialog(List<ManualSourceItem> items) {
    if (items.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => WebSourceSwitchDialog(
        currentId: _currentId ?? '',
        items: items,
        onSelect: (src) => _setCurrent(src.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (Platform.isLinux) return _buildLinuxFallback();

    return Obx(() {
      final all = _mgr.all;
      final loading = _mgr.loading.value;

      if (loading && all.isEmpty) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      final htmls = all
          .where((e) => e.type == ManualSourceType.html && !e.disabled)
          .toList();

      if (htmls.isEmpty) return _buildEmptyState();

      var cur =
          htmls.firstWhereOrNull((e) => e.id == _currentId) ?? htmls.first;
      if (cur.id != _currentId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setCurrent(cur.id);
        });
      }

      return _buildContent(cur, htmls);
    });
  }

  Widget _buildContent(ManualSourceItem cur, List<ManualSourceItem> all) {
    final full = _handlers?.isFullscreen.value == true;
    final fileUri = Uri.file(cur.path).toString();

    final body = InAppWebView(
      key: ValueKey('webview_${cur.id}'),
      webViewEnvironment: webViewEnvironment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: true,
        cacheEnabled: false,
        useShouldOverrideUrlLoading: false,
        useOnLoadResource: false,
        useShouldInterceptAjaxRequest: false,
        useShouldInterceptFetchRequest: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        supportMultipleWindows: false,
        userAgent: BrowserUa.platform,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        disableContextMenu: true,
      ),
      onWebViewCreated: (c) async {
        _web = c;
        _handlers = DsHandlers(c);

        c.addJavaScriptHandler(
          handlerName: DsBridgeService.handlerName,
          callback: (args) => _handlers!.dispatchRaw(args),
        );

        final env = DsEnv.fromContext(context);
        await c.addUserScript(
          userScript: UserScript(
            source: DsBridgeService.buildSkeleton(env),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        );

        await c.loadUrl(
          urlRequest: URLRequest(url: WebUri(fileUri)),
        );
      },
      onLoadStart: (c, url) {
        _isLoading.value = true;
        _progress.value = 0;
        _pageUrl.value = url?.toString() ?? '';
      },
      onLoadStop: (c, url) async {
        _isLoading.value = false;
        _progress.value = 1;
        _pageUrl.value = url?.toString() ?? '';
        final t = await c.getTitle() ?? '';
        _pageTitle.value = t;
      },
      onProgressChanged: (c, p) => _progress.value = p / 100,
      onTitleChanged: (c, t) => _pageTitle.value = t ?? '',
      onUpdateVisitedHistory: (c, url, _) {
        _pageUrl.value = url?.toString() ?? '';
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          if (!full)
            WebTabTopBar(
              sourceName: cur.name,
              pageTitle: _pageTitle.value,
              pageUrl: _pageUrl.value,
              isLoading: _isLoading.value,
              progress: _progress.value,
              onSwitchSource: () => _showSwitchDialog(all),
              onBack: () async {
                if (await _web?.canGoBack() == true) {
                  await _web?.goBack();
                }
              },
              onForward: () async {
                if (await _web?.canGoForward() == true) {
                  await _web?.goForward();
                }
              },
              onReload: () => _web?.reload(),
              onFullscreen: () => _handlers?.isFullscreen.value = true,
              onMenu: _showMenu,
            ),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: full
          ? FloatingActionButton(
              mini: true,
              backgroundColor: Colors.black54,
              onPressed: () => _handlers?.isFullscreen.value = false,
              child: const Icon(Icons.fullscreen_exit, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.language, size: 72, color: cs.outline),
                const SizedBox(height: 16),
                Text(
                  '还没有 Web 源',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  '请前往「设置 → 手动源管理」上传 .html 源文件',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.outline),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Get.toNamed(AppPages.manualSource),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('去手动源管理上传'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLinuxFallback() {
    return Scaffold(
      appBar: AppBar(title: const Text('Web')),
      body: const Center(
        child: Text('Linux 不支持内嵌 WebView，请使用其他平台'),
      ),
    );
  }
}
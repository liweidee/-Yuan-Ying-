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
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/modules/manual_source/controllers/manual_source_controller.dart';
import 'package:yuanying/modules/manual_source/models/manual_source_item.dart';
import 'package:yuanying/modules/manual_source/models/web_source_meta.dart';
import 'package:yuanying/modules/web_tab/models/ds_env.dart';
import 'package:yuanying/modules/web_tab/services/ds_bridge_service.dart';
import 'package:yuanying/modules/web_tab/services/ds_handlers.dart';
import 'package:yuanying/modules/web_tab/widgets/web_source_switch_dialog.dart';
import 'package:yuanying/modules/web_tab/widgets/web_tab_topbar.dart';
import 'package:yuanying/t4/services/source_manager.dart';
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

  final _isFullscreen = false.obs;

  /// 网盘链接列表
  final _cloudLinks = <Map<String, dynamic>>[].obs;

  /// 嗅探到的媒体资源列表（多视频，去重）
  final _sniffedVideos = <Map<String, String>>[].obs;

  ({String loadUrl, String? injectJs})? _entry;
  String? _entryForId;
  String? _pendingInjectJs;
  bool _injected = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _mgr.refresh();
      } catch (_) {}
      if (!mounted) return;
      _scheduleEntryResolve();
    });
  }

  void _setCurrent(String id) {
    if (_currentId == id) return;

    final oldWeb = _web;
    _web = null;
    _handlers = null;
    if (oldWeb != null) {
      try {
        oldWeb.dispose();
      } catch (_) {}
    }

    _entry = null;
    _entryForId = null;
    _pendingInjectJs = null;
    _injected = false;
    _isFullscreen.value = false;
    _cloudLinks.clear();
    _sniffedVideos.clear();

    _pageTitle.value = '';
    _pageUrl.value = '';
    _progress.value = 0;
    _isLoading.value = false;

    setState(() {
      _currentId = id;
    });
    StorageManager.setSetting(_currentIdKey, id);

    _scheduleEntryResolve();
  }

  void _scheduleEntryResolve() {
    final id = _currentId;
    if (id == null || id.isEmpty) return;

    final cur = _mgr.all.firstWhereOrNull((e) => e.id == id);
    if (cur == null) return;

    _resolveEntry(cur).then((r) {
      if (!mounted) return;
      if (_currentId != id) return;

      _pendingInjectJs = r?.injectJs;
      _injected = false;

      setState(() {
        _entry = r;
        _entryForId = id;
      });
    }).catchError((e) {
      debugPrint('[WebTab] resolve entry failed: $e');
      if (!mounted) return;
      if (_currentId != id) return;
      setState(() {
        _entry = null;
        _entryForId = id;
      });
    });
  }

  Future<({String loadUrl, String? injectJs})?> _resolveEntry(
    ManualSourceItem cur) async {
    try {
      final path = cur.path.toLowerCase();

      if (path.endsWith('.web.json')) {
        final content = await File(cur.path).readAsString();
        final meta = WebSourceMeta.parse(content);
        if (meta == null || meta.homePage.isEmpty) return null;

        String? js;
        final jsPath = cur.path.replaceAll('.web.json', '.js');
        final jsFile = File(jsPath);
        if (await jsFile.exists()) {
          js = await jsFile.readAsString();
        }
        return (loadUrl: meta.homePage, injectJs: js);
      }

      if (path.endsWith('.html')) {
        String? js;
        final jsPath = cur.path.replaceAll('.html', '.js');
        final jsFile = File(jsPath);
        if (await jsFile.exists()) {
          js = await jsFile.readAsString();
        }
        return (loadUrl: Uri.file(cur.path).toString(), injectJs: js);
      }

      return null;
    } catch (e) {
      debugPrint('[WebTab] resolve entry failed: $e');
      return null;
    }
  }

  // ================== 媒体/网盘检测 ==================
  bool _isMediaUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:') || lower.startsWith('data:')) return false;
    // 排除干扰
    if (lower.contains('.js') ||
        lower.contains('.css') ||
        lower.contains('.png') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.gif') ||
        lower.contains('.webp') ||
        lower.contains('.svg') ||
        lower.contains('.woff') ||
        lower.contains('.ttf')) {
      return false;
    }
    return RegExp(
      r'\.(m3u8|mp4|flv|mpd|mkv|mov|m4v|ts|webm)(\?|#|$)',
      caseSensitive: false,
    ).hasMatch(lower) ||
        lower.contains('videoplayback') ||
        lower.contains('/video/') ||
        lower.contains('/stream/');
  }

  void _onSniffedVideo(String url, String title) {
    if (url.isEmpty) return;
    if (!_isMediaUrl(url)) return;

    // 去重
    for (final v in _sniffedVideos) {
      if (v['url'] == url) return;
    }

    _sniffedVideos.insert(0, {
      'url': url,
      'title': title.isNotEmpty ? title : _pageTitle.value,
    });
  }

  void _onCloudLinks(List<Map<String, dynamic>> links) {
    if (links.isEmpty) return;
    final existing =
        _cloudLinks.map((e) => e['url']?.toString() ?? '').toSet();
    for (final l in links) {
      final u = l['url']?.toString() ?? '';
      if (u.isEmpty) continue;
      if (existing.contains(u)) continue;
      existing.add(u);
      _cloudLinks.add(l);
    }
  }

  // ================== 播放行为 ==================
  void _playSniffedVideo(Map<String, String> video) {
    final url = video['url'] ?? '';
    if (url.isEmpty) return;
    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': url,
        'directTitle': video['title']?.isNotEmpty == true
            ? video['title']!
            : '嗅探视频',
        'sourceName': 'Web 嗅探',
        'isDirectPushMode': true,
      },
    );
  }

  /// 参考 web_sniffer_page 的弹窗样式
  void _showSniffedVideosSheet() {
    if (_sniffedVideos.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '嗅探到 ${_sniffedVideos.length} 个资源',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      onPressed: () {
                        _sniffedVideos.clear();
                        Navigator.pop(ctx);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Obx(() => ListView.separated(
                      shrinkWrap: true,
                      itemCount: _sniffedVideos.length,
                      separatorBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(height: 1),
                      ),
                      itemBuilder: (_, i) {
                        final v = _sniffedVideos[i];
                        return _buildMediaTile(ctx, v);
                      },
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个媒体 Tile（参考 web_sniffer_page 样式）
  Widget _buildMediaTile(BuildContext ctx, Map<String, String> video) {
    final theme = Theme.of(ctx);
    final url = video['url'] ?? '';
    final title = video['title'] ?? '';
    final type = _detectMediaType(url);

    return ListTile(
      leading: Icon(
        Icons.play_circle_fill,
        color: theme.colorScheme.primary,
        size: 36,
      ),
      title: Text(
        title.isNotEmpty ? title : '视频资源',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          type,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      onTap: () {
        Navigator.pop(ctx);
        _playSniffedVideo(video);
      },
    );
  }

  String _detectMediaType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'm3u8';
    if (lower.contains('.mp4')) return 'mp4';
    if (lower.contains('.flv')) return 'flv';
    if (lower.contains('.mpd')) return 'mpd';
    if (lower.contains('.m4v')) return 'm4v';
    if (lower.contains('.mkv')) return 'mkv';
    if (lower.contains('.mov')) return 'mov';
    if (lower.contains('.ts')) return 'ts';
    if (lower.contains('.webm')) return 'webm';
    return 'video';
  }

  void _pushCloudLink(Map<String, dynamic> link) {
    final url = link['url']?.toString() ?? '';
    if (url.isEmpty) return;

    final sm = Get.find<SourceManager>();
    final pushAgent = sm.pushAgentSite;
    if (pushAgent == null) {
      SmartDialog.showToast('请先在源配置中添加 push_agent 源');
      return;
    }

    final api = pushAgent['api']?.toString() ?? '';
    final pwd = Uri.tryParse(api)?.queryParameters['pwd'] ?? 'tinydust';

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'vodId': url,
        'pwd': pwd,
        'site': pushAgent,
      },
    );
  }

  void _showCloudLinksSheet() {
    if (_cloudLinks.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSheet(
        context: ctx,
        title: '网盘链接 (${_cloudLinks.length})',
        maxSize: 0.7,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _cloudLinks.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final link = _cloudLinks[i];
            final url = link['url']?.toString() ?? '';
            final label = link['label']?.toString() ?? '';
            final code = link['extractCode']?.toString() ?? '';
            final type = _detectCloudType(url);
            return ListTile(
              leading: Icon(
                Icons.cloud_outlined,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                type.isNotEmpty ? type : '网盘链接',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  if (code.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '提取码：$code',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              trailing: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _pushCloudLink(link);
                },
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('推送'),
              ),
            );
          },
        ),
      ),
    );
  }

  String _detectCloudType(String url) {
    if (url.contains('pan.quark.cn')) return '夸克网盘';
    if (url.contains('pan.baidu.com')) return '百度网盘';
    if (url.contains('pan.xunlei.com')) return '迅雷云盘';
    if (url.contains('aliyundrive.com') || url.contains('alipan.com')) {
      return '阿里云盘';
    }
    if (url.contains('115.com')) return '115 网盘';
    if (url.contains('123pan.com')) return '123 云盘';
    if (url.contains('cloud.189.cn')) return '天翼云盘';
    if (url.contains('drive.uc.cn')) return 'UC 网盘';
    return '';
  }

  // ================== 弹窗 ==================
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
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: cs.outline.withValues(alpha: 0.15)),
            ],
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

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
                title: Text(entry.key, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _web?.setSettings(
                    settings: InAppWebViewSettings(userAgent: entry.value),
                  );
                  await _web?.reload();
                },
              ),
          ],
        ),
      ),
    );
  }

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
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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

  // ================== 底栏避让 ==================
  double _getBottomAvoidHeight(BuildContext context) {
    if (Get.isRegistered<MainController>()) {
      final mc = Get.find<MainController>();
      if (!mc.hideBottomBar.value && mc.bottomBarHeight.value > 0) {
        return mc.bottomBarHeight.value;
      }
    }
    return MediaQuery.viewPaddingOf(context).bottom;
  }

  // ================== build ==================
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

      final sources = all
          .where((e) =>
              e.type == ManualSourceType.html && !e.disabled)
          .toList();

      if (sources.isEmpty) return _buildEmptyState();

      var cur =
          sources.firstWhereOrNull((e) => e.id == _currentId) ?? sources.first;
      if (cur.id != _currentId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setCurrent(cur.id);
        });
      }

      return _buildContent(cur, sources);
    });
  }

  Widget _buildContent(ManualSourceItem cur, List<ManualSourceItem> all) {
    final entry = _entry;
    final entryReady = entry != null && _entryForId == cur.id;

    return KeyedSubtree(
      key: ValueKey('tab_${cur.id}'),
      child: Obx(() {
        final full = _isFullscreen.value;
        final hasCloud = _cloudLinks.isNotEmpty;
        final hasSniffed = _sniffedVideos.isNotEmpty;
        final showFab = full || hasCloud || hasSniffed;

        final bottomAvoid = _getBottomAvoidHeight(context);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Stack(
            children: [
              Column(
                children: [
                  if (!full) _buildNormalBar(cur, all),
                  Expanded(
                    child: entryReady
                        ? _buildWebView(cur, entry)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
              if (showFab)
                Positioned(
                  right: 16,
                  bottom: 16 + bottomAvoid,
                  child: _buildFabGroup(
                    full: full,
                    hasCloud: hasCloud,
                    hasSniffed: hasSniffed,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildNormalBar(ManualSourceItem cur, List<ManualSourceItem> all) {
    return WebTabTopBar(
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
      onFullscreen: () => _isFullscreen.value = true,
      onMenu: _showMenu,
    );
  }

  Widget _buildFabGroup({
    required bool full,
    required bool hasCloud,
    required bool hasSniffed,
  }) {
    final buttons = <Widget>[];

    if (hasSniffed) {
      buttons.add(_fabButton(
        icon: Icons.play_circle_fill_rounded,
        tooltip: '嗅探到 ${_sniffedVideos.length} 个视频',
        onTap: _showSniffedVideosSheet,
      ));
    }
    if (hasCloud) {
      buttons.add(_fabButton(
        icon: Icons.cloud_outlined,
        tooltip: '网盘链接（${_cloudLinks.length}）',
        onTap: _showCloudLinksSheet,
      ));
    }
    if (full) {
      buttons.add(_fabButton(
        icon: Icons.fullscreen_exit_rounded,
        tooltip: '退出全屏',
        onTap: () => _isFullscreen.value = false,
      ));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          buttons[i],
        ],
      ],
    );
  }

  Widget _fabButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // ================== WebView（核心：补齐所有嗅探回调） ==================
  Widget _buildWebView(
    ManualSourceItem cur,
    ({String loadUrl, String? injectJs}) entry,
  ) {
    return SizedBox.expand(
      child: InAppWebView(
        key: ValueKey('webview_${cur.id}'),
        webViewEnvironment: webViewEnvironment,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          cacheEnabled: true,
          useShouldOverrideUrlLoading: true,
          useOnLoadResource: true,
          useShouldInterceptAjaxRequest: true,
          useShouldInterceptFetchRequest: true,
          interceptOnlyAsyncAjaxRequests: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          supportMultipleWindows: false,
          userAgent: BrowserUa.platform,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          disableContextMenu: true,
        ),
        onWebViewCreated: (c) async {
          _web = c;
          _handlers = DsHandlers(c, isFullscreen: _isFullscreen);

          _handlers!.setSniffedVideoCallback(_onSniffedVideo);
          _handlers!.setCloudLinksCallback(_onCloudLinks);

          c.addJavaScriptHandler(
            handlerName: DsBridgeService.handlerName,
            callback: (args) => _handlers!.dispatchRaw(args),
          );

          final env = DsEnv.fromContext(context);
          await c.addUserScript(
            userScript: UserScript(
              source: DsBridgeService.buildSkeleton(env),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
          );

          await c.loadUrl(
            urlRequest: URLRequest(url: WebUri(entry.loadUrl)),
          );
        },
        onLoadStart: (c, url) {
          _isLoading.value = true;
          _progress.value = 0;
          _pageUrl.value = url?.toString() ?? '';
          _injected = false;
        },
        onLoadStop: (c, url) async {
          _isLoading.value = false;
          _progress.value = 1;
          _pageUrl.value = url?.toString() ?? '';
          final t = await c.getTitle() ?? '';
          _pageTitle.value = t;

          if (!_injected &&
              _pendingInjectJs != null &&
              _pendingInjectJs!.isNotEmpty) {
            try {
              await c.evaluateJavascript(source: _pendingInjectJs!);
              _injected = true;
            } catch (e) {
              debugPrint('[WebTab] 注入 js 失败: $e');
            }
          }
        },
        onProgressChanged: (c, p) => _progress.value = p / 100,
        onTitleChanged: (c, t) => _pageTitle.value = t ?? '',
        onUpdateVisitedHistory: (c, url, _) {
          _pageUrl.value = url?.toString() ?? '';
        },

        // 核心：四层回调，任何一层能触发就捕获
        // 层 1：网络资源加载（Android/iOS 完整，Windows 可能不工作）
        onLoadResource: (c, resource) {
          final url = resource.url?.toString() ?? '';
          if (_isMediaUrl(url)) _onSniffedVideo(url, _pageTitle.value);
        },
        // 层 2：XHR 拦截（跨平台，Windows 有效）
        shouldInterceptAjaxRequest: (c, request) async {
          final url = request.url?.toString() ?? '';
          if (_isMediaUrl(url)) _onSniffedVideo(url, _pageTitle.value);
          return request;
        },
        // 层 3：Fetch 拦截（跨平台，Windows 有效）
        shouldInterceptFetchRequest: (c, request) async {
          final url = request.url?.toString() ?? '';
          if (_isMediaUrl(url)) _onSniffedVideo(url, _pageTitle.value);
          return request;
        },
        // 层 4：URL 跳转拦截（兜底）
        shouldOverrideUrlLoading: (c, action) async {
          final url = action.request.url?.toString() ?? '';
          if (_isMediaUrl(url)) _onSniffedVideo(url, _pageTitle.value);
          return NavigationActionPolicy.ALLOW;
        },
        // 层 5：HTTP 错误拦截（有些 CDN 返回 404 但也可能是媒体）
        onReceivedHttpError: (c, request, response) {
          final url = request.url.toString();
          if (_isMediaUrl(url)) _onSniffedVideo(url, _pageTitle.value);
        },
      ),
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
                  '请前往「设置 → 手动源管理」上传 .html 或 .web.json 源文件',
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
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/main.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/utils/page_utils.dart';
import 'package:yuanying/utils/utils.dart';

/// 嗅探到的媒体资源
class SniffedMedia {
  final String url;
  final String name;
  final String type;
  final int detectedAt;

  SniffedMedia({
    required this.url,
    required this.name,
    required this.type,
    required this.detectedAt,
  });
}

class WebSnifferPage extends StatefulWidget {
  const WebSnifferPage({super.key});

  @override
  State<WebSnifferPage> createState() => _WebSnifferPageState();
}

class _WebSnifferPageState extends State<WebSnifferPage> {
  final _urlController = TextEditingController();
  final _medias = <SniffedMedia>[].obs;
  final _seenUrls = <String>{};
  final _webTitle = ''.obs;
  final _progress = 1.0.obs;
  final _isLoading = false.obs;

  InAppWebViewController? _webViewController;
  String _currentUrl = '';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ==================== 媒体判定 ====================

  /// 判断是否为媒体 URL
  bool _isMediaUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:')) return false;
    if (lower.startsWith('data:')) return false;
    // 排除干扰项
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
    // 白名单
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.flv') ||
        lower.contains('.mpd') ||
        lower.contains('.m4v') ||
        lower.contains('.mkv') ||
        lower.contains('.mov') ||
        lower.contains('videoplayback') ||
        lower.contains('/video/') ||
        lower.contains('/stream/');
  }

  /// 检测资源类型
  String _detectType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'm3u8';
    if (lower.contains('.mp4')) return 'mp4';
    if (lower.contains('.flv')) return 'flv';
    if (lower.contains('.mpd')) return 'mpd';
    if (lower.contains('.m4v')) return 'm4v';
    if (lower.contains('.mkv')) return 'mkv';
    if (lower.contains('.mov')) return 'mov';
    return 'video';
  }

  /// 从 URL 提取文件名
  String _extractName(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isEmpty) return '视频资源';
      var last = segments.last;
      // 去掉扩展名
      final dotIdx = last.lastIndexOf('.');
      if (dotIdx > 0) last = last.substring(0, dotIdx);
      // 去掉过长 hash
      if (last.length > 50) last = last.substring(0, 50);
      return last.isEmpty ? '视频资源' : last;
    } catch (_) {
      return '视频资源';
    }
  }

  /// 添加媒体（去重）
  void _addMedia(String url) {
    if (url.isEmpty || _seenUrls.contains(url)) return;
    if (!_isMediaUrl(url)) return;
    _seenUrls.add(url);
    _medias.insert(
      0,
      SniffedMedia(
        url: url,
        name: _extractName(url),
        type: _detectType(url),
        detectedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // ==================== 重置逻辑 ====================

  /// 重置嗅探结果（清空媒体列表、去重集合、网页标题）
  void _resetSniffed() {
    _medias.clear();
    _seenUrls.clear();
    _webTitle.value = '';
  }

  // ==================== 页面操作 ====================

  void _onVisit() {
    var url = _urlController.text.trim();
    if (url.isEmpty) {
      SmartDialog.showToast('请输入网页地址');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
      _urlController.text = url;
    }
    try {
      Uri.parse(url);
    } catch (_) {
      SmartDialog.showToast('无效的网址');
      return;
    }

    _currentUrl = url;
    _resetSniffed();
    _isLoading.value = true;
    _progress.value = 0;

    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      SmartDialog.showToast('剪贴板为空');
      return;
    }
    _urlController.text = text;
  }

  void _clearInput() {
    _urlController.clear();
  }

  Future<void> _refresh() async {
    if (_currentUrl.isEmpty) {
      SmartDialog.showToast('请先访问网页');
      return;
    }
    _resetSniffed();
    await _webViewController?.reload();
  }

  // ==================== 更多菜单 ====================

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'refresh':
        await _refresh();
        break;
      case 'copy':
        final url = await _webViewController?.getUrl();
        if (url != null) {
          Utils.copyText(url.toString());
        }
        break;
      case 'openInBrowser':
        final url = await _webViewController?.getUrl();
        if (url != null) {
          PageUtils.launchURL(url.toString());
        }
        break;
      case 'clearCache':
        try {
          await InAppWebViewController.clearAllCache();
          await _webViewController?.clearHistory();
          SmartDialog.showToast('已清理');
        } catch (e) {
          SmartDialog.showToast(e.toString());
        }
        break;
    }
  }

  // ==================== 媒体弹窗 ====================

  void _showMediaSheet() {
    if (_medias.isEmpty) return;

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
                      '嗅探到 ${_medias.length} 个资源',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
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
                      itemCount: _medias.length,
                      separatorBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(height: 1),
                      ),
                      itemBuilder: (ctx, i) {
                        final media = _medias[i];
                        return _buildMediaTile(ctx, media);
                      },
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaTile(BuildContext ctx, SniffedMedia media) {
    final theme = Theme.of(ctx);
    return ListTile(
      leading: Icon(
        Icons.play_circle_fill,
        color: theme.colorScheme.primary,
        size: 36,
      ),
      title: Text(
        media.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        media.url,
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
          media.type,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      onTap: () {
        Navigator.pop(ctx);
        _playMedia(media);
      },
    );
  }

  /// 播放单个媒体资源（单集，不拼接全部）
  void _playMedia(SniffedMedia media) {
    final title = _webTitle.value.isNotEmpty ? _webTitle.value : '网页嗅探';
    final videoDetail = VideoDetail(
      vodId: 'websniff_${DateTime.now().millisecondsSinceEpoch}',
      vodName: title,
      vodPic: '',
      vodContent: _currentUrl,
      vodYear: '',
      vodActor: '',
      vodDirector: '',
      vodRemarks: media.type.toUpperCase(),
      typeName: '网页嗅探',
      playSources: [
        PlaySource(
          name: '网页嗅探',
          episodes: [
            Episode(name: media.name, url: media.url),
          ],
        ),
      ],
    );

    Get.toNamed(
      AppPages.detail,
      arguments: {
        'isPush': true,
        'directUrl': media.url,
        'directTitle': media.name,
        'videoDetail': videoDetail,
        'sourceName': '网页嗅探',
        'vodContent': _currentUrl,
        'isDirectPushMode': true,
      },
    );
  }

  // ==================== JS 注入 ====================

  /// 页面加载完成后注入 JS Hook
  Future<void> _injectHookScript(InAppWebViewController controller) async {
    const script = r"""
      (function() {
        if (window.__webSnifferInjected) return;
        window.__webSnifferInjected = true;

        function report(url) {
          if (!url || typeof url !== 'string') return;
          if (url.startsWith('blob:') || url.startsWith('data:')) return;
          try {
            window.flutter_inappwebview.callHandler('onMediaFound', url);
          } catch (e) {}
        }

        // Hook fetch
        try {
          const originalFetch = window.fetch;
          window.fetch = function(input, init) {
            try {
              const url = (typeof input === 'string') ? input : (input && input.url);
              if (url) report(url);
            } catch (e) {}
            return originalFetch.apply(this, arguments).then(function(response) {
              try {
                if (response && response.clone) {
                  response.clone().text().then(function(text) {
                    if (text && (text.indexOf('.m3u8') > -1 || text.indexOf('.mp4') > -1)) {
                      const match = text.match(/(https?:\/\/[^"'\s]+\.(m3u8|mp4|flv)[^"'\s]*)/);
                      if (match && match[0]) report(match[0]);
                    }
                  }).catch(function(){});
                }
              } catch (e) {}
              return response;
            });
          };
        } catch (e) {}

        // Hook XHR
        try {
          const originalOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url) {
            try {
              if (url) {
                let absUrl = url;
                if (!url.startsWith('http') && !url.startsWith('blob:')) {
                  try { absUrl = new URL(url, location.href).href; } catch (e) {}
                }
                report(absUrl);
              }
            } catch (e) {}
            return originalOpen.apply(this, arguments);
          };
        } catch (e) {}

        // 定时扫描 video 标签
        setInterval(function() {
          try {
            document.querySelectorAll('video, source').forEach(function(el) {
              if (el.src && !el.src.startsWith('blob:')) {
                report(el.src);
              }
              if (el.currentSrc && !el.currentSrc.startsWith('blob:')) {
                report(el.currentSrc);
              }
            });
          } catch (e) {}
        }, 1000);
      })();
    """;
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {}
  }

  // ==================== build ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        title: Obx(() => Text(
              _webTitle.value.isNotEmpty ? _webTitle.value : '网页嗅探器',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text('刷新')),
              const PopupMenuItem(value: 'copy', child: Text('复制链接')),
              const PopupMenuItem(value: 'openInBrowser', child: Text('浏览器打开')),
              const PopupMenuItem(value: 'clearCache', child: Text('清除缓存')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ===== URL 输入区 =====
            _buildUrlBar(theme),

            // ===== Tip 提示区 =====
            _buildTip(theme),

            // ===== WebView 区域 =====
            Expanded(
              child: Stack(
                children: [
                  // WebView
                  _buildWebView(),

                  // 加载进度
                  Obx(() => _progress.value < 1
                      ? Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: _progress.value,
                            minHeight: 2,
                          ),
                        )
                      : const SizedBox.shrink()),

                  // 空状态提示
                  Obx(() {
                    if (!_isLoading.value && _currentUrl.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.travel_explore,
                              size: 72,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '输入网址，开启嗅探之旅',
                              style: TextStyle(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),

                  // 右下角播放按钮（仅嗅探到资源后显示）
                  Obx(() {
                    if (_medias.isEmpty) return const SizedBox.shrink();
                    return Positioned(
                      right: 16,
                      bottom: 24,
                      child: FloatingActionButton(
                        heroTag: 'web_sniffer_fab',
                        onPressed: _showMediaSheet,
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.play_arrow, size: 28),
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '${_medias.length}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== URL 输入栏 ====================

  Widget _buildUrlBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _onVisit(),
              decoration: InputDecoration(
                hintText: '输入网页地址',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 粘贴
                    IconButton(
                      icon: const Icon(Icons.content_paste, size: 18),
                      tooltip: '粘贴',
                      onPressed: _paste,
                    ),
                    // 清空（有内容时才显示）
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _urlController,
                      builder: (context, value, _) {
                        if (value.text.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: '清空',
                          onPressed: _clearInput,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _onVisit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('访问'),
          ),
        ],
      ),
    );
  }

  // ==================== Tip 提示 ====================

  Widget _buildTip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 12,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '输入网页地址后点击"访问"，嗅探到视频后点击右下角播放按钮',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.outline,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== WebView ====================

  Widget _buildWebView() {
    return InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        cacheEnabled: true,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
        useShouldInterceptAjaxRequest: true,
        useShouldInterceptFetchRequest: true,
        interceptOnlyAsyncAjaxRequests: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        transparentBackground: false,
        userAgent: BrowserUa.platform,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        // 注册 JS 回调
        controller.addJavaScriptHandler(
          handlerName: 'onMediaFound',
          callback: (args) {
            if (args.isNotEmpty && args[0] is String) {
              _addMedia(args[0] as String);
            }
            return null;
          },
        );
      },
      onLoadStart: (controller, url) {
        // 页面导航（点击链接、回退、前进、跳转）→ 重置嗅探结果
        final newUrl = url?.toString() ?? '';
        if (newUrl.isNotEmpty && newUrl != _currentUrl) {
          _medias.clear();
          _seenUrls.clear();
        }
        if (newUrl.isNotEmpty) _currentUrl = newUrl;
        _isLoading.value = true;
        _progress.value = 0;
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        // SPA 场景（React/Vue 等 pushState 路由切换）也需重置
        final newUrl = url?.toString() ?? '';
        if (newUrl.isNotEmpty && newUrl != _currentUrl) {
          _medias.clear();
          _seenUrls.clear();
        }
        if (newUrl.isNotEmpty) _currentUrl = newUrl;
      },
      onLoadStop: (controller, url) async {
        _isLoading.value = false;
        _progress.value = 1;
        await _injectHookScript(controller);
      },
      onProgressChanged: (controller, progress) {
        _progress.value = progress / 100;
      },
      onTitleChanged: (controller, title) {
        _webTitle.value = title ?? '';
      },
      onLoadError: (controller, url, code, message) {
        _isLoading.value = false;
      },
      onLoadResource: (controller, resource) {
        final resUrl = resource.url?.toString() ?? '';
        if (resUrl.isNotEmpty) {
          _addMedia(resUrl);
        }
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url?.toString() ?? '';
        if (_isMediaUrl(url)) {
          _addMedia(url);
        }
        return NavigationActionPolicy.ALLOW;
      },
      shouldInterceptAjaxRequest: (controller, request) async {
        final url = request.url?.toString() ?? '';
        if (_isMediaUrl(url)) {
          _addMedia(url);
        }
        return request;
      },
      shouldInterceptFetchRequest: (controller, request) async {
        final url = request.url?.toString() ?? '';
        if (_isMediaUrl(url)) {
          _addMedia(url);
        }
        return request;
      },
      onReceivedHttpError: (controller, request, response) {
        final url = request.url.toString();
        if (_isMediaUrl(url)) {
          _addMedia(url);
        }
      },
    );
  }
}
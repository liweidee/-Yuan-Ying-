import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, SingleActivator;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yuanying/main.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/utils/cache_manager.dart';
import 'package:yuanying/utils/page_utils.dart';
import 'package:yuanying/utils/utils.dart';

/// 通用 WebView 页面
class WebviewPage extends StatefulWidget {
  const WebviewPage({
    super.key,
    this.url,
    this.title,
    this.userAgent,
    this.inApp = false,
    this.off = false,
  });

  final String? url;
  final String? title;
  final String? userAgent;
  final bool inApp;   // 是否在应用内处理链接
  final bool off;     // 是否关闭当前页面

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> with WindowListener {
  late final String _url = widget.url ?? Get.parameters['url'] ?? '';
  late final String userAgent;
  final RxString title = ''.obs;
  final RxDouble progress = 1.0.obs;
  final RxBool isFullscreen = false.obs;

  InAppWebViewController? _webViewController;

  /// 进入全屏前窗口是否处于最大化，用于退出时恢复
  bool _wasMaximizedBefore = false;

  static final _prefixRegex = RegExp(
    r'^(?!(https?://))\S+://',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    userAgent =
        widget.userAgent ??
        switch (Get.parameters['uaType']) {
          'pc' => BrowserUa.pc,
          'mob' => BrowserUa.mob,
          _ => BrowserUa.platform,
        };
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      // dispose 不能 await，尽力清理，避免窗口状态残留到下次启动
      if (isFullscreen.value) {
        _exitFullscreen();
      }
    }
    _webViewController = null;
    super.dispose();
  }

  // WindowListener：同步系统触发的全屏状态
  @override
  void onWindowEnterFullScreen() {
    isFullscreen.value = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    isFullscreen.value = false;
  }

  /// 进入 Windows 真全屏（隐藏标题栏/边框/阴影，覆盖任务栏）
  Future<void> _enterFullscreen() async {
    if (!Platform.isWindows) return;

    // 1. 记录进入前是否最大化
    _wasMaximizedBefore = await windowManager.isMaximized();

    // 2. 若已最大化，先恢复，让窗口状态"干净"
    if (_wasMaximizedBefore) {
      await windowManager.restore();
      await Future.delayed(const Duration(milliseconds: 240));
    }

    // 3. 进入全屏
    await windowManager.setFullScreen(true);

    // 4. 清除 Windows 残留窗口外壳（必须在 setFullScreen 之后）
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    isFullscreen.value = true;
  }

  /// 退出全屏并恢复原样
  Future<void> _exitFullscreen() async {
    if (!Platform.isWindows) return;

    // 1. 退出全屏
    await windowManager.setFullScreen(false);

    // 2. 恢复窗口外壳：setTitleBarStyle(normal) 会同时恢复标题栏与边框
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(true);

    // 3. 恢复进入前的最大化状态
    if (_wasMaximizedBefore) {
      await windowManager.maximize();
    }

    isFullscreen.value = false;
  }

  void _toggleFullscreen() {
    if (isFullscreen.value) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return Scaffold(
        appBar: AppBar(),
        resizeToAvoidBottomInset: false,
        body: Center(
          child: TextButton(
            onPressed: () => PageUtils.launchURL(_url),
            child: const Text('unsupported'),
          ),
        ),
      );
    }

    return Obx(_buildMain);
  }

  Widget _buildMain() {
    final isWindows = Platform.isWindows;

    final scaffold = Scaffold(
      appBar: isFullscreen.value
          ? null
          : AppBar(
              title: Obx(
                () => Text(
                  title.value.isNotEmpty ? title.value : (widget.title ?? _url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: Obx(
                  () => progress.value < 1
                      ? LinearProgressIndicator(value: progress.value)
                      : const SizedBox.shrink(),
                ),
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (item) async {
                    switch (item) {
                      case 'refresh':
                        _webViewController?.reload();
                        break;
                      case 'copy':
                        WebUri? uri = await _webViewController?.getUrl();
                        if (uri != null) {
                          Utils.copyText(uri.toString());
                        }
                        break;
                      case 'openInBrowser':
                        WebUri? uri = await _webViewController?.getUrl();
                        if (uri != null) {
                          PageUtils.launchURL(uri.toString());
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
                      case 'fullscreen':
                        _enterFullscreen();
                        break;
                      case 'goBack':
                        if (await _webViewController?.canGoBack() == true) {
                          _webViewController?.goBack();
                        } else {
                          Get.back();
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                    const PopupMenuItem(value: 'copy', child: Text('复制链接')),
                    const PopupMenuItem(
                      value: 'openInBrowser',
                      child: Text('浏览器打开'),
                    ),
                    const PopupMenuItem(
                      value: 'clearCache',
                      child: Text('清除缓存'),
                    ),
                    if (isWindows)
                      const PopupMenuItem(
                        value: 'fullscreen',
                        child: Text('全屏'),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'goBack',
                      child: Text(
                        '返回',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: SafeArea(
        top: !isFullscreen.value,
        child: Stack(
          children: [
            InAppWebView(
              webViewEnvironment: webViewEnvironment,
              initialSettings: InAppWebViewSettings(
                clearCache: true,
                javaScriptEnabled: true,
                forceDark: ForceDark.AUTO,
                useHybridComposition: false,
                algorithmicDarkeningAllowed: true,
                useShouldOverrideUrlLoading: true,
                userAgent: userAgent,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri.uri(Uri.tryParse(_url) ?? Uri()),
              ),
              onWebViewCreated: (InAppWebViewController controller) {
                _webViewController = controller;
              },
              onProgressChanged: (controller, progress) {
                this.progress.value = progress / 100;
              },
              onTitleChanged: (controller, title) {
                this.title.value = title ?? '';
              },
              onCloseWindow: (controller) => Get.back(),
              onDownloadStartRequest: Platform.isAndroid
                  ? (controller, request) {
                      showDialog(
                        context: context,
                        builder: (context) {
                          String suggestedFilename = request.suggestedFilename
                              .toString();
                          String fileSize = CacheManager.formatSize(
                            request.contentLength.toDouble(),
                          );
                          try {
                            suggestedFilename = Uri.decodeComponent(
                              suggestedFilename,
                            );
                          } catch (e) {
                            if (kDebugMode) debugPrint(e.toString());
                          }
                          return AlertDialog(
                            title: Text(
                              '下载文件: $suggestedFilename ?',
                              style: const TextStyle(fontSize: 18),
                            ),
                            content: SelectableText(request.url.toString()),
                            actions: [
                              TextButton(
                                onPressed: Get.back,
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Get.back();
                                  PageUtils.launchURL(request.url.toString());
                                },
                                child: Text('确定 ($fileSize)'),
                              ),
                            ],
                          );
                        },
                      );
                      progress.value = 1;
                    }
                  : null,
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                if (widget.inApp) {
                  return NavigationActionPolicy.ALLOW;
                }
                final url = navigationAction.request.url?.toString() ?? '';

                // 检查是否为自定义 Scheme（非 http/https）
                if (_prefixRegex.hasMatch(url)) {
                  if (context.mounted) {
                    SnackBar snackBar = SnackBar(
                      content: const Text('当前网页将要打开外部链接，是否打开'),
                      showCloseIcon: true,
                      persist: false,
                      action: SnackBarAction(
                        label: '打开',
                        onPressed: () => PageUtils.launchURL(url),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(snackBar);
                  }
                  progress.value = 1;
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
            ),

            // 全屏时 AppBar 隐藏，把进度条移到顶部
            if (isFullscreen.value && isWindows)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Obx(
                  () => progress.value < 1
                      ? LinearProgressIndicator(value: progress.value)
                      : const SizedBox.shrink(),
                ),
              ),

            // 全屏时右下角悬浮退出按钮（兜底，防止用户被困）
            if (isFullscreen.value && isWindows)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.black54,
                  onPressed: _exitFullscreen,
                  child: const Icon(
                    Icons.fullscreen_exit,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!isWindows) {
      return scaffold;
    }

    return CallbackShortcuts(
      bindings: {
        // F11 切换全屏
        const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
        // Esc 仅退出全屏
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (isFullscreen.value) {
            _exitFullscreen();
          }
        },
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }
}
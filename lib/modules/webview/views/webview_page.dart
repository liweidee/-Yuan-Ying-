import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/main.dart';
import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/utils/cache_manager.dart';
import 'package:yuanying/utils/page_utils.dart';
import 'package:yuanying/utils/utils.dart';

/// 通用 WebView 页面（移除 B站 专属逻辑）
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

class _WebviewPageState extends State<WebviewPage> {
  late final String _url = widget.url ?? Get.parameters['url'] ?? '';
  late final String userAgent;
  final RxString title = ''.obs;
  final RxDouble progress = 1.0.obs;

  InAppWebViewController? _webViewController;

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
  }

  @override
  void dispose() {
    _webViewController = null;
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
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
              const PopupMenuItem(value: 'openInBrowser', child: Text('浏览器打开')),
              const PopupMenuItem(value: 'clearCache', child: Text('清除缓存')),
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
        child: InAppWebView(
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
                                color: Theme.of(context).colorScheme.outline,
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
      ),
    );
  }
}
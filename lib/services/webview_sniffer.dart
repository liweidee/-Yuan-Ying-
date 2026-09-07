import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewSniffer {
  static Future<String?> sniff({
    required String url,
    Map<String, String>? headers,
    String? script,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      return null;
    }

    final completer = Completer<String?>();
    Timer? timeoutTimer;
    OverlayEntry? overlayEntry;
    InAppWebViewController? webViewController;
    bool isCompleted = false;

    final defaultHeaders = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Referer': url,
      ...?headers,
    };

    void completeWithResult(String? result) {
      if (isCompleted) return;
      isCompleted = true;
      timeoutTimer?.cancel();
      try {
        overlayEntry?.remove();
        overlayEntry = null;
      } catch (_) {}
      webViewController = null;
      if (!completer.isCompleted) completer.complete(result);
    }

    bool isVideoUrl(String resUrl) {
      final lower = resUrl.toLowerCase();
      // 排除干扰项
      if (lower.contains('.ts') || lower.contains('.m4s') || lower.contains('.js') || lower.contains('.css')) return false;
      // 扩展视频特征
      return lower.contains('.m3u8') || lower.contains('.mp4') || lower.contains('.flv') ||
          lower.contains('.mpd') || lower.contains('.m4v') ||
          lower.contains('videoplayback') || lower.contains('video/') || lower.contains('stream/');
    }

    timeoutTimer = Timer(timeout, () => completeWithResult(null));

    try {
      final context = Get.context;
      if (context == null) {
        timeoutTimer.cancel();
        return null;
      }

      final overlay = Overlay.of(context);
      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: -1000,
          top: -1000,
          width: 1,
          height: 1,
          child: IgnorePointer(
            ignoring: true,
            child: Opacity(
              opacity: 0.0,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(url), headers: defaultHeaders),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  cacheEnabled: true,
                  clearCache: false,
                  transparentBackground: true,
                  useShouldOverrideUrlLoading: true,
                  useOnLoadResource: true,
                  // ===== iOS 优化：开启 Ajax 和 Fetch 拦截 =====
                  useShouldInterceptAjaxRequest: true,
                  useShouldInterceptFetchRequest: true,
                  interceptOnlyAsyncAjaxRequests: false, // 也拦截同步 Ajax
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  // 注册 JS 回调
                  controller.addJavaScriptHandler(
                    handlerName: 'onVideoFound',
                    callback: (args) async {
                      if (isCompleted) return null;
                      if (args.isNotEmpty && args[0] is String) {
                        var url = args[0] as String;
                        // 补全相对路径
                        final currentWebUri = await controller.getUrl();
                        final base = currentWebUri?.toString();
                        if (base != null && !url.startsWith('http://') && !url.startsWith('https://')) {
                          try {
                            url = Uri.parse(base).resolve(url).toString();
                          } catch (_) {}
                        }
                        if (isVideoUrl(url)) {
                          completeWithResult(url);
                        }
                      }
                      return null;
                    },
                  );
                },
                // 拦截页面导航
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  if (isCompleted) return NavigationActionPolicy.CANCEL;
                  final requestUrl = navigationAction.request.url?.toString() ?? '';
                  if (isVideoUrl(requestUrl)) {
                    completeWithResult(requestUrl);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                // ===== iOS：拦截 Ajax 请求 =====
                shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
                  if (isCompleted) return null;
                  final url = ajaxRequest.url?.toString() ?? '';
                  if (isVideoUrl(url)) {
                    completeWithResult(url);
                  }
                  return null; // 不修改请求
                },
                // ===== iOS：拦截 Fetch 请求 =====
                shouldInterceptFetchRequest: (controller, fetchRequest) async {
                  if (isCompleted) return null;
                  final url = fetchRequest.url?.toString() ?? '';
                  if (isVideoUrl(url)) {
                    completeWithResult(url);
                  }
                  return null; // 不修改请求
                },
                // 资源加载监听
                onLoadResource: (controller, resource) {
                  if (isCompleted) return;
                  final resUrl = resource.url?.toString() ?? '';
                  if (isVideoUrl(resUrl)) {
                    completeWithResult(resUrl);
                  }
                },
                onLoadStop: (controller, currentUrl) async {
                  if (isCompleted) return;
                  if (script != null && script.isNotEmpty) {
                    try { await controller.evaluateJavascript(source: script); } catch (_) {}
                  }
                  // 注入兜底 JS（扫描 video 标签 + 响应体检测）
                  try {
                    await controller.evaluateJavascript(source: """
                      (function() {
                        // 防止页面跳转
                        window.location.href = function() {};
                        window.location.replace = function() {};
                        window.location.assign = function() {};

                        // Hook Fetch
                        const originalFetch = window.fetch;
                        window.fetch = function(input, init) {
                          return originalFetch.apply(this, arguments).then(function(response) {
                            if (response && response.clone) {
                              response.clone().text().then(function(text) {
                                if (text && (text.includes('.m3u8') || text.includes('.mp4'))) {
                                  const match = text.match(/(https?:\\/\\/[^"']+\\.(m3u8|mp4)[^"']*)/);
                                  if (match && match[0]) {
                                    window.flutter_inappwebview.callHandler('onVideoFound', match[0]);
                                  }
                                }
                              }).catch(()=>{});
                            }
                            return response;
                          });
                        };

                        // Hook XHR
                        const originalOpen = XMLHttpRequest.prototype.open;
                        XMLHttpRequest.prototype.open = function(method, url) {
                          this.addEventListener("readystatechange", function() {
                            if (this.readyState === 4 && this.status === 200) {
                              if (this.responseText && (this.responseText.includes(".m3u8") || this.responseText.includes(".mp4"))) {
                                const match = this.responseText.match(/(https?:\\/\\/[^"']+\\.(m3u8|mp4)[^"']*)/);
                                if (match && match[0]) {
                                  window.flutter_inappwebview.callHandler('onVideoFound', match[0]);
                                }
                              }
                            }
                          }, false);
                          originalOpen.apply(this, arguments);
                        };

                        // 定时扫描 video 标签
                        setInterval(function() {
                          document.querySelectorAll('video, source').forEach(function(el) {
                            if (el.src && !el.src.startsWith('blob:')) {
                              window.flutter_inappwebview.callHandler('onVideoFound', el.src);
                            }
                          });
                        }, 800);
                      })();
                    """);
                  } catch (_) {}
                },
                onLoadError: (controller, currentUrl, code, message) {
                  if (!isCompleted) completeWithResult(null);
                },
                // 移除 onProgressChanged 自动结束，仅依赖总超时
              ),
            ),
          ),
        ),
      );

      overlay.insert(overlayEntry!);
      return await completer.future;
    } catch (e) {
      timeoutTimer?.cancel();
      overlayEntry?.remove();
      return null;
    }
  }
}
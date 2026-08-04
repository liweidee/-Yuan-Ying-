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
      if (lower.contains('.ts') || lower.contains('.m4s') || lower.contains('.js') || lower.contains('.css')) return false;
      return lower.contains('.m3u8') || lower.contains('.mp4') || lower.contains('.flv') ||
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
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  if (isCompleted) return NavigationActionPolicy.CANCEL;
                  final requestUrl = navigationAction.request.url?.toString() ?? '';
                  if (isVideoUrl(requestUrl)) {
                    completeWithResult(requestUrl);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStop: (controller, currentUrl) async {
                  if (isCompleted) return;
                  if (script != null && script.isNotEmpty) {
                    try { await controller.evaluateJavascript(source: script); } catch (_) {}
                  }
                  try {
                    await controller.evaluateJavascript(source: """
                      (function() {
                        window.location.href = function() {};
                        window.location.replace = function() {};
                        window.location.assign = function() {};

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
                onLoadResource: (controller, resource) {
                  if (isCompleted) return;
                  final resUrl = resource.url?.toString() ?? '';
                  if (isVideoUrl(resUrl)) {
                    completeWithResult(resUrl);
                  }
                },
                onLoadError: (controller, currentUrl, code, message) {
                  if (!isCompleted) completeWithResult(null);
                },
                onProgressChanged: (controller, progress) {
                  if (isCompleted) return;
                  if (progress >= 95) {
                    Future.delayed(const Duration(seconds: 2), () {
                      if (!isCompleted) completeWithResult(null);
                    });
                  }
                },
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
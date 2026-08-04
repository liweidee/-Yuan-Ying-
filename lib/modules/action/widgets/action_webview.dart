// lib/modules/action/widgets/action_webview.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../models/action_config.dart';
import '../models/button_type.dart';

/// 网页视图 Action
/// 严格对应 DrPlayer 的 WebViewAction.vue
///
/// 功能：
/// - 加载 URL
/// - 地址栏（显示/输入）
/// - 导航按钮（后退/前进/刷新）
/// - 加载进度条
/// - 全屏模式
/// - 状态栏显示
/// - 超时自动关闭
class WebViewAction extends StatefulWidget {
  const WebViewAction({
    super.key,
    required this.config,
    required this.visible,
    this.module = '',
    this.extend,
    this.apiUrl,
    this.onSubmit,
    this.onCancel,
    this.onClose,
    this.onAction,
    this.onSpecialAction,
    this.onToast,
    this.onReset,
  });

  final ActionConfig config;
  final bool visible;
  final String module;
  final dynamic extend;
  final String? apiUrl;

  final void Function(dynamic)? onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final void Function(dynamic)? onAction;
  final void Function(String, dynamic)? onSpecialAction;
  final void Function(String, String)? onToast;
  final VoidCallback? onReset;

  @override
  State<WebViewAction> createState() => _WebViewActionState();
}

class _WebViewActionState extends State<WebViewAction> {
  InAppWebViewController? _webViewController;
  String _currentUrl = '';
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  bool _hasError = false;
  String _errorMessage = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isFullscreen = false;

  Timer? _timeoutTimer;
  int _timeLeft = 0;

  bool get _showToolbar => widget.config.showToolbar;
  bool get _showAddressBar => widget.config.showAddressBar;
  bool get _allowFullscreen => widget.config.allowFullscreen;
  bool get _showStatus => widget.config.showStatus;
  bool get _showOkButton => widget.config.button.showOk;
  bool get _showCancelButton => widget.config.button.showCancel;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.config.url ?? '';
    if (widget.visible) {
      _startTimeout();
    }
  }

  @override
  void didUpdateWidget(WebViewAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _startTimeout();
      } else {
        _stopTimeout();
      }
    }
    if (widget.config.url != oldWidget.config.url && widget.config.url != null) {
      setState(() {
        _currentUrl = widget.config.url!;
        _isLoading = true;
        _loadingProgress = 0.0;
        _hasError = false;
        _errorMessage = '';
      });
    }
  }

  @override
  void dispose() {
    _stopTimeout();
    super.dispose();
  }

  void _startTimeout() {
    _stopTimeout();
    if (widget.config.timeout <= 0) return;

    _timeLeft = widget.config.timeout;
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          timer.cancel();
          _handleCancel();
        }
      });
    });
  }

  void _stopTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeLeft = 0;
  }

  // ===== WebView 回调 =====

  void _onWebViewCreated(InAppWebViewController controller) {
    _webViewController = controller;
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
      if (url != null) {
        _currentUrl = url.toString();
      }
    });
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    setState(() {
      _loadingProgress = progress / 100;
    });
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    setState(() {
      _isLoading = false;
      if (url != null) {
        _currentUrl = url.toString();
      }
    });
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = error.description ?? '加载失败';
      // 尝试从请求中获取 URL
      try {
        final url = request.url.toString();
        if (url.isNotEmpty) {
          _currentUrl = url;
        }
      } catch (_) {}
    });
  }

  void _onUpdateVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    if (url != null) {
      setState(() {
        _currentUrl = url.toString();
      });
    }
  }

  // ===== 导航方法 =====

  void _goBack() async {
    if (_webViewController != null && _canGoBack) {
      await _webViewController?.goBack();
    }
  }

  void _goForward() async {
    if (_webViewController != null && _canGoForward) {
      await _webViewController?.goForward();
    }
  }

  void _reload() async {
    if (_webViewController != null) {
      await _webViewController?.reload();
    }
  }

  void _navigate() async {
    if (_currentUrl.trim().isEmpty) return;

    String url = _currentUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    try {
      final webUri = WebUri(url);
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
        _loadingProgress = 0.0;
      });
      await _webViewController?.loadUrl(urlRequest: URLRequest(url: webUri));
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  // ===== 提交和取消 =====

  void _handleOk() {
    final result = <String, dynamic>{
      'url': _currentUrl,
      'action': 'ok',
    };
    widget.onSubmit?.call(result);
    widget.onClose?.call();
  }

  void _handleCancel() {
    widget.onCancel?.call();
    widget.onClose?.call();
  }

  void _handleClose() {
    widget.onClose?.call();
  }

  // ===== 构建方法 =====

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showToolbar) _buildToolbar(context),
        _buildProgress(context),
        _buildWebView(context),
        if (_showStatus) _buildStatus(context),
        if (widget.config.timeout > 0 && _timeLeft > 0) _buildTimeout(context),
        _buildButtons(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: 20),
            onPressed: _canGoBack ? _goBack : null,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward, size: 20),
            onPressed: _canGoForward ? _goForward : null,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20),
            onPressed: _reload,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          if (_showAddressBar)
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: '请输入网址...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  isDense: true,
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _navigate(),
                onChanged: (value) {
                  setState(() {
                    _currentUrl = value;
                  });
                },
                controller: TextEditingController(text: _currentUrl)
                  ..selection = TextSelection.fromPosition(
                    TextPosition(offset: _currentUrl.length),
                  ),
              ),
            ),
          if (_allowFullscreen)
            IconButton(
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 20,
              ),
              onPressed: _toggleFullscreen,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 2,
      color: Colors.transparent,
      child: LinearProgressIndicator(
        value: _isLoading ? _loadingProgress : 1.0,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
      ),
    );
  }

  Widget _buildWebView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_currentUrl.isEmpty) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        child: Text(
          '请输入网址',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.outline,
          ),
        ),
      );
    }

    WebUri? webUri;
    try {
      webUri = WebUri(_currentUrl);
    } catch (_) {
      return Container(
        height: 400,
        alignment: Alignment.center,
        child: Text(
          '无效的网址',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.error,
          ),
        ),
      );
    }

    return Container(
      height: _isFullscreen ? MediaQuery.sizeOf(context).height : 400,
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: webUri),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
            ),
            onWebViewCreated: _onWebViewCreated,
            onLoadStart: _onLoadStart,
            onProgressChanged: _onProgressChanged,
            onLoadStop: _onLoadStop,
            onReceivedError: _onReceivedError,
            onUpdateVisitedHistory: _onUpdateVisitedHistory,
          ),
          if (_isLoading && _loadingProgress < 1.0)
            Container(
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '加载中... ${(_loadingProgress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          if (_hasError)
            Container(
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '页面加载失败',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _reload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    child: const Text('重新加载'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final displayUrl = _currentUrl.length > 50
        ? '${_currentUrl.substring(0, 47)}...'
        : _currentUrl;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 12,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              displayUrl,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isLoading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeout(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            '$_timeLeft秒后自动关闭',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final children = <Widget>[];

    if (_showCancelButton) {
      children.add(
        TextButton(
          onPressed: _handleCancel,
          child: Text(widget.config.cancelText ?? '取消'),
        ),
      );
    }

    if (_showOkButton) {
      children.add(
        ElevatedButton(
          onPressed: _handleOk,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: Text(widget.config.okText ?? '确定'),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: children,
      ),
    );
  }
}
// lib/modules/action/widgets/action_renderer.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../models/action_config.dart';
import '../models/action_result.dart';
import '../models/action_type.dart';
import '../services/action_service.dart';
import '../utils/action_parser.dart';
import 'action_dialog.dart';
import 'action_placeholder.dart';
import 'action_input.dart';
import 'action_multi_input.dart';
import 'action_menu.dart';
import 'action_msgbox.dart';
import 'action_help.dart';
import 'action_webview.dart';
import '../../../t4/services/source_manager.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/modules/webview/views/webview_page.dart';
import 'package:yuanying/core/routes/app_pages.dart';

/// 桌面端动作弹窗统一宽度
const double _desktopActionDialogWidth = 440.0;

class ActionRenderer extends GetxController {
  final ActionService _actionService = Get.find<ActionService>();

  final RxBool isVisible = false.obs;
  final RxBool _dialogVisible = false.obs;
  OverlayEntry? _overlayEntry;

  final Rx<ActionConfig?> currentConfig = Rx<ActionConfig?>(null);
  final RxString currentMessage = ''.obs;
  final RxMap<String, String> inputValues = <String, String>{}.obs;
  final RxBool shouldReset = false.obs;

  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;

  /// 字符串动作并发锁：防止同一动作被重复触发导致重复请求。
  /// 点击被多次捕获时，只有第一次能进入，后续直接被忽略。
  bool _stringActionLock = false;

  Completer<ActionResult?>? _completer;
  String _module = '';
  dynamic _extend;
  String? _apiUrl;

  Future<ActionResult?> showAction(
    dynamic actionData, {
    String module = '',
    dynamic extend,
    String? apiUrl,
  }) async {
    if (isVisible.value) {
      await close();
    }

    _module = module;
    _extend = extend;
    _apiUrl = apiUrl;

    final config = ActionParser.parse(actionData);
    if (config == null) {
      _handleToast('无法解析 Action 配置', 'error');
      return null;
    }

    if (config.actionId.isEmpty) {
      _handleToast('actionId 是必需的', 'error');
      return null;
    }

    if (config.isSpecialAction) {
      return await _handleSpecialAction(config);
    }

    currentConfig.value = config;
    currentMessage.value = config.msg ?? '';
    inputValues.clear();
    shouldReset.value = false;

    isVisible.value = true;
    _completer = Completer<ActionResult?>();
    _showDialog(config);

    return _completer!.future;
  }

  /// 处理"字符串动作"：
  /// vod_id 是纯动作名（如 '夸克扫码' / 'set-cookie'），
  /// 需要先向服务端发 `ac=action&action=xxx`，拿到真正的 ActionConfig 再弹窗。
  ///
  /// 与 showAction 的区别：
  ///   - showAction: vod_id 已是 JSON（含 actionId），直接弹窗
  ///   - showStringAction: vod_id 是纯字符串，先请求服务端
  ///
  /// 注意：本方法不创建 `_completer`，因为 showStringAction 自身不弹窗，
  /// 只是"请求 + 分派"，递归弹窗由 _dispatchActionResult 处理。
  Future<ActionResult?> showStringAction(
    String actionName, {
    String module = '',
    dynamic extend,
    String? apiUrl,
  }) async {
    if (actionName.trim().isEmpty) {
      _handleToast('动作名为空', 'error');
      return null;
    }

    // 并发锁：同一时刻只允许一个字符串动作请求/显示流程。
    // 避免"一次点击触发多次回调"导致的重复请求。
    if (_stringActionLock || isVisible.value) {
      debugPrint(
          '[ActionRenderer] showStringAction 已在进行中，忽略重复触发: $actionName');
      return null;
    }
    _stringActionLock = true;

    try {
      _module = module;
      _extend = extend;
      _apiUrl = apiUrl;

      final actionData = <String, dynamic>{'action': actionName};
      if (extend != null) actionData['extend'] = extend;
      if (apiUrl != null && apiUrl.isNotEmpty) actionData['apiUrl'] = apiUrl;

      final response = await _actionService.executeAction(module, actionData);
      final result = _actionService.parseResponse(response);

      // showStringAction 不负责 UI，不创建 _completer。
      // 递归分支由 _dispatchActionResult 用旧 completer 返回。
      await _dispatchActionResult(result);
      return null;
    } catch (e, stack) {
      debugPrint('showStringAction error: $e');
      debugPrint(stack.toString());
      _handleToast('动作执行失败: $e', 'error');
      return null;
    } finally {
      // 锁在 finally 里释放，保证任何分支都不会卡死
      _stringActionLock = false;
    }
  }

  Future<void> close() async {
    // 立即移除 OverlayEntry（如果有）
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    // 重置状态
    _dialogVisible.value = false;
    isVisible.value = false;
    currentConfig.value = null;
    _completer = null;

    // 等待一帧，确保 Overlay 更新完成
    await Future.delayed(Duration.zero);
  }

  void _showDialog(ActionConfig config) {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    final context = Get.overlayContext;
    if (context == null) {
      _handleToast('无法显示弹窗，请重试', 'error');
      return;
    }

    final screenSize = MediaQuery.sizeOf(context);
    final isMobile = screenSize.width < 600;

    double? dialogWidth; // null 表示让 ActionDialog 自己计算

    if (isMobile) {
      // 移动端：传 null，让 ActionDialog 使用 screenSize.width * 0.92
      dialogWidth = null;
    } else {
      // 桌面端：统一宽度 440px
      double width = _desktopActionDialogWidth;

      // 不超过屏幕宽度的 90%
      if (width > screenSize.width * 0.9) {
        width = screenSize.width * 0.9;
      }

      // 确保最小宽度 360px
      if (width < 360) {
        width = 360;
      }

      dialogWidth = width;
    }

    final overlay = Overlay.of(context);
    _dialogVisible.value = true;

    _overlayEntry = OverlayEntry(
      builder: (context) => Obx(
        () => ActionDialog(
          visible: _dialogVisible.value,
          title: config.title,
          width: dialogWidth, // 桌面端传入统一宽度，移动端传 null
          height: config.height,
          bottom: config.bottom,
          canceledOnTouchOutside: config.canceledOnTouchOutside,
          showClose: true,
          onClose: () {
            _handleCancel();
          },
          onClosed: () {
            if (_overlayEntry != null) {
              _overlayEntry!.remove();
              _overlayEntry = null;
            }
          },
          child: _buildActionWidget(config),
          footer: null,
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Widget _buildActionWidget(ActionConfig config) {
    switch (config.type) {
      case ActionType.input:
      case ActionType.edit:
        return InputAction(
          config: config,
          visible: true,
          module: _module,
          extend: _extend,
          apiUrl: _apiUrl,
          onSubmit: (result) => _handleSubmit(config),
          onCancel: _handleCancel,
          onClose: _handleClose,
          onAction: _handleSubmitWithAction,
          onSpecialAction: _handleSpecialActionFromChild,
          onToast: _handleToast,
          onReset: _handleReset,
        );

      case ActionType.multiInput:
      case ActionType.multiInputX:
        return MultiInputAction(
          config: config,
          visible: true,
          module: _module,
          extend: _extend,
          apiUrl: _apiUrl,
          onSubmit: (result) => _handleSubmit(config),
          onCancel: _handleCancel,
          onClose: _handleClose,
          onAction: _handleAction,
          onSpecialAction: _handleSpecialActionFromChild,
          onToast: _handleToast,
          onReset: _handleReset,
        );

      case ActionType.menu:
      case ActionType.select:
        return MenuAction(
          config: config,
          visible: true,
          module: _module,
          extend: _extend,
          apiUrl: _apiUrl,
          onSubmit: (result) => _handleSubmit(config),
          onCancel: _handleCancel,
          onClose: _handleClose,
          onAction: _handleAction,
          onSpecialAction: _handleSpecialActionFromChild,
          onToast: _handleToast,
          onReset: _handleReset,
        );

      case ActionType.msgbox:
        return MsgBoxAction(
          config: config,
          visible: true,
          module: _module,
          extend: _extend,
          apiUrl: _apiUrl,
          onSubmit: (result) => _handleSubmit(config),
          onCancel: _handleCancel,
          onClose: _handleClose,
          onAction: _handleAction,
          onSpecialAction: _handleSpecialActionFromChild,
          onToast: _handleToast,
          onReset: _handleReset,
        );

      case ActionType.webview:
      case ActionType.browser:
        // 优化：不在弹窗内嵌 WebView，改为全屏 WebviewPage
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (isVisible.value) {
            await close();
          }
          if (Get.context != null) {
            Get.to(() => WebviewPage(
                  url: config.url,
                  title: config.title ?? '网页浏览',
                  inApp: true,
                  userAgent: null,
                ));
          }
        });
        return const SizedBox.shrink();

      case ActionType.help:
        return HelpAction(
          config: config,
          visible: true,
          module: _module,
          extend: _extend,
          apiUrl: _apiUrl,
          onSubmit: (result) => _handleSubmit(config),
          onCancel: _handleCancel,
          onClose: _handleClose,
          onAction: _handleAction,
          onSpecialAction: _handleSpecialActionFromChild,
          onToast: _handleToast,
          onReset: _handleReset,
        );

      default:
        return ActionPlaceholder(
          actionType: config.type?.toJson ?? 'unknown',
          onSubmit: () => _handleSubmit(config),
          onCancel: _handleCancel,
          onClose: _handleClose,
          onAction: _handleAction,
          onSpecialAction: _handleSpecialActionFromChild,
          onToast: _handleToast,
          onReset: _handleReset,
        );
    }
  }

  void _handleSubmitWithAction(dynamic actionData) {
    if (actionData is! Map<String, dynamic>) {
      _handleToast('无效的 Action 数据', 'error');
      return;
    }

    final actionId = actionData['actionId']?.toString();
    dynamic valueData = actionData['value'];

    if (actionId == null || actionId.isEmpty) {
      _handleToast('缺少 actionId', 'error');
      return;
    }

    if (actionData.containsKey('extend')) {
      _extend = actionData['extend'];
    }
    if (actionData.containsKey('apiUrl')) {
      _apiUrl = actionData['apiUrl']?.toString();
    }

    // 核心修复：将 valueData 转换为 JSON 字符串
    String? valueStr;
    if (valueData is Map || valueData is List) {
      try {
        valueStr = jsonEncode(valueData);
      } catch (e) {
        valueStr = valueData.toString();
      }
    } else if (valueData is String) {
      valueStr = valueData;
    } else if (valueData != null) {
      valueStr = valueData.toString();
    }

    final config = ActionConfig(actionId: actionId, value: valueStr);
    _handleSubmit(config);
  }

  void _handleAction(dynamic action) {
    if (action is Map<String, dynamic> && action.containsKey('actionId')) {
      final actionId = action['actionId']?.toString();
      if (actionId != null && actionId.isNotEmpty) {
        _handleSubmitWithAction(action);
        return;
      }
    }
    close();
    Future.delayed(const Duration(milliseconds: 100), () {
      showAction(
        action,
        module: _module,
        extend: _extend,
        apiUrl: _apiUrl,
      ).then((result) {
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete(result);
        }
      });
    });
  }

  Future<void> _handleSubmit(ActionConfig config) async {
    // 【关键】不再使用 isLoading 做并发保护：
    // ActionRenderer 是单例，isLoading 是共享字段。
    // 当嵌套弹窗（如 get_quark_cookie → get_quark_cookie_value）出现时，
    // 第一层的 _handleSubmit 挂在 await _dispatchActionResult 上，
    // 第二层点确定时若依赖 isLoading 判定，会被上一层状态影响误拦。
    // 防重复已由 HomePage 的 800ms 节流 + showStringAction 的 _stringActionLock 覆盖。
    isLoading.value = true;

    try {
      final actionData = <String, dynamic>{
        'action': config.actionId,
        'value': config.value ?? '',
      };

      if (_extend != null) actionData['extend'] = _extend;
      if (_apiUrl != null && _apiUrl!.isNotEmpty) actionData['apiUrl'] = _apiUrl;

      final response = await _actionService.executeAction(_module, actionData);
      final result = _actionService.parseResponse(response);

      // 请求完成后立即复位，避免 _dispatchActionResult 里的 await 影响后续弹窗
      isLoading.value = false;

      await _dispatchActionResult(result);
    } catch (e, stack) {
      debugPrint('_handleSubmit error: $e');
      debugPrint(stack.toString());
      _handleToast('操作失败: $e', 'error');
      isLoading.value = false;
    }
  }

  /// 把 ActionResult 分派为：递归 Action / 专项动作 / Toast / 数据。
  ///
  /// 由 _handleSubmit 和 showStringAction 共用，避免两处重复。
  ///
  /// 关键设计：
  /// - 递归分支用 await showAction 直接触发下一层弹窗，
  ///   避免 addPostFrameCallback 在异步上下文里"等下一帧"导致弹窗延迟；
  /// - 下一层弹窗关闭后，把它的结果回填给上一层的 oldCompleter，
  ///   保持"下一层结果 = 上一层返回值"的语义。
  Future<void> _dispatchActionResult(ActionResult result) async {
    // 1. 递归 Action
    if (result.nextAction != null) {
      final oldCompleter = _completer;
      await close();
      final nextResult = await showAction(
        result.nextAction!.toJson(),
        module: _module,
        extend: _extend,
        apiUrl: _apiUrl,
      );
      if (oldCompleter != null && !oldCompleter.isCompleted) {
        oldCompleter.complete(nextResult);
      }
      return;
    }

    // 2. 专项动作
    if (result.specialAction != null) {
      final Map<String, dynamic> specialData = result.specialAction!;
      final actionId = specialData['actionId']?.toString() ?? '';
      final shouldClose = actionId != '__keep__';
      if (shouldClose) await close();
      final specialResult =
          await _handleSpecialActionFromMap(result.specialAction);
      if (shouldClose && _completer != null && !_completer!.isCompleted) {
        _completer!.complete(specialResult);
      }
      return;
    }

    // 3. Toast
    if (result.toast != null && result.toast!.isNotEmpty) {
      _handleToast(result.toast!, 'success');
    }

    // 4. 数据分支
    if (result.data != null) {
      if (result.data is Map) {
        final map = result.data as Map;
        if (map.containsKey('type')) {
          final oldCompleter = _completer;
          await close();
          final nextResult = await showAction(
            map,
            module: _module,
            extend: _extend,
            apiUrl: _apiUrl,
          );
          if (oldCompleter != null && !oldCompleter.isCompleted) {
            oldCompleter.complete(nextResult);
          }
          return;
        }
        final messages = <String>[];
        map.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            messages.add('$key: $value');
          }
        });
        if (messages.isNotEmpty) {
          _handleToast(messages.join('\n'), 'success');
        }
      } else if (result.data is String && (result.data as String).isNotEmpty) {
        _handleToast(result.data as String, 'success');
      }
    }

    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(result);
    }
    await close();
  }

  Future<ActionResult?> _handleSpecialAction(ActionConfig config) async {
    return _handleSpecialActionFromMap(config.specialParams);
  }

  Future<ActionResult?> _handleSpecialActionFromMap(dynamic actionData) async {
    final Map<String, dynamic> map;
    if (actionData is Map<String, dynamic>) {
      map = actionData;
    } else {
      map = {};
    }
    final actionId = map['actionId']?.toString() ?? '';

    switch (actionId) {
      case '__keep__':
        final msg = map['msg']?.toString();
        final reset = map['reset'] ?? false;
        if (msg != null && msg.isNotEmpty) {
          currentMessage.value = msg;
        }
        if (reset) {
          inputValues.clear();
          shouldReset.value = true;
        }
        return ActionResult(success: true, specialAction: map, toast: msg);

      case '__close__':
        final msg = map['msg']?.toString();
        if (msg != null && msg.isNotEmpty) {
          _handleToast(msg, 'info');
        }
        return ActionResult(success: true);

      case '__detail__':
        final skey = map['skey']?.toString();
        final ids = map['ids']?.toString();
        if (skey != null && skey.isNotEmpty && ids != null && ids.isNotEmpty) {
          if (Get.isRegistered<SourceManager>()) {
            Get.find<SourceManager>().switchSiteByKey(skey);
          }
          Get.toNamed('/detail', arguments: {'vodId': ids, 'siteKey': skey});
        } else {
          _handleToast('跳转详情页参数不完整', 'error');
        }
        return ActionResult(success: true);

      case '__copy__':
        final content = map['content']?.toString();
        if (content != null && content.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: content));
          _handleToast('已复制到剪贴板', 'success');
        } else {
          _handleToast('没有可复制的内容', 'error');
        }
        return ActionResult(success: true);

      case '__self_search__':
        final skey = map['skey']?.toString() ?? '';
        final tid = map['tid']?.toString() ?? '';
        final name = map['name']?.toString();
        final msg = map['msg']?.toString();

        if (tid.isEmpty) {
          _handleToast('源内搜索参数不完整：缺少 tid', 'error');
          return ActionResult(success: false, error: '缺少 tid');
        }

        // 目标源：指定则用指定的，否则用当前源
        final sourceManager = Get.find<SourceManager>();
        final targetKey = skey.isNotEmpty
            ? skey
            : (sourceManager.currentSite.value?['key']?.toString() ?? '');

        if (targetKey.isEmpty) {
          _handleToast('无法确定搜索源', 'error');
          return ActionResult(success: false, error: '无源');
        }

        _handleToast(
          (msg != null && msg.isNotEmpty) ? msg : '执行源内搜索',
          'info',
        );

        Get.toNamed(
          AppPages.searchResult,
          arguments: {
            'keyword': tid,
            'sources': [targetKey],
            'onlyDefault': false,
            'selfSearch': true,
            'title': name,
          },
        );

        return ActionResult(success: true);

      case '__refresh_list__':
        _handleToast('列表已刷新', 'success');
        // 调用 HomeController 的刷新方法（如果已注册）
        try {
          if (Get.isRegistered<HomeController>()) {
            Get.find<HomeController>().refreshData();
          }
        } catch (e) {
          // 忽略错误，不阻塞动作流程
        }
        return ActionResult(success: true);

      case '__ktvplayer__':
        final name = map['name']?.toString() ?? 'KTV';
        final id = map['id']?.toString();
        final url = map['url']?.toString();
        if ((id != null && id.isNotEmpty) || (url != null && url.isNotEmpty)) {
          Get.toNamed('/player', arguments: {
            'vodId': id,
            'playUrl': url,
            'title': name,
            'isKtv': true,
          });
        } else {
          _handleToast('播放参数不完整', 'error');
        }
        return ActionResult(success: true);

      default:
        return ActionResult(success: true, data: map);
    }
  }

  void _handleSpecialActionFromChild(String actionType, dynamic actionData) {
    close();
    Future.delayed(const Duration(milliseconds: 100), () async {
      final Map<String, dynamic> specialParams;
      if (actionData is Map<String, dynamic>) {
        specialParams = actionData;
      } else {
        specialParams = {'data': actionData};
      }
      final config = ActionConfig(
        actionId: actionType,
        specialParams: specialParams,
      );
      final result = await _handleSpecialAction(config);
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete(result);
      }
    });
  }

  void _handleToast(String message, String type) {
    SmartDialog.showToast(message);
  }

  void _handleReset() {
    debugPrint('[Action] Reset triggered');
  }

  void _handleCancel() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    close();
  }

  void _handleClose() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    close();
  }

  @override
  void onClose() {
    close();
    super.onClose();
  }
}
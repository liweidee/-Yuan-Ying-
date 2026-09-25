import 'package:get/get.dart';

import '../services/lx_js_engine.dart';
import '../utils/lx_logger.dart';

/// 洛雪音乐主控制器
class LxMusicController extends GetxController {
  final LxJsEngine _engine = LxJsEngine.instance;

  /// 当前 Tab（0=搜索 1=歌单 2=榜单）
  final RxInt tabIndex = 0.obs;

  /// 引擎是否就绪（UI 可据此显示"正在初始化"）
  final RxBool engineReady = false.obs;

  /// 是否已激活脚本
  final RxBool hasActiveScript = false.obs;

  /// 已注册的源列表
  final RxList<String> registeredSources = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      LxLogger.globalSink ??= _defaultGlobalSink;
      await _engine.init();
      engineReady.value = true;

      // 恢复上次激活的脚本
      final persistedId = await _engine.getPersistedActiveScriptId();
      if (persistedId != null) {
        if (_engine.getScript(persistedId) != null) {
          LxLogger.info('恢复激活脚本: $persistedId');
          await _engine.activateScript(persistedId);
        } else {
          LxLogger.warn('恢复失败：脚本不存在 $persistedId');
          await _engine.deactivateScript();
        }
      }

      // 监听引擎状态
      _engine.stateStream.listen((state) {
        hasActiveScript.value = _engine.isActive;
        registeredSources.value = _engine.sources.keys.toList();
        LxLogger.info('引擎状态: $state, 激活=${_engine.isActive}');
      });

      // 监听脚本事件
      _engine.eventStream.listen((event) {
        hasActiveScript.value = _engine.isActive;
        registeredSources.value = _engine.sources.keys.toList();
      });
    } catch (e) {
      LxLogger.error('引擎初始化失败: $e');
      engineReady.value = true; // 标记完成，避免 UI 卡住
    }
  }

  /// 默认全局日志出口（占位）
  void _defaultGlobalSink(String tag, String message) {
    // 若项目有 SystemLogService，可在此接入
    // SystemLogService.instance?.add(tag, message);
  }

  void switchTab(int index) {
    tabIndex.value = index;
  }
}
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/models/common/bar_hide_type.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:yuanying/models/common/theme/theme_type.dart';
import 'package:yuanying/models/common/theme/theme_color_type.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/modules/setting/views/color_select_page.dart';
import 'package:yuanying/common/widgets/dialog/select_dialog.dart';
import 'package:yuanying/modules/setting/widgets/dual_slider_dialog.dart';
import 'package:yuanying/modules/setting/widgets/slider_dialog.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/utils/get_ext.dart';
import 'package:yuanying/utils/storage_manager.dart';
import 'package:yuanying/utils/theme_utils.dart';
import 'package:yuanying/common/widgets/scale_app.dart';
import 'package:yuanying/models/common/nav_bar_config.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class StyleSetting extends StatefulWidget {
  const StyleSetting({super.key});

  @override
  State<StyleSetting> createState() => _StyleSettingState();
}

class _StyleSettingState extends State<StyleSetting> {
  late ThemeType _currentThemeType;
  late int _currentColorIndex;
  late bool _pureBlackEnabled;

  @override
  void initState() {
    super.initState();
    _currentThemeType = ThemeUtils.getThemeType();
    _currentColorIndex = ThemeUtils.getCustomColorIndex();
    _pureBlackEnabled = ThemeUtils.getPureBlackTheme();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('外观设置'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Style.safeSpace),
        children: [
          // ===== 原有功能：主题模式 =====
          _buildSettingItem(
            context: context,
            icon: Icons.brightness_6_outlined,
            title: '主题模式',
            subtitle: '当前：${_currentThemeType.desc}',
            onTap: _showThemeModeDialog,
          ),
          const SizedBox(height: 8),

          // ===== 原有功能：应用主题 =====
          _buildSettingItem(
            context: context,
            icon: Icons.palette_outlined,
            title: '应用主题',
            subtitle: _getColorLabel(_currentColorIndex),
            onTap: _navigateToColorSelect,
          ),
          const SizedBox(height: 8),

          // ===== 原有功能：纯黑主题 =====
          _buildSwitchItem(
            context: context,
            icon: Icons.dark_mode_outlined,
            title: '纯黑主题',
            subtitle: '开启后暗色模式背景变为纯黑',
            value: _pureBlackEnabled,
            onChanged: _onPureBlackChanged,
          ),
          const SizedBox(height: 16),

          // ============================================================
          // 新增功能1：App字体字重
          // ============================================================
          _buildSplitItem(
            context: context,
            icon: Icons.text_fields,
            title: 'App字体字重',
            subtitle: '点击设置',
            switchKey: SettingBoxKey.appFontWeight,
            onTitleTap: _showFontWeightDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能2：字体大小
          _buildSettingItem(
            context: context,
            icon: Icons.format_size_outlined,
            title: '字体大小',
            subtitle: () {
              final scale = SettingPref.defaultTextScale;
              return scale == 1.0 ? '默认' : scale.toString();
            }(),
            onTap: _navigateToFontSizeSetting,
          ),
          const SizedBox(height: 8),

          // 新增功能3：界面缩放
          _buildSettingItem(
            context: context,
            icon: Icons.zoom_in_outlined,
            title: '界面缩放',
            subtitle: '当前缩放比例：${SettingPref.uiScale.toStringAsFixed(2)}',
            onTap: _showUiScaleDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能4：列表宽度限制
          _buildSettingItem(
            context: context,
            icon: Icons.calendar_view_week_outlined,
            title: '列表宽度（dp）限制',
            subtitle: '当前: 主页${SettingPref.recommendCardWidth.toInt()}dp 其他${SettingPref.smallCardWidth.toInt()}dp',
            onTap: _showCardWidthDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能5：页面过渡动画
          _buildSettingItem(
            context: context,
            icon: Icons.animation,
            title: '页面过渡动画',
            subtitle: '当前：${SettingPref.pageTransition.name}',
            onTap: _showTransitionDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能6：导航栏样式：悬浮底栏
          // _buildSwitchItem(
          //   context: context,
          //   icon: MdiIcons.soundbar,
          //   title: '悬浮底栏',
          //   subtitle: '开启后底栏悬浮显示',
          //   value: SettingPref.floatingNavBar,
          //   onChanged: _onFloatingNavBarChanged,
          //   needReboot: true,
          // ),
          // const SizedBox(height: 8),
          _buildSettingItem(
            context: context,
            icon: Icons.navigation_outlined,
            title: '导航栏样式',
            subtitle: '当前：${SettingPref.navigationBarStyle.label}',
            onTap: _showNavigationBarStyleDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能7：播放页移除安全边距
          _buildSwitchItem(
            context: context,
            icon: Icons.fit_screen_outlined,
            title: '播放页移除安全边距',
            subtitle: '移除播放页面的安全区域边距',
            value: SettingPref.removeSafeArea,
            onChanged: _onRemoveSafeAreaChanged,
          ),
          const SizedBox(height: 8),

          // 新增功能8：视频播放页深色主题
          // _buildSwitchItem(
          //   context: context,
          //   icon: Icons.dark_mode_outlined,
          //   title: '视频播放页使用深色主题',
          //   subtitle: '视频播放页面强制使用深色主题',
          //   value: SettingPref.darkVideoPage,
          //   onChanged: _onDarkVideoPageChanged,
          // ),
          // const SizedBox(height: 8),

          // 新增功能9：顶/底栏收齐类型
          _buildSettingItem(
            context: context,
            icon: Icons.unfold_more,
            title: '顶/底栏收起类型',
            subtitle: '当前：${SettingPref.barHideType.label}',
            onTap: _showBarHideTypeDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能10：首页顶栏收齐
          _buildSwitchItem(
            context: context,
            icon: Icons.vertical_align_top_outlined,
            title: '首页顶栏收齐',
            subtitle: '开启后滚动时顶部栏自动收起',
            value: SettingPref.hideTopBar,
            onChanged: _onHideTopBarChanged,
          ),
          const SizedBox(height: 8),

          // 新增功能11：首页底栏收齐
          _buildSwitchItem(
            context: context,
            icon: Icons.vertical_align_bottom_outlined,
            title: '首页底栏收齐',
            subtitle: '开启后滚动时底部导航栏自动收起',
            value: SettingPref.hideBottomBar,
            onChanged: _onHideBottomBarChanged,
          ),
          const SizedBox(height: 8),

          // 新增功能12：默认启动页
          _buildSettingItem(
            context: context,
            icon: Icons.home_outlined,
            title: '默认启动页',
            subtitle: '当前启动页：${SettingPref.defaultHomePage.label}',
            onTap: _showDefHomeDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能13：滑动动画弹簧参数
          _buildSettingItem(
            context: context,
            icon: Icons.chrome_reader_mode_outlined,
            title: '滑动动画弹簧参数',
            subtitle: '点击设置弹簧参数',
            onTap: _showSpringDialog,
          ),
          const SizedBox(height: 8),

          // 新增功能14：Navbar编辑
          _buildSettingItem(
            context: context,
            icon: Icons.toc_outlined,
            title: 'Navbar编辑',
            subtitle: '删除或调换Navbar',
            onTap: _navigateToBarSetting,
          ),
          const SizedBox(height: 8),

          // 新增功能15：返回时直接退出
          _buildSwitchItem(
            context: context,
            icon: Icons.exit_to_app_outlined,
            title: '返回时直接退出',
            subtitle: '开启后在主页任意tab按返回键都直接退出，关闭则先回到第一个tab',
            value: SettingPref.directExitOnBack,
            onChanged: _onDirectExitOnBackChanged,
          ),
          const SizedBox(height: 8),

          // 底部留白
          SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 80),
        ],
      ),
    );
  }

  // ========================================================================
  // 辅助方法
  // ========================================================================

  void _refreshUI() {
    if (mounted) setState(() {});
  }

  /// 全局更新应用（主题、字体等需要重建UI的功能）
  void _updateApp() {
    Get.updateMyAppTheme();
  }

  String _getColorLabel(int index) {
    if (index >= 0 && index < colorThemeTypes.length) {
      return '当前：${colorThemeTypes[index].label}';
    }
    return '当前：默认绿';
  }

  // ========================================================================
  // 原有功能的回调
  // ========================================================================

  void _showThemeModeDialog() async {
    final result = await showDialog<ThemeType>(
      context: context,
      builder: (context) => SelectDialog<ThemeType>(
        title: '主题模式',
        value: _currentThemeType,
        values: ThemeType.values.map((e) => (e, e.desc)).toList(),
      ),
    );

    if (result != null && result != _currentThemeType) {
      _currentThemeType = result;
      await ThemeUtils.setThemeMode(result);
      _updateApp();
    }
  }

  void _navigateToColorSelect() async {
    final result = await Get.to(() => const ColorSelectPage());
    if (result != null && result != _currentColorIndex) {
      _currentColorIndex = result;
      await ThemeUtils.setCustomColor(result);
      _updateApp();
    }
  }

  void _onPureBlackChanged(bool value) async {
    _pureBlackEnabled = value;
    await ThemeUtils.setPureBlackTheme(value);
    _updateApp();
  }

  // ========================================================================
  // 新增功能的回调
  // ========================================================================

  // ----- 字体字重 -----
  void _showFontWeightDialog() async {
    final dynamic rawValue = StorageManager.getSetting<dynamic>(SettingBoxKey.appFontWeight);
    int intValue;
    if (rawValue is bool) {
      intValue = rawValue ? 4 : -1;
      StorageManager.setSetting(SettingBoxKey.appFontWeight, intValue);
    } else if (rawValue is int) {
      intValue = rawValue;
    } else {
      intValue = -1;
    }
    final int initialValue = intValue == -1 ? 4 : intValue;

    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        title: const Text('App字体字重'),
        value: initialValue.toDouble() + 1,
        min: 1,
        max: FontWeight.values.length.toDouble(),
        divisions: FontWeight.values.length - 1,
        precise: 0,
      ),
    );
    if (res != null) {
      StorageManager.setSetting(SettingBoxKey.appFontWeight, res.toInt() - 1);
      _updateApp();
    }
  }

  // ----- 字体大小 -----
  void _navigateToFontSizeSetting() async {
    final res = await Get.toNamed(AppPages.fontSizeSetting);
    if (res != null) {
      // 字体大小修改后需要重建应用以应用新的 textScaleFactor
      Get.appUpdate();
      _refreshUI();
    }
  }

  // ----- 界面缩放 -----
  void _showUiScaleDialog() async {
    const minUiScale = 0.5;
    const maxUiScale = 2.0;
    double uiScale = SettingPref.uiScale;
    final textController = TextEditingController(text: uiScale.toStringAsFixed(2));

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('界面缩放'),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            spacing: 20,
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                padding: EdgeInsets.zero,
                value: uiScale,
                min: minUiScale,
                max: maxUiScale,
                secondaryTrackValue: 1.0,
                divisions: ((maxUiScale - minUiScale) * 20).toInt(),
                label: textController.text,
                onChanged: (value) => setDialogState(() {
                  uiScale = value.toPrecision(2);
                  textController.text = uiScale.toStringAsFixed(2);
                }),
              ),
              TextFormField(
                controller: textController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(4),
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]+')),
                ],
                decoration: const InputDecoration(
                  labelText: '缩放比例',
                  hintText: '0.50 - 2.00',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed >= minUiScale && parsed <= maxUiScale) {
                    setDialogState(() {
                      uiScale = parsed;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              StorageManager.deleteSetting(SettingBoxKey.uiScale);
              // 重置缩放
              _applyUiScale(1.0);
              _refreshUI();
            },
            child: const Text('重置'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, uiScale);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null) {
      _applyUiScale(result);
      _refreshUI();
    }
  }

  /// 应用界面缩放
  void _applyUiScale(double scale) {
    SettingPref.uiScale = scale;
    // 关键：更新 ScaledWidgetsFlutterBinding 的 scaleFactor
    try {
      final binding = WidgetsBinding.instance;
      if (binding is ScaledWidgetsFlutterBinding) {
        binding.scaleFactor = scale;
      }
    } catch (e) {
      // 如果 binding 不是 ScaledWidgetsFlutterBinding，忽略
    }
    Get.appUpdate();
  }

  // ----- 列表宽度限制 -----
  void _showCardWidthDialog() async {
    final res = await showDialog<(double, double)>(
      context: context,
      builder: (context) => DualSliderDialog(
        title: const Text('列表最大列宽度（默认240dp）'),
        value1: SettingPref.recommendCardWidth,
        value2: SettingPref.smallCardWidth,
        description1: const Text('主页推荐流'),
        description2: const Text('其他'),
        min: 150.0,
        max: 500.0,
        divisions: 35,
        suffix: 'dp',
        precise: 0,
      ),
    );
    if (res != null) {
      SettingPref.recommendCardWidth = res.$1;
      SettingPref.smallCardWidth = res.$2;
      // ===== 修复：强制刷新整个应用，让首页重新布局 =====
      Get.appUpdate();
      _refreshUI();
    }
  }

  // ----- 页面过渡动画 -----
  void _showTransitionDialog() async {
    final res = await showDialog<Transition>(
      context: context,
      builder: (context) => SelectDialog<Transition>(
        title: '页面过渡动画',
        value: SettingPref.pageTransition,
        values: Transition.values.map((e) => (e, e.name)).toList(),
      ),
    );
    if (res != null) {
      Get.rootController.defaultTransition = res;
      SettingPref.pageTransition = res;
      _refreshUI();
    }
  }

  // ----- 悬浮底栏 -----
  void _onFloatingNavBarChanged(bool value) {
    SettingPref.floatingNavBar = value;
    _refreshUI();
  }

  void _showNavigationBarStyleDialog() async {
    final res = await showDialog<NavigationBarStyle>(
      context: context,
      builder: (context) => SelectDialog<NavigationBarStyle>(
        title: '导航栏样式',
        value: SettingPref.navigationBarStyle,
        values: NavigationBarStyle.values.map((e) => (e, e.label)).toList(),
      ),
    );
    if (res != null) {
      SettingPref.navigationBarStyle = res;
      if (Get.isRegistered<MainController>()) {
        Get.find<MainController>().refreshNavBarStyle();
      }
      SmartDialog.showToast('切换成功');
      _refreshUI();
    }
  }

  // ----- 移除安全边距 -----
  void _onRemoveSafeAreaChanged(bool value) {
    SettingPref.removeSafeArea = value;
    _refreshUI();
  }

  // ----- 视频深色主题 -----
  // void _onDarkVideoPageChanged(bool value) {
  //   SettingPref.darkVideoPage = value;
  //   _refreshUI();
  // }

  // ----- 顶/底栏收齐类型 -----
  void _showBarHideTypeDialog() async {
    final res = await showDialog<BarHideType>(
      context: context,
      builder: (context) => SelectDialog<BarHideType>(
        title: '顶/底栏收起类型',
        value: SettingPref.barHideType,
        values: BarHideType.values.map((e) => (e, e.label)).toList(),
      ),
    );
    if (res != null) {
      SettingPref.barHideType = res;
      _refreshUI();
    }
  }

  // ----- 首页顶栏收齐 -----
  void _onHideTopBarChanged(bool value) {
    SettingPref.hideTopBar = value;
    // 通知 HomeController 更新
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().refreshHideTopBar();
    }
    _refreshUI();
  }

  // ----- 首页底栏收齐 -----
  void _onHideBottomBarChanged(bool value) {
    SettingPref.hideBottomBar = value;
    // 通知 MainController 更新
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().refreshHideBottomBar();
    }
    _refreshUI();
  }

  // ----- 默认启动页 -----
  void _showDefHomeDialog() async {
    final res = await showDialog<NavigationBarType>(
      context: context,
      builder: (context) => SelectDialog<NavigationBarType>(
        title: '首页启动页',
        value: SettingPref.defaultHomePage,
        values: NavigationBarType.values.map((e) => (e, e.label)).toList(),
      ),
    );
    if (res != null) {
      SettingPref.defaultHomePage = res;
      _refreshUI();
    }
  }

  // ----- 弹簧参数 -----
  void _showSpringDialog() async {
    final List<String> springDescription = SettingPref.springDescription
        .map((i) => i.toString())
        .toList(growable: false);
    bool physicalMode = true;

    void physical2Duration() {
      try {
        final mass = double.parse(springDescription[0]);
        final stiffness = double.parse(springDescription[1]);
        final damping = double.parse(springDescription[2]);
        final duration = math.sqrt(4 * math.pi * math.pi * mass / stiffness);
        final dampingRatio = damping / (2.0 * math.sqrt(mass * stiffness));
        final bounce = dampingRatio < 1.0
            ? 1.0 - dampingRatio
            : 1.0 / dampingRatio - 1;
        springDescription[0] = duration.toString();
        springDescription[1] = bounce.toString();
      } catch (e) {
        SmartDialog.showToast('转换失败: $e');
      }
    }

    void duration2Physical() {
      try {
        final duration = double.parse(springDescription[0]);
        final bounce = double.parse(springDescription[1]).clamp(-1.0, 1.0);
        final stiffness = 4 * math.pi * math.pi / math.pow(duration, 2);
        final dampingRatio = bounce > 0 ? 1.0 - bounce : 1.0 / (bounce + 1);
        final damping = 2 * math.sqrt(stiffness) * dampingRatio;
        springDescription[0] = '1';
        springDescription[1] = stiffness.toString();
        springDescription[2] = damping.toString();
      } catch (e) {
        SmartDialog.showToast('转换失败: $e');
      }
    }

    final res = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = ColorScheme.of(context);
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('弹簧参数'),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    try {
                      if (physicalMode) {
                        physical2Duration();
                      } else {
                        duration2Physical();
                      }
                      physicalMode = !physicalMode;
                      setDialogState(() {});
                    } catch (e) {
                      SmartDialog.showToast('转换失败: $e');
                    }
                  },
                  child: Text(physicalMode ? '切换到时间模式' : '切换到物理模式'),
                ),
              ],
            ),
            content: Column(
              key: ValueKey(physicalMode),
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                physicalMode ? 3 : 2,
                (index) {
                  final labels = physicalMode
                      ? ['质量 (mass)', '刚度 (stiffness)', '阻尼 (damping)']
                      : ['滑动时间 (s)', '反弹 (bounce)'];
                  return TextFormField(
                    autofocus: index == 0,
                    initialValue: springDescription[index],
                    keyboardType: TextInputType.numberWithOptions(
                      signed: !physicalMode && index == 1,
                      decimal: true,
                    ),
                    onChanged: (value) => springDescription[index] = value,
                    inputFormatters: [
                      !physicalMode && index == 1
                          ? FilteringTextInputFormatter.allow(RegExp(r'[-\d.]+'))
                          : FilteringTextInputFormatter.allow(RegExp(r'[\d.]+')),
                    ],
                    decoration: InputDecoration(labelText: labels[index]),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text('重置'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '取消',
                  style: TextStyle(color: colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: () {
                  try {
                    if (!physicalMode) duration2Physical();
                    final res = springDescription.map(double.parse).toList();
                    Navigator.pop(context, true);
                    SettingPref.springDescription = res;
                    SmartDialog.showToast('设置成功，重启生效');
                  } catch (e) {
                    SmartDialog.showToast('输入无效: $e');
                  }
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );

    if (res == false) {
      // 重置
      StorageManager.deleteSetting(SettingBoxKey.springDescription);
      SmartDialog.showToast('重置成功，重启生效');
      _refreshUI();
    } else if (res == true) {
      _refreshUI();
    }
  }

  // ----- Navbar编辑 -----
  void _navigateToBarSetting() {
    Get.toNamed(
      AppPages.barSetting,
      arguments: {
        'key': SettingBoxKey.navBarSort,
        'defaultBars': NavigationBarType.values,
        'title': 'Navbar',
      },
    );
  }

  // ----- 返回时直接退出 -----
  void _onDirectExitOnBackChanged(bool value) {
    SettingPref.directExitOnBack = value;
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().directExitOnBack = value;
    }
    _refreshUI();
  }

  // ========================================================================
  // UI组件
  // ========================================================================

  Widget _buildSettingItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: InkWell(
        borderRadius: Style.mdRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Style.mdRadius,
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  borderRadius: Style.mdRadius,
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool needReboot = false,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Style.mdRadius,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius: Style.mdRadius,
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: (v) {
                onChanged(v);
                if (needReboot) {
                  SmartDialog.showToast('重启生效');
                }
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String switchKey,
    required VoidCallback onTitleTap,
  }) {
    final theme = Theme.of(context);

    final dynamic rawValue = StorageManager.getSetting<dynamic>(switchKey);
    int intValue;
    if (rawValue is bool) {
      intValue = rawValue ? 4 : -1;
      StorageManager.setSetting(switchKey, intValue);
    } else if (rawValue is int) {
      intValue = rawValue;
    } else {
      intValue = -1;
    }
    final bool switchValue = intValue != -1;

    return Material(
      color: Colors.transparent,
      borderRadius: Style.mdRadius,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Style.mdRadius,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius: Style.mdRadius,
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: onTitleTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 25,
              child: VerticalDivider(
                width: 1,
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch(
                value: switchValue,
                onChanged: (v) {
                  if (v) {
                    StorageManager.setSetting(switchKey, 4);
                  } else {
                    StorageManager.setSetting(switchKey, -1);
                  }
                  _updateApp();
                  _refreshUI();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
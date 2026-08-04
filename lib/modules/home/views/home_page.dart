import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/common/widgets/button/icon_button.dart';
import 'package:yuanying/common/widgets/flutter/refresh_indicator.dart'
    as custom;
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/common/widgets/video_card/video_card_h.dart';
import 'package:yuanying/common/skeleton/video_card_v.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/utils/grid.dart';
import 'package:yuanying/modules/action/widgets/action_renderer.dart';
import 'package:yuanying/common/widgets/marquee.dart';
import 'package:yuanying/modules/push/views/push_dialog.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/services/search_filter_service.dart';
import 'package:yuanying/utils/storage.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/modules/setting/views/site_config_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  late final HomeController controller;
  late final SourceManager sourceManager;
  late TextScaler textScaler;
  late final ActionRenderer actionRenderer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    controller = Get.put(HomeController());
    sourceManager = Get.find<SourceManager>();
    actionRenderer = Get.find<ActionRenderer>();

    // ===== 监听滚动更新底栏偏移 =====
    controller.scrollController.addListener(_onScrollUpdateBottomBar);
  }

  /// 跳转到详情页或处理 Action
  void _navigateToDetail(VideoItem item) {
    // ===== 1. Action 卡片处理 =====
    if (item.isAction) {
      final config = item.actionConfig;
      if (config != null) {
        actionRenderer.showAction(
          config.toJson(),
          module: sourceManager.currentSite.value?['key'] ?? '',
          extend: sourceManager.currentSite.value?['ext'],
          apiUrl: sourceManager.currentSite.value?['api'],
        );
        return;
      }
      SmartDialog.showToast('Action 配置解析失败');
      return;
    }

    // ===== 2. 文件夹处理 =====
    if (item.vodTag == 'folder') {
      final category = Category(
        typeId: item.vodId,
        typeName: item.vodName,
      );
      controller.switchCategory(category);
      if (controller.scrollController.hasClients) {
        controller.scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    // ===== 3. 豆瓣源：直接跳转到搜索结果页 =====
    final site = sourceManager.currentSite.value;
    final siteName = site?['name']?.toString() ?? '';
    if (siteName.contains('豆瓣[官]') || siteName.contains('TMDB[官]')) {
      // 获取搜索过滤器
      final filterService = Get.find<SearchFilterService>();
      List<String> sourceKeys;
      final bool onlyDefault = filterService.onlyDefaultSource.value;
      
      if (onlyDefault) {
        // 只搜当前源
        final currentKey = sourceManager.currentSite.value?['key']?.toString() ?? '';
        sourceKeys = currentKey.isNotEmpty ? [currentKey] : [];
      } else {
        // 搜所有已启用的源
        sourceKeys = filterService.enabledSourceKeyList;
      }

      // 兜底：如果源列表为空，则使用当前源
      if (sourceKeys.isEmpty) {
        final currentKey = sourceManager.currentSite.value?['key']?.toString() ?? '';
        if (currentKey.isNotEmpty) sourceKeys = [currentKey];
      }

      // 如果仍然为空，提示并返回
      if (sourceKeys.isEmpty) {
        SmartDialog.showToast('没有可用的搜索源');
        return;
      }

      // 跳转到搜索结果页
      Get.toNamed(
        AppPages.searchResult,
        arguments: {
          'keyword': item.vodName,
          'sources': sourceKeys,
          'onlyDefault': onlyDefault,
        },
      );
      return;
    }

    // ===== 4. 普通视频：跳转详情页 =====
    final pwd = site?['ext'] is Map 
        ? (site!['ext'] as Map)['pwd']?.toString() ?? 'tinydust'
        : 'tinydust';
    
    Get.toNamed(
      AppPages.detail,
      arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
      },
    );
  }

  void _showPushDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PushDialog(),
    );
  }

  // ===== 滚动监听：更新底栏偏移 =====
  void _onScrollUpdateBottomBar() {
    final scrollCtr = controller.scrollController;
    if (!scrollCtr.hasClients) return;
    final offset = scrollCtr.position.pixels;
    
    final mainController = Get.find<MainController>();
    mainController.updateBottomBarOffset(offset);
  }

  @override
  void dispose() {
    controller.scrollController.removeListener(_onScrollUpdateBottomBar);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    textScaler = MediaQuery.textScalerOf(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        clipBehavior: Clip.hardEdge,
        margin: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
        decoration: const BoxDecoration(borderRadius: Style.mdRadius),
        child: Obx(() {
          // ===== 1. 配置加载中 =====
          if (sourceManager.isConfigLoading.value) {
            return Column(
              children: [
                _buildTopBar(theme),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          if (sourceManager.configLoadError.value) {
            // 配置加载失败
            return _buildConfigError(theme);
          }

          // ===== 2. 首页请求中 =====
          if (controller.isHomeLoading.value) {
            return Column(
              children: [
                _buildTopBar(theme),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // ===== 3. 切换源中 =====
          if (controller.isSwitchingSource.value) {
            return Column(
              children: [
                _buildTopBar(theme),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // ===== 4. 首页请求失败 =====
          if (controller.isHomeError.value) {
            return Column(
              children: [
                _buildTopBar(theme),
                Expanded(
                  child: Center(
                    child: Text(
                      '暂无数据',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // ===== 5. 配置列表为空（加载完成后才判断） =====
          if (sourceManager.sites.isEmpty) {
            return _buildEmptyConfig(theme);
          }

          // ===== 6. 正常内容 =====
          final bool isInstant = Get.find<MainController>().isInstantMode;
          final bool isRecommend = controller.currentCategory.value?.typeId == 'recommend' || (controller.currentCategory.value == null && controller.categories.isNotEmpty);

          Widget scrollView = CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: !controller.hideTopBar.value,
                floating: controller.hideTopBar.value,
                snap: false,
                elevation: 0,
                backgroundColor: theme.colorScheme.surface,
                toolbarHeight: 52,
                expandedHeight: 52,
                key: ValueKey('appbar_${isInstant ? 'instant' : 'sync'}'),
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildTopBar(theme),
                ),
              ),
              if (controller.categories.isNotEmpty)   // 仅当有分类时才显示
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CategoryHeaderDelegate(theme: theme),
                ),
              Obx(() {
                final siteKey = sourceManager.currentSite.value?['key'] ?? '';
                final showFilter = controller.getFilterVisibility(siteKey);
                final cid = controller.currentCategory.value?.typeId;
                final hasFilter = cid != null &&
                    controller.filters.containsKey(cid) &&
                    controller.filters[cid]!.isNotEmpty;

                if (!showFilter || !hasFilter) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(child: _buildFilterBar(theme));
              }),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              Obx(() => _buildContent(theme)),
            ],
          );

          // 推荐分类禁用下拉刷新
          if (!isRecommend) {
            return custom.RefreshIndicator(
              onRefresh: controller.refreshData,
              child: scrollView,
            );
          }

          return scrollView;
        }),
      ),
    );
  }

  Widget _buildEmptyConfig(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        _buildTopBar(theme),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 第一行：图标 + 文字（水平居中）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.api_outlined,  // 替换为更合适的接口图标
                        size: 24,
                        color: colorScheme.outline.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '暂无接口配置',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                          color: colorScheme.onSurface,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 第二行：配置按钮（无图标）
                  FilledButton(
                    onPressed: () => Get.toNamed(AppPages.setting),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Style.mdRadius.topLeft.x),
                      ),
                    ),
                    child: const Text(
                      '去添加接口',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigError(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        _buildTopBar(theme),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '配置加载失败',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请检查网络连接或配置内容是否正确',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      // 重新加载配置
                      sourceManager.loadConfig();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: _buildSourceInfo(theme),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => Get.toNamed(AppPages.search),
                  splashRadius: 20),
              IconButton(
                  icon: const Icon(Icons.send, size: 20),
                  onPressed: _showPushDialog,
                  splashRadius: 20),
              IconButton(
                  icon: const Icon(Icons.history, size: 20),
                  onPressed: () => Get.toNamed(AppPages.history),
                  splashRadius: 20),
              IconButton(
                  icon: const Icon(Icons.star_border, size: 20),
                  onPressed: () => Get.toNamed(AppPages.favorite),
                  splashRadius: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceInfo(ThemeData theme) {
    return Obx(() {
      final site = sourceManager.currentSite.value;
      final name = site?['name']?.toString() ?? '';
      final logo = site?['logo']?.toString() ?? sourceManager.configLogo.value;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ----- 头像：点击弹出切换接口弹窗 -----
          // GestureDetector(
          //   onTap: _showSwitchInterfaceDialog,
          //   child: CircleAvatar(
          //     radius: 14,
          //     backgroundColor: theme.colorScheme.primaryContainer,
          //     backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
          //     child: logo.isEmpty ? const Icon(Icons.api, size: 16) : null,
          //   ),
          // ),
          // ----- 头像：圆角方形 -----
          GestureDetector(
            onTap: _showSwitchInterfaceDialog,
            child: ClipRRect(
              borderRadius: Style.mdRadius,
              child: Container(
                width: 28,
                height: 28,
                color: theme.colorScheme.primaryContainer,
                child: logo.isNotEmpty
                    ? Image.network(
                        logo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.api,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.api,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ----- 源名称：点击弹出切换源弹窗 -----
          GestureDetector(
            onTap: _showSourceSwitchDialog,
            behavior: HitTestBehavior.opaque,  // 确保点击事件穿透
            child: SizedBox(
              width: 120,
              child: MarqueeText(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
                velocity: 25,
                spacing: 30,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down,
              size: 18, color: theme.colorScheme.outline),
        ],
      );
    });
  }

  void _showSourceSwitchDialog() {
    final sites = sourceManager.sites;
    if (sites.isEmpty) return;

    // ===== 提取所有标签（按源显示顺序排列） =====
    final allTags = <String>[];
    for (final site in sites) {
      final name = site['name']?.toString() ?? '';
      final regExp = RegExp(r'\[([^\]]+)\]');
      final matches = regExp.allMatches(name);
      for (final match in matches) {
        final tag = match.group(1)?.trim() ?? '';
        if (tag.isNotEmpty && !allTags.contains(tag)) {
          allTags.add(tag);
        }
      }
    }
    final tagList = allTags;

    // ---- 修改宽度计算 ----
    final double screenWidth = MediaQuery.of(context).size.width;
    final double dialogWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.85;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '切换接口源',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: dialogWidth,
              constraints: BoxConstraints(
                // maxHeight: MediaQuery.of(context).size.height * 0.8,
                maxHeight: 500.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _SourceSwitchDialogContent(
                sites: sites,
                tagList: tagList,
                currentSiteKey: sourceManager.currentSite.value?['key']?.toString() ?? '',
                onSelectSite: (site) {
                  sourceManager.switchSite(site);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 切换接口弹窗（中央弹窗）
    void _showSwitchInterfaceDialog() {
    final customSites = GStorage.getCustomSites();
    if (customSites.isEmpty) {
      SmartDialog.showToast('暂无接口配置，请先添加');
      return;
    }

    String currentKey = GStorage.getSetting<String>('selected_config_key') ?? '';
    if (currentKey.isEmpty || !customSites.any((site) => site['key']?.toString() == currentKey)) {
      final firstKey = customSites.first['key']?.toString();
      if (firstKey != null && firstKey.isNotEmpty) {
        currentKey = firstKey;
        GStorage.setSetting('selected_config_key', currentKey);
      }
    }

    String currentLogo = '';
    for (final site in customSites) {
      if (site['key']?.toString() == currentKey) {
        currentLogo = site['logo']?.toString() ?? '';
        break;
      }
    }

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final dialogWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.85;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            width: dialogWidth,
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ----- 头部 -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
                  child: Row(
                    children: [
                      if (currentLogo.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            currentLogo,
                            width: 28,
                            height: 28,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.api,
                              color: Colors.green[700],
                              size: 28,
                            ),
                          ),
                        )
                      else
                        Icon(Icons.api, color: Colors.green[700], size: 28),
                      const SizedBox(width: 12),
                      Text(
                        '切换接口',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(dialogContext);
                          Get.to(const SiteConfigPage());
                        },
                        child: Icon(
                          Icons.settings,
                          color: Colors.grey[600],
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                // ----- 列表 -----
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    physics: const BouncingScrollPhysics(),
                    children: customSites.map((site) {
                      final key = site['key']?.toString() ?? '';
                      final isSelected = key == currentKey;
                      final name = site['name']?.toString() ?? '未命名';
                      final source = site['_source']?.toString() ?? 'remote';

                      return GestureDetector(
                        onTap: () {
                          // 保存接口配置 key
                          GStorage.setSetting('selected_config_key', key);

                          if (source == 'local') {
                            final configKey = site['_configKey']?.toString();
                            if (configKey != null && configKey.isNotEmpty) {
                              final package = GStorage.getConfigPackage(configKey);
                              if (package != null) {
                                final sites = (package['sites'] as List?)
                                        ?.map((e) => Map<String, dynamic>.from(e))
                                        .toList() ??
                                    [];
                                final parses = (package['parses'] as List?)
                                        ?.map((e) => Map<String, dynamic>.from(e))
                                        .toList() ??
                                    [];
                                sourceManager.applyLocalConfigPackage(
                                  sites: sites,
                                  parses: parses,
                                  siteKey: key,
                                  packageKey: configKey,
                                );
                              }
                            }
                          } else if (source == 'local_file') {
                            // ===== 新增：处理本地文件配置 =====
                            final filePath = site['api']?.toString();
                            if (filePath != null && filePath.isNotEmpty) {
                              sourceManager.loadFileConfig(filePath, siteKey: key);
                            }
                          } else {
                            // 远程接口正常切换
                            sourceManager.switchConfig(key);
                          }

                          // 关闭弹窗
                          Navigator.pop(dialogContext);
                        },
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              if (isSelected)
                                Icon(
                                  Icons.radio_button_checked,
                                  color: Colors.green[700],
                                  size: 20,
                                )
                              else
                                Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey[400],
                                  size: 20,
                                ),
                              const SizedBox(width: 12),
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                  color: isSelected ? const Color(0xFF2E7D32) : Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _showAllCategoriesDialog(BuildContext context) {
    final controller = Get.find<HomeController>();
    final categories = controller.categories;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface, // 使用主题表面色
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示器
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      '全部分类',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final c = categories[index];
                    final isSelected = controller.currentCategory.value?.typeId == c.typeId;
                    return GestureDetector(
                      onTap: () {
                        controller.switchCategory(c);
                        Navigator.pop(context);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          c.typeName,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// 筛选栏 - 彻底解决溢出问题
  Widget _buildFilterBar(ThemeData theme) {
    return Obx(() {
      final cid = controller.currentCategory.value?.typeId;
      if (cid == null) return const SizedBox.shrink();

      final groups = controller.filters[cid];
      if (groups == null || groups.isEmpty) return const SizedBox.shrink();

      return Container(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // 高度由内容决定
          children: groups.map((group) {
            // 构建该组的所有筛选项
            final children = group.values.map((value) {
              final isSelected =
                  controller.currentFilterValues[group.key] == value.value;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => controller.updateFilter(group.key, value.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      value.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList();

            // 每个筛选组独立水平滚动
            // ClampingScrollPhysics：只有内容溢出时才可滚动，未溢出不可拖动
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(), // 溢出才滚动
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            );
          }).toList(),
        ),
      );
    });
  }

  Widget _buildContent(ThemeData theme) {
    final mode = controller.cardLayoutMode.value;

    // ===== 列表模式 =====
    if (Grid.isListMode(mode)) {
      // 加载中
      if (controller.isLoading.value && controller.videoList.isEmpty) {
        return SliverFillRemaining(
          child: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }

      // 错误状态
      if (controller.errorMsg.value.isNotEmpty &&
          controller.errorMsg.value != '暂无配置，请去设置页添加接口' &&
          controller.videoList.isEmpty) {
        return SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(controller.errorMsg.value),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: controller.refreshData,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      }

      // 空数据
      if (controller.videoList.isEmpty) {
        return SliverFillRemaining(
          child: Center(
            child: Text(
              '暂无数据',
              style: TextStyle(
                color: theme.colorScheme.outline,
                fontSize: 14,
              ),
            ),
          ),
        );
      }

      // 列表渲染
      return SliverPadding(
        padding: const EdgeInsets.only(bottom: 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == controller.videoList.length - 1) controller.loadMore();
              final item = controller.videoList[index];
              return VideoCardH(
                videoItem: item,
                onTap: () => _navigateToDetail(item), //传入回调
              );
            },
            childCount: controller.videoList.length,
          ),
        ),
      );
    }

    // ===== 网格模式（2列/3列） =====
    final gridDelegate = Grid.videoCardVDelegate(
      context,
      mode: mode,
      minHeight: 25,
    );

    // 加载中显示圆圈（首次加载分类或筛选变化时）
    if (controller.isLoading.value && controller.videoList.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    // 错误状态（非“暂无配置”的错误）
    if (controller.errorMsg.value.isNotEmpty &&
        controller.errorMsg.value != '暂无配置，请去设置页添加接口' &&
        controller.videoList.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(controller.errorMsg.value),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: controller.refreshData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    // 空数据
    if (controller.videoList.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            '暂无数据',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    // 显示数据列表（网格）
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 100),
      sliver: SliverGrid.builder(
        gridDelegate: gridDelegate,
        itemBuilder: (context, index) {
          if (index == controller.videoList.length - 1) controller.loadMore();
          final item = controller.videoList[index];
          return VideoCardV(
            videoItem: item,
            onTap: () => _navigateToDetail(item),  //传入回调
          );
        },
        itemCount: controller.videoList.length,
      ),
    );
  }

  late final SliverGridDelegateWithExtentAndRatio gridDelegate =
      SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: 180.0,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: textScaler.scale(90),
  );
}

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final ThemeData theme;

  const _CategoryHeaderDelegate({required this.theme});

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  bool shouldRebuild(covariant _CategoryHeaderDelegate old) => false;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const _CategoryStickyContent(),
    );
  }
}

double _getTextWidth(BuildContext context, String text, TextStyle style) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  // 限制最大宽度，防止极端情况
  return textPainter.width.clamp(0.0, MediaQuery.of(context).size.width * 0.25);
}

class _CategoryStickyContent extends StatelessWidget {
  const _CategoryStickyContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = Get.find<HomeController>();
    final sourceManager = Get.find<SourceManager>();

    return Obx(() {
      final categories = controller.categories;
      if (categories.isEmpty) {
        return ColoredBox(
          color: theme.colorScheme.surface,
          child: const SizedBox(height: 46),
        );
      }

      final siteKey = sourceManager.currentSite.value?['key'] ?? '';
      final showFilter = controller.filterBarVisibility[siteKey] ?? true;

      return Container(
        height: 46,
        color: theme.colorScheme.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：分类列表
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: categories.map((item) {
                    final isSelected = controller.currentCategory.value?.typeId == item.typeId;
                    final textStyle = TextStyle(
                      fontSize: 14,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    );

                    return GestureDetector(
                      onTap: () => controller.switchCategory(item),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // ===== 文字：永远居中 =====
                            Text(
                              item.typeName,
                              style: textStyle,
                            ),
                            // ===== 下划线：独立定位，不挤压文字 =====
                            if (isSelected)
                              Positioned(
                                bottom: 6,  // 距离底部 6px，可自由调整
                                child: Container(
                                  width: _getTextWidth(
                                    context,
                                    item.typeName,
                                    textStyle,
                                  ),
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 右侧：固定按钮（无任何偏移，与容器对齐）
            Container(
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  Obx(() {
                    final cid = controller.currentCategory.value?.typeId;
                    final hasFilter = cid != null &&
                        controller.filters.containsKey(cid) &&
                        controller.filters[cid]!.isNotEmpty;
                    if (!hasFilter) return const SizedBox.shrink();
                    return IconButton(
                      icon: Icon(
                        showFilter ? Icons.filter_alt : Icons.filter_alt_off,
                        size: 20,
                      ),
                      onPressed: () => controller.toggleFilterBar(siteKey),
                      splashRadius: 20,
                    );
                  }),
                  Obx(() {
                    final mode = controller.cardLayoutMode.value;
                    return IconButton(
                      icon: Icon(mode.icon, size: 20),
                      onPressed: controller.toggleCardLayout,
                      tooltip: mode.label,
                      splashRadius: 20,
                    );
                  }),
                  IconButton(
                    icon: const Icon(Icons.expand_more, size: 20),
                    onPressed: () =>
                        _HomePageState._showAllCategoriesDialog(context),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  double _getTextWidth(BuildContext context, String text, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return textPainter.width.clamp(0.0, MediaQuery.of(context).size.width * 0.25);
  }
}

// ============================================================================
// 源切换弹窗内部组件
// ============================================================================

class _SourceSwitchDialogContent extends StatefulWidget {
  final List<Map<String, dynamic>> sites;
  final List<String> tagList;
  final String currentSiteKey;
  final void Function(Map<String, dynamic>) onSelectSite;

  const _SourceSwitchDialogContent({
    required this.sites,
    required this.tagList,
    required this.currentSiteKey,
    required this.onSelectSite,
  });

  @override
  State<_SourceSwitchDialogContent> createState() =>
      _SourceSwitchDialogContentState();
}

class _SourceSwitchDialogContentState extends State<_SourceSwitchDialogContent> {
  String _searchQuery = '';
  String _selectedTag = '全部';
  bool _isGridView = true;
  late ScrollController _scrollController;

  // ---- 存储键 ----
  String get _scrollOffsetKey => 'source_switch_scroll_${_isGridView ? 'grid' : 'list'}';
  String get _viewModeKey => 'source_switch_view_mode'; // 新增

  @override
  void initState() {
    super.initState();
    // 读取保存的视图模式
    _isGridView = GStorage.getSetting<bool>(_viewModeKey) ?? true;

    _scrollController = ScrollController();

    // 滚动监听
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final offset = _scrollController.position.pixels;
        GStorage.setSetting(_scrollOffsetKey, offset);
      }
    });

    // 恢复滚动位置
    final savedOffset = GStorage.getSetting<double>(_scrollOffsetKey) ?? 0.0;
    if (savedOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(savedOffset);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _switchView() {
    setState(() {
      _isGridView = !_isGridView;
      GStorage.setSetting(_viewModeKey, _isGridView); // 保存视图模式

      // 重建控制器（保持滚动监听和恢复逻辑）
      final oldController = _scrollController;
      _scrollController = ScrollController();
      _scrollController.addListener(() {
        if (_scrollController.hasClients) {
          final offset = _scrollController.position.pixels;
          GStorage.setSetting(_scrollOffsetKey, offset);
        }
      });
      oldController.dispose();

      // 恢复新视图的滚动位置
      final savedOffset = GStorage.getSetting<double>(_scrollOffsetKey) ?? 0.0;
      if (savedOffset > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(savedOffset);
          }
        });
      }
    });
  }

  List<Map<String, dynamic>> get _filteredSites {
    var list = widget.sites;
    if (_selectedTag != '全部') {
      list = list.where((site) {
        final name = site['name']?.toString() ?? '';
        return name.contains('[$_selectedTag]');
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((site) {
        final name = site['name']?.toString() ?? '';
        return name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // ---------- 顶部区域：搜索框 + 视图切换 ----------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                flex: 85,
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: '搜索源...',
                    hintStyle: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: colorScheme.onSurface.withOpacity(0.6),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              // 视图切换按钮（圆形）
              GestureDetector(
                onTap: _switchView,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    // 图标与当前视图对应：网格视图显示列表图标，列表视图显示网格图标
                    _isGridView ? Icons.list : Icons.grid_view,
                    size: 24,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ---------- 中部区域：筛选标签（水平滚动，默认无背景） ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildTagChip(
                  label: '全部',
                  isSelected: _selectedTag == '全部',
                  onTap: () {
                    setState(() {
                      _selectedTag = '全部';
                    });
                  },
                ),
                const SizedBox(width: 8),
                ...widget.tagList.map((tag) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildTagChip(
                      label: tag,
                      isSelected: _selectedTag == tag,
                      onTap: () {
                        setState(() {
                          _selectedTag = tag;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // ---------- 底部区域：列表 ----------
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _isGridView
                ? GridView.builder(
                    controller: _scrollController,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 3.8,
                      // mainAxisExtent: 50,
                    ),
                    itemCount: _filteredSites.length,
                    itemBuilder: (context, index) {
                      final site = _filteredSites[index];
                      return _buildSiteTile(site);
                    },
                  )
                : ListView.separated(
                    controller: _scrollController,
                    itemCount: _filteredSites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final site = _filteredSites[index];
                      return _buildSiteTile(site);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  // 构建标签芯片（大圆角胶囊，默认无背景）
  Widget _buildTagChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20), // 大圆角胶囊
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 构建单个站点列表项
  Widget _buildSiteTile(Map<String, dynamic> site) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final siteKey = site['key']?.toString() ?? '';
    final isCurrent = siteKey == widget.currentSiteKey;
    final name = site['name']?.toString() ?? '未命名';
    final searchable = site['searchable'] as int? ?? 0;

    final searchFilterService = Get.find<SearchFilterService>();
    final isSearchEnabled = searchFilterService.isSourceEnabled(siteKey);

    final isGrid = _isGridView;

    Color? backgroundColor;
    if (isGrid) {
      backgroundColor = isCurrent
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest;
    } else {
      backgroundColor = isCurrent ? colorScheme.primaryContainer : null;
    }

    Border? border;
    if (isGrid && isCurrent) {
      border = Border.all(
        color: colorScheme.primary,
        width: 1.5,
      );
    } else {
      border = Border.all(color: Colors.transparent, width: 1.5);
    }

    final bool canSearch = searchable != 0;

    return InkWell(
      onTap: () => widget.onSelectSite(site),
      borderRadius: BorderRadius.circular(10),
      hoverColor: colorScheme.primaryContainer.withOpacity(0.3),
      splashColor: colorScheme.primaryContainer.withOpacity(0.2),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: isGrid ? 6 : 10,   // 修改此处
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: border,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: canSearch
                  ? () {
                      searchFilterService.toggleSourceEnabled(
                        siteKey,
                        !isSearchEnabled,
                      );
                      setState(() {});
                    }
                  : null,
              icon: Icon(
                canSearch
                    ? (isSearchEnabled ? Icons.search : Icons.search_off)
                    : Icons.search_off,
                size: 18,
                color: canSearch
                    ? (isSearchEnabled
                        ? colorScheme.primary
                        : colorScheme.outline.withOpacity(0.5))
                    : colorScheme.outline.withOpacity(0.3),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              tooltip: canSearch
                  ? (isSearchEnabled ? '禁用搜索' : '启用搜索')
                  : '不支持搜索',
            ),
          ],
        ),
      ),
    );
  }
}
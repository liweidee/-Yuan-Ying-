import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/common/widgets/button/icon_button.dart';
import 'package:yuanying/common/widgets/flutter/refresh_indicator.dart' as custom;
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/common/widgets/video_card/video_card_h.dart';
import 'package:yuanying/common/skeleton/video_card_v.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/modules/home/controllers/category_controller.dart';
import 'package:yuanying/modules/home/views/category_page.dart';
import 'package:yuanying/modules/home/views/recommend_page.dart';
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
import 'package:yuanying/common/widgets/custom_height_widget.dart';
import 'package:yuanying/models/common/bar_hide_type.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  late final HomeController controller;
  late final SourceManager sourceManager;
  late final ActionRenderer actionRenderer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    controller = Get.put(HomeController());
    sourceManager = Get.find<SourceManager>();
    actionRenderer = Get.find<ActionRenderer>();
  }

  // 跳转详情
  void _navigateToDetail(VideoItem item) {
    // Action 卡片
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

    // 文件夹
    if (item.vodTag == 'folder') {
      final category = Category(
        typeId: item.vodId,
        typeName: item.vodName,
      );
      controller.switchCategory(category);
      return;
    }

    // 豆瓣/TMDB 源
    final site = sourceManager.currentSite.value;
    final siteName = site?['name']?.toString() ?? '';
    if (siteName.contains('豆瓣[官]') || siteName.contains('TMDB[官]')) {
      final filterService = Get.find<SearchFilterService>();
      List<String> sourceKeys;
      final bool onlyDefault = filterService.onlyDefaultSource.value;
      if (onlyDefault) {
        final currentKey = sourceManager.currentSite.value?['key']?.toString() ?? '';
        sourceKeys = currentKey.isNotEmpty ? [currentKey] : [];
      } else {
        sourceKeys = filterService.enabledSourceKeyList;
      }
      if (sourceKeys.isEmpty) {
        final currentKey = sourceManager.currentSite.value?['key']?.toString() ?? '';
        if (currentKey.isNotEmpty) sourceKeys = [currentKey];
      }
      if (sourceKeys.isEmpty) {
        SmartDialog.showToast('没有可用的搜索源');
        return;
      }
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

    // 普通视频
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.api_outlined,
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

  Widget _buildTopBarContent(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: _buildSourceInfo(theme)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.search, size: 22),
              onPressed: () => Get.toNamed(AppPages.search),
              splashRadius: 22,
            ),
            IconButton(
              icon: const Icon(Icons.send, size: 20),
              onPressed: _showPushDialog,
              splashRadius: 20,
            ),
            IconButton(
              icon: const Icon(Icons.history, size: 22),
              onPressed: () => Get.toNamed(AppPages.history),
              splashRadius: 22,
            ),
            IconButton(
              icon: const Icon(Icons.star_border, size: 22),
              onPressed: () => Get.toNamed(AppPages.favorite),
              splashRadius: 22,
            ),
          ],
        ),
      ],
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
          GestureDetector(
            onTap: _showSourceSwitchDialog,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 100,
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
                            final filePath = site['api']?.toString();
                            if (filePath != null && filePath.isNotEmpty) {
                              sourceManager.loadFileConfig(filePath, siteKey: key);
                            }
                          } else {
                            sourceManager.switchConfig(key);
                          }

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

  double _getTextWidth(BuildContext context, String text, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return textPainter.width.clamp(0.0, MediaQuery.of(context).size.width * 0.25);
  }

  Widget _buildNormalContent(ThemeData theme) {
    final mainController = Get.find<MainController>();
    final hideTopBar = controller.hideTopBar.value;
    const topBarHeight = 52.0;   

    // ===== 1. 构建顶部栏 =====
    Widget topBar = Container(
      height: topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      color: theme.colorScheme.surface,
      child: _buildTopBarContent(theme), // 原有的 Row 内容
    );

    // ===== 2. 如果启用隐藏，应用裁剪偏移 =====
    if (hideTopBar) {
      final offset = mainController.topBarOffset.value.clamp(0.0, topBarHeight);
      topBar = CustomHeightWidget(
        height: topBarHeight - offset,
        offset: Offset(0, -offset),
        child: topBar,
      );
    }

    // ===== 3. TabBar（分类栏） =====
    final categories = controller.categories;
    final siteKey = sourceManager.currentSite.value?['key'] ?? '';
    final showFilter = controller.getFilterVisibility(siteKey);

    Widget tabBar = Container(
      height: 46,
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TabBar(
              controller: controller.tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              indicatorColor: theme.colorScheme.primary,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 0.1,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              tabs: categories.map((item) => Tab(text: item.typeName)).toList(),
              onTap: (index) => controller.switchCategory(categories[index]),
            ),
          ),
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
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: Icon(showFilter ? Icons.filter_alt : Icons.filter_alt_off, size: 20),
                    onPressed: () => controller.toggleFilterBar(siteKey),
                    splashRadius: 20,
                  );
                }),
                const SizedBox(width: 4),
                Obx(() {
                  final mode = controller.cardLayoutMode.value;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: Icon(mode.icon, size: 20),
                    onPressed: controller.toggleCardLayout,
                    tooltip: mode.label,
                    splashRadius: 20,
                  );
                }),
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  icon: const Icon(Icons.expand_more, size: 20),
                  onPressed: () => _showAllCategoriesDialog(context),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // 判断当前分类是否有筛选（用于间距）
    final currentCategory = controller.currentCategory.value;
    final hasFilter = currentCategory != null &&
        controller.filters.containsKey(currentCategory.typeId) &&
        controller.filters[currentCategory.typeId]!.isNotEmpty;

    // ===== 4. TabBarView 内容 =====
    Widget tabView = TabBarView(
      controller: controller.tabController!,
      children: categories.map((category) {
        if (category.typeId == 'recommend') {
          return RecommendPage(
            data: controller.recommendList,
            onVideoTap: _navigateToDetail,
          );
        }
        final ctrl = controller.getOrCreateController(category.typeId);
        return CategoryPage(
          controller: ctrl!,
          onVideoTap: _navigateToDetail,
        );
      }).toList(),
    );

    // ===== 5. 组合布局 =====
    return Column(
      children: [
        topBar,
        tabBar,
        if (!hasFilter) const SizedBox(height: 8),
        Expanded(child: tabView),
      ],
    );
  }

  void _showAllCategoriesDialog(BuildContext context) {
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
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      child: Icon(Icons.close, size: 20, color: colorScheme.outline),
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

  Widget _buildTopBar(ThemeData theme) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      color: theme.colorScheme.surface,
      child: _buildTopBarContent(theme),
    );
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
            return _buildConfigError(theme);
          }

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

          if (sourceManager.sites.isEmpty) {
            return _buildEmptyConfig(theme);
          }

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

          return _buildNormalContent(theme);
        }),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ===== 源切换弹窗内部组件 =====

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

  String get _scrollOffsetKey => 'source_switch_scroll_${_isGridView ? 'grid' : 'list'}';
  String get _viewModeKey => 'source_switch_view_mode';

  @override
  void initState() {
    super.initState();
    _isGridView = GStorage.getSetting<bool>(_viewModeKey) ?? true;
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final offset = _scrollController.position.pixels;
        GStorage.setSetting(_scrollOffsetKey, offset);
      }
    });
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
      GStorage.setSetting(_viewModeKey, _isGridView);
      final oldController = _scrollController;
      _scrollController = ScrollController();
      _scrollController.addListener(() {
        if (_scrollController.hasClients) {
          final offset = _scrollController.position.pixels;
          GStorage.setSetting(_scrollOffsetKey, offset);
        }
      });
      oldController.dispose();
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
        // ---------- 搜索框 ----------
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
                    _isGridView ? Icons.list : Icons.grid_view,
                    size: 24,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ---------- 筛选标签 ----------
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

        // ---------- 列表区域 ----------
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: _isGridView
                ? CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 8,
                          childAspectRatio: 3.2,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final site = _filteredSites[index];
                            return _buildSiteTile(site);
                          },
                          childCount: _filteredSites.length,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    controller: _scrollController,
                    itemCount: _filteredSites.length,
                    padding: EdgeInsets.zero,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
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
          borderRadius: BorderRadius.circular(20),
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

    // 统一高度：单栏和双栏视觉一致
    final verticalPadding = isGrid ? 10.0 : 8.0;

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
          vertical: verticalPadding, // 统一高度
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
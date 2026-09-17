import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import '../controllers/fnos_search_controller.dart';
import '../controllers/fnos_server_controller.dart';
import '../models/fnos_media_item.dart';
import '../services/fnos_api_service.dart';
import '../widgets/fnos_media_card.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class FnosSearchPage extends StatefulWidget {
  const FnosSearchPage({super.key});

  @override
  State<FnosSearchPage> createState() => _FnosSearchPageState();
}

class _FnosSearchPageState extends State<FnosSearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  late final FnosSearchController ctrl;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<FnosSearchController>()) {
      Get.put(FnosSearchController());
    }
    ctrl = Get.find<FnosSearchController>();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // ===== 搜索框 =====
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            autofocus: false,
            textInputAction: TextInputAction.search,
            onChanged: ctrl.onKeywordChanged,
            decoration: InputDecoration(
              hintText: '搜索片名、演员',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: Obx(() {
                if (ctrl.keyword.value.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    ctrl.clear();
                  },
                );
              }),
              filled: true,
              fillColor: colorScheme.surfaceVariant.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              isDense: true,
            ),
          ),
        ),

        // ===== 分类 Tab =====
        Obx(() {
          if (ctrl.rawResults.isEmpty) return const SizedBox.shrink();
          final current = ctrl.selectedTabIndex.value;
          return Container(
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: FnosSearchController.tabs.length,
              itemBuilder: (_, i) {
                final isSelected = i == current;
                // 该 Tab 下是否有结果
                final hasInTab = i == 0
                    ? ctrl.rawResults.isNotEmpty
                    : _hasInTab(ctrl.rawResults, FnosSearchController.tabs[i]);
                if (!hasInTab) return const SizedBox.shrink();

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: InkWell(
                    onTap: () => ctrl.switchTab(i),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        FnosSearchController.tabs[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }),

        // ===== 内容区 =====
        Expanded(
          child: Obx(() {
            final kw = ctrl.keyword.value;

            // 初始态
            if (kw.trim().isEmpty) {
              return _buildInitialState(colorScheme);
            }

            // 加载中
            if (ctrl.isLoading.value && ctrl.rawResults.isEmpty) {
              return _loadingWidget;
            }

            // 错误
            if (ctrl.error.value.isNotEmpty && ctrl.rawResults.isEmpty) {
              return _buildError(ctrl.error.value, colorScheme);
            }

            // 无结果
            if (ctrl.rawResults.isEmpty) {
              return _buildNoResult(colorScheme);
            }

            // 结果网格
            final items = ctrl.filteredResults;
            if (items.isEmpty) {
              return _buildNoResult(colorScheme);
            }
            return _buildResultGrid(items, colorScheme);
          }),
        ),
      ],
    );
  }

  bool _hasInTab(List<FnosPlayListItem> list, String tab) {
    for (final item in list) {
      final t = item.type ?? '';
      switch (tab) {
        case '电影':
          if (t == 'Movie') return true;
          break;
        case '电视剧':
          if (t == 'TV' || t == 'Season' || t == 'Episode') return true;
          break;
        case '电视直播':
          if (t == 'LiveChannel') return true;
          break;
        case '人物':
          if (t == 'Person') return true;
          break;
        case '其他':
          if (t != 'Movie' &&
              t != 'TV' &&
              t != 'Season' &&
              t != 'Episode' &&
              t != 'LiveChannel' &&
              t != 'Person') {
            return true;
          }
          break;
      }
    }
    return false;
  }

  Widget _buildInitialState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_rounded,
            size: 64,
            color: colorScheme.outline.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '输入关键词开始搜索',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '支持片名、演员名',
            style: TextStyle(
              color: colorScheme.outline,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResult(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: colorScheme.outline.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '未找到相关内容',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: ctrl.retry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultGrid(
    List<FnosPlayListItem> items,
    ColorScheme colorScheme,
  ) {
    final serverCtrl = Get.find<FnosServerController>();
    final server = serverCtrl.currentServer;
    if (server == null) return _loadingWidget;

    final token = serverCtrl.getToken(server.id);
    final headers = FnosApiService().imageHeaders(token: token);

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1200
        ? 6
        : screenWidth > 800
            ? 5
            : screenWidth > 600
                ? 4
                : 3;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.55,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final imageUrl = FnosApiService.imageUrl(
          server.baseUrl,
          item.poster ?? '',
          width: 300,
        );
        return FnosMediaCard(
          item: item,
          imageUrl: imageUrl,
          headers: headers,
          onTap: () => _onItemTap(item),
        );
      },
    );
  }

  // ============================================================
  // 点击结果 → 跳转
  // ============================================================
  void _onItemTap(FnosPlayListItem item) {
    final type = item.type ?? '';

    // 人物：暂不支持详情页
    if (type == 'Person') {
      SmartDialog.showToast('暂不支持查看人物详情');
      return;
    }

    // 直播频道：直接播放
    if (type == 'LiveChannel') {
      Get.toNamed(
        AppPages.fnosDetail,
        arguments: {'itemGuid': item.guid},
      );
      return;
    }

    // 剧集 / 季 / 集：跳父级或自身
    String guid = item.guid;
    if ((type == 'Episode' || type == 'Season') &&
        item.parentGuid != null &&
        item.parentGuid!.isNotEmpty) {
      guid = item.parentGuid!;
    }

    // 电影 / 电视剧 / 视频 / 文件夹 → 详情页
    Get.toNamed(
      AppPages.fnosDetail,
      arguments: {
        'itemGuid': guid,
        'initialEpisodeGuid': type == 'Episode' ? item.guid : null,
        'poster': item.poster,
        'title': item.title,
        'tvTitle': item.tvTitle,
        'type': item.type,
        'overview': item.overview,
      },
    );
  }
}
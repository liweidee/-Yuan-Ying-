// lib/modules/video/widgets/search_tab.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/controllers/video_search_controller.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/modules/action/widgets/action_renderer.dart';

class SearchTab extends StatefulWidget {
  final String controllerTag;
  const SearchTab({super.key, required this.controllerTag});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late final DetailSearchController _searchController;
  late final DetailController _detailController;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _detailController = Get.find<DetailController>(tag: widget.controllerTag);

    final controllerTag = 'detail_search_${widget.controllerTag}';
    if (Get.isRegistered<DetailSearchController>(tag: controllerTag)) {
      _searchController = Get.find<DetailSearchController>(tag: controllerTag);
    } else {
      _searchController = Get.put(DetailSearchController(), tag: controllerTag);
    }

    final detail = _detailController.introController.videoDetail.value;
    final name = detail?.vodName ?? '';
    _textController.text = name;
    _searchController.keyword.value = name;

    _textController.addListener(() {
      if (_searchController.keyword.value != _textController.text) {
        _searchController.keyword.value = _textController.text;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (name.isNotEmpty) {
        _searchController.search(name);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _textController.text.trim();
    if (query.isEmpty) {
      SmartDialog.showToast('请输入搜索关键词');
      return;
    }
    _focusNode.unfocus();
    _searchController.search(query);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(context, colorScheme),
        const SizedBox(height: 8),
        _buildSourceChips(colorScheme),
        const SizedBox(height: 8),
        Expanded(child: _buildResultList(colorScheme)),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, size: 20, color: colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: '搜索视频...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _onSearch(),
                    ),
                  ),
                  Obx(() {
                    if (_searchController.keyword.value.isNotEmpty) {
                      return IconButton(
                        icon: Icon(Icons.clear, size: 18, color: colorScheme.outline),
                        onPressed: () {
                          _textController.clear();
                          _searchController.keyword.value = '';
                          _focusNode.requestFocus();
                        },
                      );
                    }
                    return const SizedBox(width: 4);
                  }),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: _onSearch,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.primary,
                child: Icon(Icons.search, size: 22, color: colorScheme.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChips(ColorScheme colorScheme) {
    final tag = 'detail_search_${widget.controllerTag}';

    return Obx(() {
      final controller = Get.find<DetailSearchController>(tag: tag);
      final allKeys = controller.sourceKeys;

      // 获取当前选中的 key（直接访问，让 GetX 追踪）
      final currentKey = controller.currentSourceKey.value;

      // 过滤：只显示有搜索结果（count > 0）的源
      final filteredKeys = controller.isLoading.value
          ? allKeys
          : allKeys.where((key) => controller.getCurrentCount(key) > 0).toList();

      if (filteredKeys.isEmpty) {
        if (controller.isLoading.value) {
          return const SizedBox(
            height: 36,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return const SizedBox(
          height: 36,
          child: Center(
            child: Text(
              '所有源均无搜索结果',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        );
      }

      return SizedBox(
        height: 36,
        child: Center(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: filteredKeys.length,
            itemBuilder: (context, index) {
              final key = filteredKeys[index];
              // 直接比较，确保选中状态准确
              final isSelected = currentKey == key;
              final count = controller.getCurrentCount(key);
              final name = controller.getSourceName(key);
              final label = count > 0 ? '$name ($count)' : name;

              return GestureDetector(
                onTap: () => controller.switchSource(key),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(maxWidth: 160),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  Widget _buildResultList(ColorScheme colorScheme) {
    final tag = 'detail_search_${widget.controllerTag}';

    return Obx(() {
      final controller = Get.find<DetailSearchController>(tag: tag);

      if (controller.isLoading.value && controller.currentItems.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.isError.value) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(controller.errorMsg.value, style: TextStyle(color: colorScheme.outline)),
              TextButton(
                onPressed: controller.refreshCurrent,
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }

      if (controller.currentItems.isEmpty) {
        return Center(
          child: Text('暂无搜索结果', style: TextStyle(color: colorScheme.outline)),
        );
      }

      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
          childAspectRatio: 0.65,
        ),
        itemCount: controller.currentItems.length,
        itemBuilder: (context, index) {
          final item = controller.currentItems[index];
          return VideoCardV(
            videoItem: item,
            onTap: () => _navigateToDetail(item),
          );
        },
      );
    });
  }

  void _navigateToDetail(VideoItem item) {
    final sourceKey = item.vodTag;
    final sourceManager = Get.find<SourceManager>();

    if (item.isAction) {
      final config = item.actionConfig;
      if (config != null) {
        final renderer = Get.find<ActionRenderer>();
        renderer.showAction(
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

    if (item.vodTag == 'folder') {
      SmartDialog.showToast('请在首页切换分类');
      return;
    }

    Map<String, dynamic>? targetSite;
    String? apiUrl;
    String pwd = 'tinydust';

    if (sourceKey != null && sourceKey.isNotEmpty) {
      targetSite = sourceManager.sites.firstWhere(
        (s) => s['key']?.toString() == sourceKey,
        orElse: () => {},
      );
      if (targetSite.isNotEmpty) {
        apiUrl = targetSite['api']?.toString();
        final ext = targetSite['ext'];
        if (ext is Map && ext['pwd'] != null) {
          pwd = ext['pwd'].toString();
        }
      }
    }

    if (targetSite == null || targetSite.isEmpty) {
      final current = sourceManager.currentSite.value;
      if (current != null) {
        targetSite = current;
        apiUrl = current['api']?.toString();
        final ext = current['ext'];
        if (ext is Map && ext['pwd'] != null) {
          pwd = ext['pwd'].toString();
        }
      }
    }

    if (apiUrl == null || apiUrl.isEmpty) {
      SmartDialog.showToast('无法获取播放源');
      return;
    }

    final tag = DetailController.generateTag(prefix: 'detail_search');
    Get.toNamed(
      '/detail',
      arguments: {
        'vodId': item.vodId,
        'pwd': pwd,
        'apiUrl': apiUrl,
        '_controllerTag': tag,
        if (targetSite != null && targetSite.isNotEmpty) 'site': targetSite,
      },
      preventDuplicates: false,
    );
  }
}
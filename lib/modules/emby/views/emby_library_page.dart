import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/loading_widget/m3e_loading_indicator.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/utils/emby_converter.dart';
import '../controllers/emby_library_controller.dart';
import '../services/emby_api_service.dart';

const Widget _loadingWidget = Center(child: M3ELoadingIndicator());

class EmbyLibraryPage extends StatelessWidget {
  const EmbyLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = Get.arguments as Map<String, dynamic>;
    final libraryId = args['libraryId'] as String;
    final libraryName = args['libraryName'] as String;
    /// 接收 collectionType
    final collectionType = args['collectionType'] as String?;

    if (!Get.isRegistered<EmbyLibraryController>(tag: libraryId)) {
      Get.put(
        EmbyLibraryController(
          libraryId: libraryId,
          libraryName: libraryName,
          collectionType: collectionType, // ← 传入
        ),
        tag: libraryId,
      );
    }
    final ctrl = Get.find<EmbyLibraryController>(tag: libraryId);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(libraryName),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: _EmbyLibrarySearchDelegate(ctrl),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: (value) {
              final parts = value.split(':');
              ctrl.setSort(parts[0], parts[1]);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'SortName:Ascending', child: Text('名称 (A-Z)')),
              const PopupMenuItem(
                  value: 'SortName:Descending', child: Text('名称 (Z-A)')),
              const PopupMenuItem(
                  value: 'DateCreated:Descending', child: Text('最新添加')),
              const PopupMenuItem(
                  value: 'DateCreated:Ascending', child: Text('最早添加')),
              const PopupMenuItem(
                  value: 'CommunityRating:Descending', child: Text('评分最高')),
              const PopupMenuItem(
                  value: 'CommunityRating:Ascending', child: Text('评分最低')),
              const PopupMenuItem(
                  value: 'ProductionYear:Descending', child: Text('年份最新')),
              const PopupMenuItem(
                  value: 'ProductionYear:Ascending', child: Text('年份最旧')),
              const PopupMenuItem(
                  value: 'Random:Ascending', child: Text('随机')),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoading.value && ctrl.items.isEmpty) {
          return _loadingWidget;
        }
        if (ctrl.error.isNotEmpty && ctrl.items.isEmpty) {
          return Center(
            child: Text(ctrl.error.value,
                style: TextStyle(color: theme.colorScheme.error)),
          );
        }
        final items = ctrl.items;
        if (items.isEmpty) {
          return Center(
            child: Text('暂无内容',
                style: TextStyle(color: theme.colorScheme.outline)),
          );
        }
        final server = ctrl.serverController.currentServer!;

        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount =
            screenWidth > 800 ? 5 : screenWidth > 600 ? 4 : 3;

        return GridView.builder(
          controller: ctrl.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.6,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: items.length + (ctrl.hasMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final item = items[index];
            final imageUrl = EmbyApiService.displayPoster(
              server.baseUrl,
              item,
              maxWidth: 300,
              apiKey: ctrl.serverController.getToken(server.id),
            );
            final videoItem = EmbyConverter.toVideoItem(item, imageUrl);
            return VideoCardV(
              videoItem: videoItem,
              onTap: () => Get.toNamed(AppPages.embyDetail,
                  arguments: {'itemId': item.id}),
            );
          },
        );
      }),
    );
  }
}

class _EmbyLibrarySearchDelegate extends SearchDelegate {
  final EmbyLibraryController ctrl;
  _EmbyLibrarySearchDelegate(this.ctrl);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          query = '';
          ctrl.searchKeyword.value = '';
        },
        icon: const Icon(Icons.clear),
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    ctrl.searchKeyword.value = query;
    return Container();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return const SizedBox.shrink();
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/utils/emby_converter.dart';
import '../controllers/emby_search_controller.dart';
import '../services/emby_api_service.dart';

class EmbySearchPage extends StatelessWidget {
  const EmbySearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EmbySearchController>()) {
      Get.put(EmbySearchController());
    }
    final ctrl = Get.find<EmbySearchController>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // 搜索框（带防抖）
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索媒体...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
              onChanged: (value) {
                // 防抖 500ms
                ctrl.search(value);
              },
              autofocus: true,
            ),
          ),
          // 结果区域
          Expanded(
            child: Obx(() {
              if (ctrl.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (ctrl.error.isNotEmpty) {
                return Center(
                  child: Text(ctrl.error.value, style: TextStyle(color: theme.colorScheme.error)),
                );
              }
              if (ctrl.keyword.isEmpty) {
                return Center(
                  child: Text('输入关键词开始搜索', style: TextStyle(color: theme.colorScheme.outline)),
                );
              }
              if (ctrl.results.isEmpty) {
                return Center(
                  child: Text('未找到相关内容', style: TextStyle(color: theme.colorScheme.outline)),
                );
              }
              // 使用网格展示
              final server = ctrl.serverController.currentServer!;
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = screenWidth > 800 ? 5 : screenWidth > 600 ? 4 : 3;
              return GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 0.6,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: ctrl.results.length,
                itemBuilder: (context, index) {
                  final item = ctrl.results[index];
                  final imageUrl = EmbyApiService.primaryImage(server.baseUrl, item.id, maxWidth: 300);
                  final videoItem = EmbyConverter.toVideoItem(item, imageUrl);
                  return VideoCardV(
                    videoItem: videoItem,
                    onTap: () => Get.toNamed(AppPages.embyDetail, arguments: {'itemId': item.id}),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
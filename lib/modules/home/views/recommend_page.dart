import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/utils/grid.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/common/widgets/video_card/video_card_h.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';

/// 推荐分类页面
///
/// 特点：
/// - 无下拉刷新（RefreshIndicator）
/// - 无加载更多（loadMore）
/// - 数据来自 HomeController.recommendList（由 fetchHome 接口返回）
/// - 支持布局模式切换（网格/列表）
/// - 滚动时自动隐藏顶部/底部栏
class RecommendPage extends StatefulWidget {
  final List<VideoItem> data;
  final Function(VideoItem) onVideoTap;

  const RecommendPage({
    Key? key,
    required this.data,
    required this.onVideoTap,
  }) : super(key: key);

  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  late final ScrollController _scrollController;
  final MainController _mainController = Get.find<MainController>();

  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollUpdate);
  }

  void _onScrollUpdate() {
    final offset = _scrollController.position.pixels;
    if (offset == _lastScrollOffset) return;
    final isDown = offset > _lastScrollOffset;
    _lastScrollOffset = offset;

    _mainController.updateTopBarOffset(offset, isScrollingDown: isDown);
    _mainController.updateBottomBarOffset(offset, isScrollingDown: isDown);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final mode = Get.find<HomeController>().cardLayoutMode.value;

      if (widget.data.isEmpty) {
        return Center(
          child: Text(
            '暂无推荐数据',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 14,
            ),
          ),
        );
      }

      // 列表模式
      if (Grid.isListMode(mode)) {
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: widget.data.length,
          itemBuilder: (context, index) {
            final item = widget.data[index];
            return VideoCardH(
              videoItem: item,
              onTap: () => widget.onVideoTap(item),
            );
          },
        );
      }

      // 网格模式
      final gridDelegate = Grid.videoCardVDelegate(
        context,
        mode: mode,
        minHeight: 25,
      );
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 100),
        gridDelegate: gridDelegate,
        itemCount: widget.data.length,
        itemBuilder: (context, index) {
          final item = widget.data[index];
          return VideoCardV(
            videoItem: item,
            onTap: () => widget.onVideoTap(item),
          );
        },
      );
    });
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/utils/grid.dart';
import 'package:yuanying/common/widgets/video_card/video_card_v.dart';
import 'package:yuanying/common/widgets/video_card/video_card_h.dart';
import 'package:yuanying/t4/models/video_item.dart';
import 'package:yuanying/models/common/card_layout_mode.dart';
import 'package:yuanying/modules/home/controllers/home_controller.dart';

/// 推荐分类页面
/// 无下拉刷新，无加载更多，数据来自 HomeController.recommendList
/// 滚动由父级 HomePage 的 CommonPageState 统一处理，本页面无需额外监听
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

class _RecommendPageState extends State<RecommendPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用
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
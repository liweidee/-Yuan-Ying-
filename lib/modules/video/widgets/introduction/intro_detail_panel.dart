import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:yuanying/common/widgets/search_text.dart';
import 'package:yuanying/t4/models/video_detail.dart';
import 'package:yuanying/utils/utils.dart';

/// 简介详情弹窗
class IntroDetailPanel extends StatefulWidget {
  final VideoDetail detail;
  final String sourceName;
  final String controllerTag;

  const IntroDetailPanel({
    super.key,
    required this.detail,
    required this.sourceName,
    required this.controllerTag,
  });

  @override
  State<IntroDetailPanel> createState() => _IntroDetailPanelState();
}

class _IntroDetailPanelState extends State<IntroDetailPanel>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 处理标签（用逗号分隔）
    final tags = widget.detail.vodTag?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [];

    return Container(
      color: colorScheme.surface,  // ← 移除圆角，直接使用纯色背景
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 左侧：TabBar（只有一个"详情"Tab）
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  dividerHeight: 0,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  indicatorColor: colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,  // ← 关键：下划线与文字等宽
                  indicatorWeight: 2,
                  tabs: const [
                    Tab(text: '详情'),
                  ],
                ),
              ),
              // 右侧：关闭按钮
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 2),
            ],
          ),
          // ===== 注意：无分割线（dividerHeight: 0 已生效） =====

          // ===== 内容区域 =====
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInfo(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tags = widget.detail.vodTag?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
      ),
      children: [
        // 标题
        SelectableText(
          widget.detail.vodName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 4),

        // 来源名称
        Text(
          widget.sourceName,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),

        // 标签
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((tag) {
              return SearchText(
                text: tag,
                fontSize: 13,
                onTap: (text) {
                  Get.toNamed(
                    '/searchResult',
                    parameters: {'keyword': text},
                  );
                },
                onLongPress: Utils.copyText,
              );
            }).toList(),
          ),
        ],

        // 简介
        if (widget.detail.vodContent?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          Text(
            '简介：',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            widget.detail.vodContent!,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ],
    );
  }
}
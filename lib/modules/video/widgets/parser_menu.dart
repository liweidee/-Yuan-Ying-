import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/services/parser_service.dart';

/// 解析源选择弹窗
class ParserMenu extends StatelessWidget {
  const ParserMenu({super.key});

  static void show(String controllerTag) {
    final controller = Get.find<DetailController>(tag: controllerTag);

    final parsers = controller.parserSources;
    if (parsers.isEmpty) {
      SmartDialog.showToast('暂无可用解析源');
      return;
    }

    showModalBottomSheet(
      context: Get.context!,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        final theme = Theme.of(context);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
              height: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '解析接口',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: parsers.length,
                      itemBuilder: (context, index) {
                        final parser = parsers[index];
                        final isSelected =
                            controller.currentParser.value?.name == parser.name;

                        return ListTile(
                          dense: true,
                          onTap: () {
                            Navigator.pop(context);
                            controller.switchParser(parser);
                          },
                          title: Text(
                            parser.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check,
                                  size: 20,
                                  color: colorScheme.primary,
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
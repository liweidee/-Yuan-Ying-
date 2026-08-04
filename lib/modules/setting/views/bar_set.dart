import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/models/common/enum_with_label.dart';
import 'package:yuanying/modules/main/controllers/main_controller.dart';
import 'package:yuanying/modules/setting/models/setting_pref.dart';
import 'package:yuanying/utils/storage_manager.dart';

class BarSetPage extends StatefulWidget {
  const BarSetPage({super.key});

  @override
  State<BarSetPage> createState() => _BarSetPageState();
}

class _BarSetPageState extends State<BarSetPage> {
  late final String key;
  late final String title;
  late final List<({EnumWithLabel item, bool enabled})> list;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> args = Get.arguments;
    key = args['key'];
    title = args['title'];
    final List? cache = StorageManager.getSetting<List>(key);
    final defaultBars = args['defaultBars'] as List;
    list = defaultBars
        .map((e) => (
              item: e as EnumWithLabel,
              enabled: cache?.contains((e as Enum).index) ?? true,
            ))
        .toList();
    if (cache != null && cache.isNotEmpty) {
      final cacheIndex = {for (final (k, v) in cache.indexed) v: k};
      list.sort((a, b) {
        final indexA = cacheIndex[(a.item as Enum).index] ?? cacheIndex.length;
        final indexB = cacheIndex[(b.item as Enum).index] ?? cacheIndex.length;
        return indexA.compareTo(indexB);
      });
    }
  }

  void saveEdit() {
    final List<int> sorted = list
        .where((e) => e.enabled)
        .map((e) => (e.item as Enum).index)
        .toList();
    StorageManager.setSetting(key, sorted);
    // ===== 修复：通知 MainController 刷新导航栏 =====
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().setNavBarConfig();
    }
    SmartDialog.showToast('保存成功，下次启动时生效');
  }

  void onReset() {
    Get.back();
    StorageManager.deleteSetting(key);
    // ===== 修复：通知 MainController 刷新导航栏 =====
    if (Get.isRegistered<MainController>()) {
      Get.find<MainController>().setNavBarConfig();
    }
    SmartDialog.showToast('重置成功，下次启动时生效');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('$title编辑'),
        actions: [
          TextButton(onPressed: onReset, child: const Text('重置')),
          TextButton(onPressed: saveEdit, child: const Text('保存')),
          const SizedBox(width: 12),
        ],
      ),
      body: ReorderableListView(
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex--;
          final item = list.removeAt(oldIndex);
          list.insert(newIndex, item);
          setState(() {});
        },
        padding: const EdgeInsets.symmetric(vertical: 8),
        footer: Padding(
          padding: const EdgeInsets.only(right: 34, top: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '*长按拖动排序',
              style: TextStyle(color: colorScheme.outline, fontSize: 12),
            ),
          ),
        ),
        children: list
            .map(
              (e) => CheckboxListTile(
                key: ValueKey(e.item.hashCode),
                value: e.enabled,
                onChanged: (bool? value) {
                  final index = list.indexOf(e);
                  list[index] = (item: e.item, enabled: value ?? true);
                  setState(() {});
                },
                title: Text(e.item.label),
                secondary: const Icon(Icons.drag_indicator_rounded),
              ),
            )
            .toList(),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:yuanying/modules/danmaku/controllers/danmaku_controller.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';

class DanmakuBlockPage extends StatefulWidget {
  const DanmakuBlockPage({super.key});

  @override
  State<DanmakuBlockPage> createState() => _DanmakuBlockPageState();
}

class _DanmakuBlockPageState extends State<DanmakuBlockPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtr;

  final RxList<String> _keywords = <String>[].obs;
  final RxList<String> _regexes = <String>[].obs;

  @override
  void initState() {
    super.initState();
    _tabCtr = TabController(length: 2, vsync: this);
    _keywords.assignAll(PlayerPref.danmakuFilterKeywords);
    _regexes.assignAll(PlayerPref.danmakuFilterRegexes);
  }

  @override
  void dispose() {
    _tabCtr.dispose();
    super.dispose();
  }

  void _persist() {
    PlayerPref.danmakuFilterKeywords = _keywords.toList();
    PlayerPref.danmakuFilterRegexes = _regexes.toList();
    // 通知正在播放的弹幕控制器刷新屏蔽规则
    if (Get.isRegistered<DanmakuController>()) {
      Get.find<DanmakuController>().reloadFilter();
    }
  }

  Future<void> _showAddDialog(int tabIndex) async {
    final isRegex = tabIndex == 1;
    final hint = isRegex
        ? '输入正则表达式，无需包含头尾的 "/"，例如：^666'
        : '输入要屏蔽的关键词，例如：广告';

    final textCtr = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRegex ? '添加正则' : '添加关键词'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: textCtr,
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = textCtr.text.trim();
              if (v.isEmpty) {
                SmartDialog.showToast('内容不能为空');
                return;
              }
              if (isRegex) {
                try {
                  RegExp(v);
                } catch (e) {
                  SmartDialog.showToast('正则表达式无效');
                  return;
                }
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final v = textCtr.text.trim();
    if (v.isEmpty) return;

    if (isRegex) {
      if (_regexes.contains(v)) {
        SmartDialog.showToast('规则已存在');
        return;
      }
      _regexes.add(v);
    } else {
      if (_keywords.contains(v)) {
        SmartDialog.showToast('规则已存在');
        return;
      }
      _keywords.add(v);
    }
    _persist();
  }

  Future<void> _showEditDialog(int tabIndex, int index) async {
    final isRegex = tabIndex == 1;
    final list = isRegex ? _regexes : _keywords;
    final initialValue = list[index];

    final hint = isRegex
        ? '输入正则表达式，无需包含头尾的 "/"，例如：^666'
        : '输入要屏蔽的关键词，例如：广告';

    final textCtr = TextEditingController(text: initialValue);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRegex ? '编辑正则' : '编辑关键词'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: textCtr,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = textCtr.text.trim();
              if (v.isEmpty) {
                SmartDialog.showToast('内容不能为空');
                return;
              }
              if (isRegex) {
                try {
                  RegExp(v);
                } catch (_) {
                  SmartDialog.showToast('正则表达式无效');
                  return;
                }
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final v = textCtr.text.trim();
    if (v.isEmpty) return;
    if (v == initialValue) return;            // 未修改
    if (list.contains(v)) {                   // 与其它规则重名
      SmartDialog.showToast('规则已存在');
      return;
    }
    list[index] = v;
    _persist();
  }

  void _delete(int tabIndex, int index) {
    if (tabIndex == 0) {
      _keywords.removeAt(index);
    } else {
      _regexes.removeAt(index);
    }
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕屏蔽')),
      body: Column(
        children: [
          TabBar(
            controller: _tabCtr,
            tabs: [
              Obx(() => Tab(text: '关键词(${_keywords.length})')),
              Obx(() => Tab(text: '正则(${_regexes.length})')),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtr,
              children: [
                _buildList(0, _keywords),
                _buildList(1, _regexes),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加',
        onPressed: () => _showAddDialog(_tabCtr.index),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(int tabIndex, RxList<String> items) {
    final cs = Theme.of(context).colorScheme;
    return Obx(() {
      if (items.isEmpty) {
        return Center(
          child: Text(
            tabIndex == 0 ? '暂无屏蔽关键词' : '暂无屏蔽正则',
            style: TextStyle(color: cs.outline),
          ),
        );
      }
      return ListView.builder(
        itemCount: items.length,
        padding: const EdgeInsets.only(bottom: 100),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text(item),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _showEditDialog(tabIndex, index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(tabIndex, index),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
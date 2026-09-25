import 'package:flutter/material.dart';

import 'lx_download_tab.dart';

/// 独立的下载管理页（供从其他入口跳转使用）
///
/// 主入口现在走底部导航的「下载 Tab」（LxDownloadTab），
/// 这个页面仅作为独立路由入口保留。
class LxDownloadPage extends StatelessWidget {
  const LxDownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理', style: TextStyle(fontSize: 18)),
      ),
      body: const LxDownloadTab(),
    );
  }
}
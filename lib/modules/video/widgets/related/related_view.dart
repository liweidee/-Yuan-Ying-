import 'package:flutter/material.dart';

/// 推荐区域（占位）
class RelatedView extends StatelessWidget {
  const RelatedView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '推荐功能开发中',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
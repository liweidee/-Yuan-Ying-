import 'dart:convert';

import 'package:json5/json5.dart';

import 'package:yuanying/modules/novel/models/novel_chapter_content.dart';
import 'package:yuanying/modules/novel/utils/purify.dart';
import 'package:yuanying/t4/services/i_spider_service.dart';
import 'package:yuanying/utils/business_exception.dart';
import 'package:yuanying/utils/storage_manager.dart';

class NovelChapterContentService {
  final ISpiderService apiService;
  final String sourceName;
  final String pwd;
  final String apiUrl;

  const NovelChapterContentService({
    required this.apiService,
    required this.sourceName,
    required this.pwd,
    required this.apiUrl,
  });

  Future<NovelChapterContent> load({
    required int chapterIndex,
    required String vodId,
    required String playParams,
    required String separator,
    required List<Map<String, dynamic>> purifyRules,
  }) async {
    final cacheKey = StorageManager.sourceScopedKey(
      'novel_chapter_${vodId}_$chapterIndex',
      apiUrl,
    );
    var text = StorageManager.getCache<String>(cacheKey) ?? '';
    if (text.isEmpty) {
      final playUrl = await apiService.getPlayUrl(
        playParams: playParams,
        flag: sourceName,
        pwd: pwd,
      );
      if (playUrl == null) {
        throw const BusinessException('获取播放地址失败');
      }
      final url = playUrl.defaultUrl;
      if (url == null || url.isEmpty) {
        throw const BusinessException('播放地址为空');
      }
      if (!url.startsWith('novel://')) {
        throw const BusinessException('不支持该协议');
      }
      final cleaned = _cleanJsonString(url.substring(7));
      Map<String, dynamic>? data;
      try {
        data = JSON5.parse(cleaned) as Map<String, dynamic>;
      } catch (e) {
        throw BusinessException('解析章节内容失败：$e');
      }
      text =
          data['content']?.toString() ??
          data['body']?.toString() ??
          data['text']?.toString() ??
          '';
      if (text.isEmpty) {
        throw const BusinessException('章节内容为空');
      }
      await StorageManager.setCache(cacheKey, text);
    }
    if (purifyRules.isNotEmpty) {
      text = applyReplaceRules(text, jsonEncode(purifyRules));
    }
    return NovelChapterContent.fromText(
      chapterIndex: chapterIndex,
      text: text,
      separator: separator,
    );
  }

  String _cleanJsonString(String raw) {
    var value = raw.trim();
    while (value.startsWith('/') || value.startsWith(r'\')) {
      value = value.substring(1);
    }
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
}

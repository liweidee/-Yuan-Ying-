// lib/modules/agent_llm/services/agent_tool_executor.dart

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/agent_llm/models/playback_context.dart';
import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/t4/services/source_manager.dart';

class AgentToolExecutor {
  AgentToolExecutor._();
  static final AgentToolExecutor instance = AgentToolExecutor._();

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    final registry = AgentToolRegistry.instance;

    // ============ search_video ============
    registry.register(AgentTool(
      name: 'search_video',
      description: '在影视源中按关键词搜索视频，并跳转到搜索结果页',
      parameters: {
        'type': 'object',
        'properties': {
          'keyword': {
            'type': 'string',
            'description': '搜索关键词',
          },
        },
        'required': ['keyword'],
      },
      execute: (args) async {
        final kw = args['keyword']?.toString().trim() ?? '';
        if (kw.isEmpty) {
          return {'ok': false, 'error': 'keyword 不能为空'};
        }
        Get.toNamed(AppPages.search, arguments: {'keyword': kw});
        return {'ok': true, 'action': '已打开搜索页', 'keyword': kw};
      },
    ));

    // ============ open_video ============
    registry.register(AgentTool(
      name: 'open_video',
      description: '打开指定视频的详情页',
      parameters: {
        'type': 'object',
        'properties': {
          'vodId': {
            'type': 'string',
            'description': '视频 ID',
          },
          'siteKey': {
            'type': 'string',
            'description': '视频源 key（可选，不填则使用当前源）',
          },
        },
        'required': ['vodId'],
      },
      execute: (args) async {
        final vodId = args['vodId']?.toString().trim() ?? '';
        if (vodId.isEmpty) {
          return {'ok': false, 'error': 'vodId 不能为空'};
        }
        final siteKey = args['siteKey']?.toString().trim() ?? '';
        Map<String, dynamic>? site;
        if (siteKey.isNotEmpty && Get.isRegistered<SourceManager>()) {
          site = Get.find<SourceManager>().sites.firstWhereOrNull(
                (s) => s['key']?.toString() == siteKey,
              );
        }
        String pwd = 'tinydust';
        if (site != null) {
          final ext = site['ext'];
          if (ext is Map && ext['pwd'] != null) {
            pwd = ext['pwd'].toString();
          }
        }
        Get.toNamed(AppPages.detail, arguments: {
          'vodId': vodId,
          'pwd': pwd,
          if (site != null) 'site': site,
        });
        return {
          'ok': true,
          'action': '已打开详情页',
          'vodId': vodId,
          'siteKey': siteKey,
        };
      },
    ));

    // ============ get_player_state ============
    registry.register(AgentTool(
      name: 'get_player_state',
      description: '获取当前播放器状态（是否播放、位置、时长、视频标题、当前集名、来源）',
      parameters: {
        'type': 'object',
        'properties': {},
      },
      execute: (args) async {
        final ctx = PlaybackContextRegistry.instance.current;
        final state = <String, dynamic>{
          'playing': false,
          'position': 0,
          'duration': 0,
          'vodId': '',
          'vodName': '',
          'episodeName': '',
          'siteKey': '',
          'siteName': '',
        };
        try {
          final pc = PlPlayerController.getInstance();
          state['playing'] = pc.playerStatus.value.isPlaying;
          state['position'] = pc.position.inSeconds;
          state['duration'] = pc.duration.value.inSeconds;
        } catch (e) {
          debugPrint('[AgentToolExecutor] get_player_state 读播放器失败: $e');
        }
        if (ctx != null) {
          state['vodId'] = ctx.vodId;
          state['vodName'] = ctx.vodName;
          state['episodeName'] = ctx.episodeName;
          state['siteKey'] = ctx.siteKey;
          state['siteName'] = ctx.siteName;
        }
        return {'ok': true, 'state': state};
      },
    ));
  }

  /// 执行单个 tool_call
  Future<Map<String, dynamic>> executeToolCall(Map<String, dynamic> tc) async {
    final id = tc['id']?.toString() ?? '';
    final fn = tc['function'];
    var name = '';
    var args = <String, dynamic>{};
    if (fn is Map) {
      name = fn['name']?.toString() ?? '';
      final rawArgs = fn['arguments'];
      if (rawArgs is Map) {
        args = Map<String, dynamic>.from(rawArgs);
      } else if (rawArgs is String && rawArgs.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawArgs);
          if (decoded is Map) {
            args = Map<String, dynamic>.from(decoded);
          }
        } catch (e) {
          debugPrint('[AgentToolExecutor] args 解析失败: $e');
        }
      }
    }

    final tool = AgentToolRegistry.instance.find(name);
    if (tool == null) {
      return {
        'tool_call_id': id,
        'content': jsonEncode({'ok': false, 'error': 'unknown tool: $name'}),
      };
    }

    try {
      final result = await tool.execute(args);
      return {
        'tool_call_id': id,
        'content': jsonEncode(result),
      };
    } catch (e) {
      return {
        'tool_call_id': id,
        'content': jsonEncode({'ok': false, 'error': e.toString()}),
      };
    }
  }
}
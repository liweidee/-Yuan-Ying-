// lib/modules/agent_llm/services/capabilities/playback_capability.dart

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/modules/agent_llm/models/playback_context.dart';
import 'package:yuanying/modules/agent_llm/services/agent_tool_registry.dart';
import 'package:yuanying/modules/agent_llm/services/capabilities/agent_capability.dart';
import 'package:yuanying/modules/agent_llm/utils/keyword_matcher.dart';
import 'package:yuanying/modules/agent_llm/utils/message_utils.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/t4/services/source_manager.dart';

/// 点播能力：搜索 / 打开详情 / 查询播放状态 / 查询壳子状态。
///
/// 对齐 DsPlayer 的「找片 & 播放」大类。
class PlaybackCapability extends AgentCapability {
  @override
  String get id => 'playback';

  @override
  String get displayName => '点播';

  @override
  String get summary => '搜索影视、打开详情页、查询播放状态';

  @override
  void register(AgentToolRegistry registry) {
    registry.register(_buildSearchVideo());
    registry.register(_buildOpenVideo());
    registry.register(_buildGetPlayerState());
    registry.register(_buildGetAppState());
  }

  // ============================================================
  // search_video
  // ============================================================

  AgentTool _buildSearchVideo() {
    return AgentTool(
      name: 'search_video',
      description: '在影视源中按关键词搜索视频，并跳转到搜索结果页',
      usageGuide: '''
【什么时候用】
- 用户说"搜一下 xxx" / "找 xxx" / "有没有 xxx" / "帮我搜 xxx"
- 用户想找某部影视作品，但还没指定具体线路或集数
- 未来如果用户说"全网找"，应改用 search_video_all（尚未实现）

【什么时候不用】
- 用户已经在播放中，说"下一集" / "换线路" → 应该用播放控制工具（未来）
- 用户想打开一个已知的 vodId → 用 open_video

【示例】
- "搜一下战狼2" → keyword="战狼2"
- "帮我找流浪地球" → keyword="流浪地球"
- "有没有沙丘2的资源" → keyword="沙丘2"

【参数提取规则】
- keyword 只填影视名，不带"电影"、"电视剧"、"资源"、"在线"等修饰词
- 不要包含"搜"、"找"、"看"等动词
''',
      parameters: {
        'type': 'object',
        'properties': {
          'keyword': {
            'type': 'string',
            'description': '搜索关键词（影视名）',
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
      // 保险：模型不支持 tools 时靠这个命中
      fallbackIntentMatcher: (messages) {
        final text = extractLastUserText(messages);
        return KeywordMatcher.matchSearch(text);
      },
    );
  }

  // ============================================================
  // open_video
  // ============================================================

  AgentTool _buildOpenVideo() {
    return AgentTool(
      name: 'open_video',
      description: '打开指定视频的详情页',
      usageGuide: '''
【什么时候用】
- 用户明确给出了 vodId（比如从搜索结果里选了一条）要打开详情页
- 用户说"看《XXX》" 但已经通过上一步 search_video 拿到了 vodId

【什么时候不用】
- 用户只说"搜《XXX》"，还没确定具体哪一条 → 用 search_video
- 用户说"播放第 N 个" → 需要列表上下文，当前版本不支持

【示例】
- "打开战狼2" → vodId="12345"（需模型从上下文推断）
- "看这条" → vodId="从上下文推断"

【参数规则】
- vodId 必填，siteKey 可选（不填则使用当前源）
''',
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
      // open_video 依赖上下文中的 vodId，不适合关键词兜底
      fallbackIntentMatcher: null,
    );
  }

  // ============================================================
  // get_player_state
  // ============================================================

  AgentTool _buildGetPlayerState() {
    return AgentTool(
      name: 'get_player_state',
      description: '获取当前播放器状态（是否播放、位置、时长、视频标题、当前集名、来源）',
      usageGuide: '''
【什么时候用】
- 用户问"我在看什么" / "播到哪了" / "第几集"
- 用户在做播放控制类指令（下一集、快进）但模型需要确认当前状态
- 用户说"当前源是什么"（需要结合状态推断）

【什么时候不用】
- 用户说"搜一下 xxx" → 用 search_video
- 用户在未播放任何内容时问"我在看什么" → 仍可调用，会返回 playing=false

【示例】
- "我在看什么" → 无参数
- "播到哪了" → 无参数
''',
      parameters: {'type': 'object', 'properties': {}},
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
          debugPrint('[PlaybackCapability] get_player_state 读播放器失败: $e');
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
      fallbackIntentMatcher: (messages) {
        final text = extractLastUserText(messages);
        return KeywordMatcher.matchPlayerState(text);
      },
    );
  }

  // ============================================================
  // get_app_state（对齐 DsPlayer 的 app_dump）
  // ============================================================

  AgentTool _buildGetAppState() {
    return AgentTool(
      name: 'get_app_state',
      description: '获取当前壳子状态（所在页面、是否在播放、播放详情）',
      usageGuide: '''
【什么时候用】
- 模型不确定用户现在在哪一页时
- 用户问"我现在在哪" / "在干什么"
- 执行多步操作前需要确认状态

【什么时候不用】
- 状态已经由 system prompt 的【当前壳子状态】提供时，不需要再调
- 大多数情况下不需要主动调，system prompt 已经包含状态

【示例】
- "我现在在哪" → 无参数
''',
      parameters: {'type': 'object', 'properties': {}},
      execute: (args) async {
        final route = Get.currentRoute;
        final ctx = PlaybackContextRegistry.instance.current;
        return {
          'ok': true,
          'route': route,
          if (ctx != null) ...{
            'vodName': ctx.vodName,
            'episodeName': ctx.episodeName,
            'siteKey': ctx.siteKey,
            'siteName': ctx.siteName,
          },
        };
      },
      // get_app_state 是显式查询工具，不设兜底
      fallbackIntentMatcher: null,
    );
  }
}
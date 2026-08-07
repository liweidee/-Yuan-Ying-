import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import 'package:yuanying/common/widgets/custom_icon.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/utils/extension/num_ext.dart';
import 'package:yuanying/modules/video/controllers/video_controller.dart';
import 'package:yuanying/modules/video/widgets/danmaku_settings.dart';
import 'package:yuanying/plugin/pl_player/controller.dart';
import 'package:yuanying/plugin/pl_player/models/play_repeat.dart';
import 'package:yuanying/plugin/pl_player/models/video_fit_type.dart';
import 'package:yuanying/plugin/pl_player/player_pref.dart';
import 'package:yuanying/services/shutdown_timer_service.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/utils/duration_utils.dart';
import 'package:yuanying/common/widgets/scroll_behavior.dart';
import 'package:yuanying/common/widgets/dialog/export_import.dart';
import 'package:yuanying/utils/storage_utils.dart';
import 'package:yuanying/models_new/video/video_play_info/subtitle.dart';
import 'package:yuanying/utils/utils.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:yuanying/plugin/pl_player/models/hwdec_type.dart';
import 'package:media_kit/media_kit.dart' hide Subtitle;

// ===== 播放地址信息卡片数据模型 =====
class _AddressInfoItem {
  final IconData icon;
  final String title;
  final String content;
  final String copyContent;
  final Color color;
  final bool isJson;

  _AddressInfoItem({
    required this.icon,
    required this.title,
    required this.content,
    required this.copyContent,
    required this.color,
    this.isJson = false,
  });
}

/// 更多设置面板 - 支持桌面端右侧弹出和移动端底部弹出
class SettingSheet extends StatefulWidget {
  final DetailController controller;
  final bool isWide; // 桌面端为 true

  const SettingSheet({
    super.key,
    required this.controller,
    this.isWide = false,
  });

  @override
  State<SettingSheet> createState() => _SettingSheetState();
}

class _SettingSheetState extends State<SettingSheet> {
  late final DetailController controller;
  late final PlPlayerController playerController;

  final bool isFvpEngine = PlayerPref.playerEngine == PlayerEngineType.fvp;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    playerController = controller.playerController;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWide = widget.isWide;

    if (isWide) {
      // 桌面端：普通 ListView，从顶部开始显示
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          ),
        ),
        child: ScrollConfiguration(
          behavior: const NoScrollbarBehavior(),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: _buildContent(theme),
          ),
        ),
      );
    } else {
      // 移动端：固定高度，不可拖拽，底部安全区域
      final bottomPadding = MediaQuery.of(context).padding.bottom;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: Material(
            color: colorScheme.surface,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: ScrollConfiguration(
                behavior: const NoScrollbarBehavior(),
                child: ListView(
                  padding: EdgeInsets.only(
                    top: 8,
                    bottom: bottomPadding + 8, // 底部安全区域 + 额外间距
                  ),
                  children: _buildContent(theme),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  List<Widget> _buildContent(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return [
      // ===== 画质 =====
      if (controller.currentQualities.isNotEmpty)
        _buildSettingItem(
          icon: Icons.high_quality,
          title: '选择画质',
          subtitle: controller.currentPlayUrl.value.isNotEmpty
              ? controller.currentQualities
                  .firstWhere(
                    (q) => q.url == controller.currentPlayUrl.value,
                    orElse: () => controller.currentQualities.first,
                  )
                  .label
              : '默认',
          onTap: _showQualityDialog,
        ),

      // ===== 解码格式 =====
      if (!isFvpEngine)
        _buildSettingItem(
          icon: Icons.memory,
          title: '硬解模式',
          subtitle: PlayerPref.hardwareDecoding,
          onTap: _showHwDecDialog,
        ),

      // ===== 倍速 =====
      _buildSettingItem(
        icon: Icons.speed,
        title: '倍速',
        subtitle: '${playerController.playbackSpeed}X',
        onTap: _showSpeedDialog,
      ),

      // ===== 画面比例 =====
      _buildSettingItem(
        icon: Icons.aspect_ratio,
        title: '画面比例',
        subtitle: playerController.videoFit.value.desc,
        onTap: _showFitDialog,
      ),

      // ===== 播放顺序 =====
      _buildSettingItem(
        icon: Icons.repeat,
        title: '播放顺序',
        subtitle: playerController.playRepeat.label,
        onTap: _showPlayRepeatDialog,
      ),

      // ===== 音轨选择 =====
      if (controller.audioTracks.isNotEmpty && !isFvpEngine)
        _buildSettingItem(
          icon: Icons.audiotrack,
          title: '音轨选择',
          subtitle: controller.currentAudioName,
          onTap: _showAudioTrackDialog,
        ),

      // ===== 视轨选择 =====
      if (controller.videoTracks.isNotEmpty && !isFvpEngine)
        _buildSettingItem(
          icon: Icons.videocam,
          title: '视轨选择',
          subtitle: controller.currentVideoName,
          onTap: _showVideoTrackDialog,
        ),

      // ===== 字幕轨道 =====
      if (controller.subtitleTracks.isNotEmpty && !isFvpEngine)
        _buildSettingItem(
          icon: Icons.closed_caption,
          title: '字幕轨道',
          subtitle: controller.currentSubtitleName,
          onTap: _showSubtitleTrackDialog,
        ),

      const SizedBox(height: 4),

      // ===== 弹幕设置 =====
      _buildSettingItem(
        icon: CustomIcons.dm_settings,
        title: '弹幕设置',
        subtitle: '弹幕外观及屏蔽',
        onTap: _showDanmakuSettings,
      ),

      // ===== 字幕设置 =====
      if (!isFvpEngine)
        _buildSettingItem(
          icon: Icons.subtitles_outlined,
          title: '字幕设置',
          subtitle: '字幕样式及加载',
          onTap: _showSubtitleSettings,
        ),

      const SizedBox(height: 4),

      // ===== 水平操作区 =====
      _buildActionRow(),

      const SizedBox(height: 4),

      // ===== 离线缓存 =====
      _buildSettingItem(
        icon: Icons.download_outlined,
        title: '离线缓存',
        subtitle: '缓存视频到本地',
        onTap: () {
          SmartDialog.showToast('离线缓存功能开发中');
        },
      ),

      // ===== 播放地址 =====
      _buildSettingItem(
        icon: Icons.link,
        title: '播放地址',
        subtitle: controller.currentPlayUrl.value.isNotEmpty
            ? controller.currentPlayUrl.value.length > 30
                ? '${controller.currentPlayUrl.value.substring(0, 30)}...'
                : controller.currentPlayUrl.value
            : '无',
        onTap: _showPlayUrlDialog,
      ),

      // ===== 重载视频 =====
      _buildSettingItem(
        icon: Icons.refresh_outlined,
        title: '重载视频',
        subtitle: '重新加载当前视频',
        onTap: _reloadVideo,
      ),

      // ===== 加载字幕 =====
      // if (!isFvpEngine)
      _buildSettingItem(
        icon: Icons.file_open_outlined,
        title: '加载字幕',
        subtitle: '加载本地字幕文件',
        onTap: _loadSubtitle,
      ),

      // ===== 保存字幕 =====
      if (!isFvpEngine)
        _buildSettingItem(
          icon: Icons.download_outlined,
          title: '保存字幕',
          subtitle: '保存当前字幕',
          onTap: _exportSubtitle,
        ),

      // ===== 保存封面 =====
      _buildSettingItem(
        icon: Icons.image_outlined,
        title: '保存封面',
        subtitle: '保存视频封面图',
        onTap: _saveCover,
      ),

      const SizedBox(height: 4),

      // 跳过片头片尾
      _buildSettingItem(
        icon: Icons.skip_next_outlined,
        title: '跳过片头片尾',
        subtitle: '设置跳过片头片尾时长',
        onTap: _showSkipDialog,
      ),

      // ===== 定时关闭 =====
      _buildSettingItem(
        icon: Icons.hourglass_top_outlined,
        title: '定时关闭',
        subtitle: '设置播放定时关闭',
        onTap: _showScheduleExitDialog,
      ),

      // ===== 播放信息 =====
      _buildSettingItem(
        icon: Icons.info_outline,
        title: '播放信息',
        subtitle: '查看播放统计信息',
        onTap: _showPlayerInfoDialog,
      ),

      const SizedBox(height: 8),
    ];
  }

  // ===== 设置项构建 =====
  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.outline,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
      ),
    );
  }

  // ===== 水平操作区 =====
  Widget _buildActionRow() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildActionChip(
              icon: Icons.flip,
              label: '左右翻转',
              selected: playerController.flipX.value,
              onTap: () {
                playerController.flipX.value = !playerController.flipX.value;
                setState(() {});
              },
            ),
            const SizedBox(width: 10),
            _buildActionChip(
              icon: CustomIcons.view_headline_rotate_90,
              label: '上下翻转',
              selected: playerController.flipY.value,
              onTap: () {
                playerController.flipY.value = !playerController.flipY.value;
                setState(() {});
              },
            ),
            const SizedBox(width: 10),
            _buildActionChip(
              icon: Icons.headphones,
              label: '听视频',
              selected: playerController.onlyPlayAudio.value,
              onTap: () {
                playerController.onlyPlayAudio.value =
                    !playerController.onlyPlayAudio.value;
                controller.playerInit();
                setState(() {});
              },
            ),
            const SizedBox(width: 10),
            _buildActionChip(
              icon: Icons.play_circle_outline,
              label: '后台播放',
              selected: playerController.continuePlayInBackground.value,
              onTap: () {
                playerController.setContinuePlayInBackground();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: selected
              ? null
              : Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.25),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? colorScheme.primary : colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 获取当前解码格式 =====
  String _getCurrentDecodeFormat() {
    return PlayerPref.hardwareDecoding.toUpperCase();
  }

  // ===== 画质选择 =====
  void _showQualityDialog() {
    final qualities = controller.currentQualities;
    if (qualities.isEmpty) {
      SmartDialog.showToast('当前没有可选的画质');
      return;
    }
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;
      showDialog(
        context: Get.context!,
        builder: (context) => AlertDialog(
          title: const Text('选择画质'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: qualities.map((quality) {
              final isSelected = controller.currentPlayUrl.value == quality.url;
              return ListTile(
                dense: true,
                title: Text(quality.label),
                trailing: isSelected
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  controller.switchQuality(quality);
                },
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // ===== 解码格式选择 =====
  void _showHwDecDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;
      final current = PlayerPref.hardwareDecoding;
      showDialog(
        context: Get.context!,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '硬解模式',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: HwDecType.values.map((type) {
                        final isSelected = type.hwdec == current;
                        return ListTile(
                          dense: true,
                          title: Text(type.hwdec),
                          subtitle: Text(type.desc, style: const TextStyle(fontSize: 12)),
                          trailing: isSelected
                              ? Icon(Icons.check, color: colorScheme.primary)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            PlayerPref.hardwareDecoding = type.hwdec;
                            controller.switchDecodeFormat(type.hwdec);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // ===== 音轨选择对话框 =====
  void _showAudioTrackDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;
      final tracks = controller.audioTracks;
      if (tracks.isEmpty) {
        SmartDialog.showToast('没有可用的音轨');
        return;
      }
      showDialog(
        context: Get.context!,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.audiotrack, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('选择音轨', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('共 ${tracks.length + 2} 条', style: TextStyle(fontSize: 13, color: colorScheme.outline)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // 自动选择
                      _buildTrackTile(
                        title: '自动选择',
                        subtitle: 'Track auto',
                        isSelected: controller.currentAudioIndex == -2,
                        onTap: () {
                          Navigator.pop(context);
                          controller.setAudioTrack(AudioTrack.auto());
                        },
                        colorScheme: colorScheme,
                      ),
                      // 关闭音轨
                      _buildTrackTile(
                        title: '关闭音轨',
                        subtitle: 'Track no',
                        isSelected: controller.currentAudioIndex == -3,
                        onTap: () {
                          Navigator.pop(context);
                          controller.setAudioTrack(AudioTrack.no());
                        },
                        colorScheme: colorScheme,
                      ),
                      // 所有音轨
                      ...tracks.asMap().entries.map((entry) {
                        final index = entry.key;
                        final track = entry.value;
                        final isSelected = controller.currentAudioIndex == index;
                        return _buildTrackTile(
                          title: track.title ?? '音轨 ${index + 1}',
                          subtitle: _buildAudioSubtitle(track),
                          isSelected: isSelected,
                          onTap: () {
                            Navigator.pop(context);
                            controller.setAudioTrack(track);
                          },
                          colorScheme: colorScheme,
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _buildAudioSubtitle(AudioTrack track) {
    final parts = <String>[];
    if (track.language != null) parts.add('语言：${track.language}');
    if (track.codec != null) parts.add('编码：${track.codec}');
    return parts.join(' / ');
  }

  // ===== 视轨选择对话框 =====
  void _showVideoTrackDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;
      final tracks = controller.videoTracks;
      if (tracks.isEmpty) {
        SmartDialog.showToast('没有可用的视轨');
        return;
      }
      showDialog(
        context: Get.context!,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.videocam, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('选择视轨', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('共 ${tracks.length + 2} 条', style: TextStyle(fontSize: 13, color: colorScheme.outline)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // 自动选择
                      _buildTrackTile(
                        title: '自动选择',
                        subtitle: 'Track auto',
                        isSelected: controller.currentVideoIndex == -2,
                        onTap: () {
                          Navigator.pop(context);
                          controller.setVideoTrack(VideoTrack.auto());
                        },
                        colorScheme: colorScheme,
                      ),
                      // 关闭视轨
                      _buildTrackTile(
                        title: '关闭视轨',
                        subtitle: 'Track no',
                        isSelected: controller.currentVideoIndex == -3,
                        onTap: () {
                          Navigator.pop(context);
                          controller.setVideoTrack(VideoTrack.no());
                        },
                        colorScheme: colorScheme,
                      ),
                      ...tracks.asMap().entries.map((entry) {
                        final index = entry.key;
                        final track = entry.value;
                        final isSelected = controller.currentVideoIndex == index;
                        return _buildTrackTile(
                          title: track.title ?? '视轨 ${index + 1}',
                          subtitle: _buildVideoSubtitle(track),
                          isSelected: isSelected,
                          onTap: () {
                            Navigator.pop(context);
                            controller.setVideoTrack(track);
                          },
                          colorScheme: colorScheme,
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _buildVideoSubtitle(VideoTrack track) {
    final parts = <String>[];
    if (track.language != null) parts.add('语言：${track.language}');
    if (track.codec != null) parts.add('编码：${track.codec}');
    // 使用官方 API 属性名：w, h, fps[reference:4]
    if (track.w != null && track.h != null) {
      parts.add('分辨率：${track.w}x${track.h}');
    }
    if (track.fps != null) {
      parts.add('帧率：${track.fps!.toStringAsFixed(2)}fps');
    }
    return parts.join(' / ');
  }

  // ===== 字幕轨道对话框 =====
  void _showSubtitleTrackDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;
      final tracks = controller.subtitleTracks;
      if (tracks.isEmpty) {
        SmartDialog.showToast('没有可用的字幕轨道');
        return;
      }
      showDialog(
        context: Get.context!,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.closed_caption, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('选择字幕', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('共 ${tracks.length + 3} 条', style: TextStyle(fontSize: 13, color: colorScheme.outline)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // 关闭字幕（使用 SubtitleTrack.no()）
                      _buildTrackTile(
                        title: '关闭字幕',
                        subtitle: '不显示任何字幕',
                        isSelected: controller.currentSubtitleTrackIndex == -1,
                        onTap: () {
                          Navigator.pop(context);
                          controller.disableSubtitleTrack();
                        },
                        colorScheme: colorScheme,
                      ),
                      // 自动选择
                      _buildTrackTile(
                        title: '自动选择',
                        subtitle: 'Track auto',
                        isSelected: controller.currentSubtitleTrackIndex == -2,
                        onTap: () {
                          Navigator.pop(context);
                          controller.setSubtitleTrack(SubtitleTrack.auto());
                        },
                        colorScheme: colorScheme,
                      ),
                      // 强制无字幕
                      _buildTrackTile(
                        title: '强制无字幕',
                        subtitle: 'Track no',
                        isSelected: controller.currentSubtitleTrackIndex == -3,
                        onTap: () {
                          Navigator.pop(context);
                          controller.setSubtitleTrack(SubtitleTrack.no());
                        },
                        colorScheme: colorScheme,
                      ),
                      ...tracks.asMap().entries.map((entry) {
                        final index = entry.key;
                        final track = entry.value;
                        final isSelected = controller.currentSubtitleTrackIndex == index;
                        return _buildTrackTile(
                          title: track.title ?? '字幕 ${index + 1}',
                          subtitle: _buildSubtitleSub(track),
                          isSelected: isSelected,
                          onTap: () {
                            Navigator.pop(context);
                            controller.setSubtitleTrack(track);
                          },
                          colorScheme: colorScheme,
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _buildSubtitleSub(SubtitleTrack track) {
    final parts = <String>[];
    if (track.language != null) parts.add('语言：${track.language}');
    if (track.codec != null) parts.add('编码：${track.codec}');
    return parts.join(' / ');
  }

  Widget _buildTrackTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.outline))
          : null,
      trailing: isSelected ? Icon(Icons.check, color: colorScheme.primary) : null,
      onTap: onTap,
    );
  }

  // ===== 倍速选择 =====
  void _showSpeedDialog() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final theme = Theme.of(Get.context!);
      final colorScheme = theme.colorScheme;
      showDialog(
        context: Get.context!,
        builder: (context) => AlertDialog(
          title: const Text('倍速'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: speeds.map((speed) {
              final isSelected =
                  (playerController.playbackSpeed - speed).abs() < 0.01;
              return GestureDetector(
                onTap: () {
                  playerController.setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // ===== 画面比例选择 =====
  void _showFitDialog() {
    const fits = [
      VideoFitType.contain,
      VideoFitType.cover,
      VideoFitType.fill,
      VideoFitType.fitWidth,
      VideoFitType.fitHeight,
    ];
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final theme = Theme.of(Get.context!);
      final colorScheme = theme.colorScheme;
      showDialog(
        context: Get.context!,
        builder: (context) => AlertDialog(
          title: const Text('画面比例'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fits.map((fit) {
              final isSelected = playerController.videoFit.value == fit;
              return GestureDetector(
                onTap: () {
                  playerController.toggleVideoFit(fit);
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    fit.desc,
                    style: TextStyle(
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // ===== 播放顺序选择 =====
  void _showPlayRepeatDialog() {
    final values = PlayRepeat.values;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;
      showDialog(
        context: Get.context!,
        builder: (context) => AlertDialog(
          title: const Text('播放顺序'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: values.map((mode) {
              final isSelected = playerController.playRepeat == mode;
              return ListTile(
                dense: true,
                title: Text(mode.label),
                trailing: isSelected
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  playerController.setPlayRepeat(mode);
                },
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  // ===== 弹幕设置 =====
  void _showDanmakuSettings() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showModalBottomSheet(
        context: Get.context!,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DanmakuSettings(controller: controller),
      );
    });
  }

  // ===== 字幕设置 =====
  void _showSubtitleSettings() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final theme = Theme.of(Get.context!);
      final colorScheme = theme.colorScheme;

      final sliderTheme = SliderThemeData(
        trackHeight: 10,
        trackShape: const _MSliderTrackShape(),
        thumbColor: colorScheme.primary,
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.onInverseSurface,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
      );

      showModalBottomSheet(
        context: Get.context!,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  child: DraggableScrollableSheet(
                    initialChildSize: 0.65,
                    minChildSize: 0.4,
                    maxChildSize: 0.85,
                    expand: false,
                    builder: (context, scrollController) {
                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        children: [
                          // 标题
                          const SizedBox(height: 8),
                          const Center(
                            child: Text(
                              '字幕设置',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ===== 字体大小 =====
                          _buildSubtitleSlider(
                            label: '字体大小',
                            value: playerController.subtitleFontScale,
                            min: 0.5,
                            max: 2.5,
                            divisions: 20,
                            displayFormat: (v) => '${(v * 100).toStringAsFixed(1)}%',
                            defaultValue: 1.0,
                            onChanged: (val) {
                              playerController.subtitleFontScale = val;
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          // ===== 全屏字体大小 =====
                          _buildSubtitleSlider(
                            label: '全屏字体大小',
                            value: playerController.subtitleFontScaleFS,
                            min: 0.5,
                            max: 2.5,
                            divisions: 20,
                            displayFormat: (v) => '${(v * 100).toStringAsFixed(1)}%',
                            defaultValue: 1.5,
                            onChanged: (val) {
                              playerController.subtitleFontScaleFS = val;
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          // ===== 字体粗细 =====
                          _buildSubtitleSliderInt(
                            label: '字体粗细',
                            value: playerController.subtitleFontWeight,
                            min: 0,
                            max: 8,
                            divisions: 8,
                            displayFormat: (v) => '${v + 1}',
                            defaultValue: 5,
                            note: '（可能无法精确调节）',
                            onChanged: (val) {
                              playerController.subtitleFontWeight = val;
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          // ===== 描边粗细 =====
                          _buildSubtitleSlider(
                            label: '描边粗细',
                            value: playerController.subtitleStrokeWidth,
                            min: 0,
                            max: 5,
                            divisions: 10,
                            displayFormat: (v) => v.toStringAsFixed(1),
                            defaultValue: 2.0,
                            onChanged: (val) {
                              playerController.subtitleStrokeWidth = val;
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          // ===== 左右边距 =====
                          _buildSubtitleSliderInt(
                            label: '左右边距',
                            value: playerController.subtitlePaddingH,
                            min: 0,
                            max: 100,
                            divisions: 100,
                            displayFormat: (v) => v.toString(),
                            defaultValue: 24,
                            onChanged: (val) {
                              playerController.subtitlePaddingH = val;
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          // ===== 底部边距 =====
                          _buildSubtitleSliderInt(
                            label: '底部边距',
                            value: playerController.subtitlePaddingB,
                            min: 0,
                            max: 200,
                            divisions: 200,
                            displayFormat: (v) => v.toString(),
                            defaultValue: 24,
                            onChanged: (val) {
                              playerController.subtitlePaddingB = val;
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          // ===== 背景不透明度 =====
                          _buildSubtitleSlider(
                            label: '背景不透明度',
                            value: playerController.subtitleBgOpacity,
                            min: 0,
                            max: 1,
                            divisions: 10,
                            displayFormat: (v) => '${(v * 100).toInt()}%',
                            defaultValue: 0.67,
                            onChanged: (val) {
                              playerController.subtitleBgOpacity = val.toPrecision(2);
                              playerController.updateSubtitleStyle();
                              setState(() {});
                            },
                          ),

                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        // 保存设置
        playerController.putSubtitleSettings();
      });
    });
  }

  // ===== 字幕设置辅助方法 =====
  /// 重置按钮
  Widget _resetBtn(ThemeData theme, Object def, VoidCallback onPressed) {
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        tooltip: '默认值: $def',
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: theme.colorScheme.outline,
        ),
      ),
    );
  }

  /// 浮点数滑块（字幕设置专用）
  Widget _buildSubtitleSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String Function(double) displayFormat,
    required double defaultValue,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(Get.context!);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$label ${displayFormat(value)}',
                style: const TextStyle(fontSize: 13),
              ),
              _resetBtn(theme, defaultValue, () {
                onChanged(defaultValue);
              }),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              trackShape: const _MSliderTrackShape(),
              thumbColor: colorScheme.primary,
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.onInverseSurface,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            ),
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value.clamp(min, max),
              label: displayFormat(value),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// 整数滑块（字幕设置专用）
  Widget _buildSubtitleSliderInt({
    required String label,
    required int value,
    required double min,
    required double max,
    int? divisions,
    required String Function(int) displayFormat,
    required int defaultValue,
    String note = '',
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(Get.context!);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$label ${displayFormat(value)}',
                style: const TextStyle(fontSize: 13),
              ),
              _resetBtn(theme, defaultValue, () {
                onChanged(defaultValue);
              }),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Text(
                note,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              trackShape: const _MSliderTrackShape(),
              thumbColor: colorScheme.primary,
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.onInverseSurface,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            ),
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value.toDouble().clamp(min, max),
              label: displayFormat(value),
              onChanged: (val) {
                onChanged(val.toInt());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderItem({
    required String label,
    required double value,
    required double min,
    required double max,
    required String Function(double) displayFormat,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
            Text(displayFormat(value), style: TextStyle(fontSize: 13, color: colorScheme.onSurface)),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ===== 跳过片头片尾 =====
  void _showSkipDialog() {
    // 关闭更多设置
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;

      // 从 controller 读取当前值
      int initialStart = controller.skipStartDuration.value;
      int initialEnd = controller.skipEndDuration.value;

      // 使用 showDialog，状态变量定义在 StatefulBuilder 外部
      showDialog(
        context: Get.context!,
        barrierDismissible: true,
        builder: (dialogContext) {
          // 状态变量放在 StatefulBuilder 外部，保证 setState 后不会重置
          int localStart = initialStart;
          int localEnd = initialEnd;

          return StatefulBuilder(
            builder: (context, setState) {
              // 内部函数更新状态
              void updateStart(int value) {
                setState(() {
                  localStart = value;
                });
              }

              void updateEnd(int value) {
                setState(() {
                  localEnd = value;
                });
              }

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '跳过片头片尾',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '设置后将自动跳过片头片尾，仅当次有效',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // 片头行
                      Row(
                        children: [
                          const SizedBox(
                            width: 44,
                            child: Text('片头:', style: TextStyle(fontSize: 14)),
                          ),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 300,
                              divisions: 60,
                              value: localStart.toDouble(),
                              onChanged: (val) => updateStart(val.round()),
                              activeColor: colorScheme.primary,
                              inactiveColor: colorScheme.onSurface.withOpacity(0.1),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              localStart == 0 ? '关' : '${localStart}s',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 片尾行
                      Row(
                        children: [
                          const SizedBox(
                            width: 44,
                            child: Text('片尾:', style: TextStyle(fontSize: 14)),
                          ),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 300,
                              divisions: 60,
                              value: localEnd.toDouble(),
                              onChanged: (val) => updateEnd(val.round()),
                              activeColor: colorScheme.primary,
                              inactiveColor: colorScheme.onSurface.withOpacity(0.1),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              localEnd == 0 ? '关' : '${localEnd}s',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 预设按钮网格
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 3.5,
                        children: [
                          _buildPresetButton('片头30s', () => updateStart(30), colorScheme),
                          _buildPresetButton('片头60s', () => updateStart(60), colorScheme),
                          _buildPresetButton('片头90s', () => updateStart(90), colorScheme),
                          _buildPresetButton('片尾30s', () => updateEnd(30), colorScheme),
                          _buildPresetButton('片尾60s', () => updateEnd(60), colorScheme),
                          _buildPresetButton('片尾90s', () => updateEnd(90), colorScheme),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 底部操作栏
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                localStart = 0;
                                localEnd = 0;
                              });
                            },
                            child: Text('清除', style: TextStyle(color: colorScheme.primary)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text('取消', style: TextStyle(color: colorScheme.primary)),
                          ),
                          TextButton(
                            onPressed: () {
                              // 保存设置
                              controller.skipStartDuration.value = localStart;
                              controller.skipEndDuration.value = localEnd;
                              controller.playerController.skipStartDuration.value = localStart;
                              controller.playerController.skipEndDuration.value = localEnd;
                              // 立即应用片头跳过
                              final pos = controller.playerController.position;
                              if (localStart > 0 && pos.inSeconds < localStart) {
                                controller.playerController.seekTo(
                                  Duration(seconds: localStart),
                                  isSeek: false,
                                );
                              }
                              Navigator.of(dialogContext).pop();
                            },
                            child: Text(
                              '确定',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    });
  }

  Widget _buildPresetButton(String label, VoidCallback onTap, ColorScheme colorScheme) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 6),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
      ),
    );
  }

  // ===== 定时关闭 =====
  void _showScheduleExitDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      shutdownTimerService.showScheduleExitDialog(Get.context!);
    });
  }

  // ===== 重载视频 =====
  void _reloadVideo() {
    Navigator.pop(context);
    controller.reloadCurrentEpisode();
    SmartDialog.showToast('重载成功');
  }

  // ===== 播放地址查看 =====
  void _showPlayUrlDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final theme = Theme.of(Get.context!);
      final colorScheme = theme.colorScheme;

      // ===== 收集数据 =====
      final flag = controller.introController.sourceNames.isNotEmpty
          ? controller.introController.sourceNames[
              controller.introController.currentSourceIndex.value
                  .clamp(0, controller.introController.sourceNames.length - 1)
            ]
          : '未知线路';

      final play = controller.introController.currentPlayEpisode?.url ?? '无';

      final playUrl = controller.currentPlayUrl.value.isNotEmpty
          ? controller.currentPlayUrl.value
          : '无';

      final headers = controller.currentHeaders.value;
      final hasHeaders = headers.isNotEmpty;

      // ===== 构建数据项列表 =====
      final items = [
        _AddressInfoItem(
          icon: Icons.radio_button_checked_rounded,
          title: '播放源',
          content: flag,
          copyContent: flag,
          color: colorScheme.primary,
        ),
        _AddressInfoItem(
          icon: Icons.link_rounded,
          title: '原始链接',
          content: play,
          copyContent: play,
          color: colorScheme.secondary,
        ),
        _AddressInfoItem(
          icon: Icons.play_circle_rounded,
          title: '实际播放地址',
          content: playUrl,
          copyContent: playUrl,
          color: colorScheme.tertiary,
        ),
        _AddressInfoItem(
          icon: Icons.code_rounded,
          title: '请求头',
          content: hasHeaders ? _formatHeaders(headers) : '暂无请求头',
          copyContent: hasHeaders ? _formatHeaders(headers) : '',
          color: colorScheme.primary,
          isJson: hasHeaders,
        ),
      ];

      showDialog(
        context: Get.context!,
        barrierDismissible: true,
        builder: (context) {
          return Dialog(
            backgroundColor: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 560,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ===== 标题栏 =====
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '播放地址信息',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: colorScheme.outline,
                          ),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ===== 内容区域（可滚动） =====
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Column(
                        children: items.map((item) => _buildInfoCard(context, item)).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // ===== 构建单个信息卡片 =====
  Widget _buildInfoCard(BuildContext context, _AddressInfoItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== 标题栏（图标 + 标题 + 复制图标按钮） =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // 播放源使用标签图标
                Icon(
                  item.title == '播放源'
                      ? MdiIcons.tag
                      : item.icon,
                  size: 16,
                  color: item.color,
                ),
                const SizedBox(width: 8),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                // ===== 复制按钮：只显示图标，无文字，无背景 =====
                if (item.copyContent.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      Utils.copyText(item.copyContent);
                      SmartDialog.showToast('已复制 ${item.title}');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ===== 内容区域（带圆角背景） =====
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              child: item.isJson
                  ? _buildJsonContent(context, item.content)
                  : SelectableText(
                      item.content,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: item.content.length > 60 ? 'Monospace' : null,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== 构建 JSON 内容（请求头专用） =====
  Widget _buildJsonContent(BuildContext context, String jsonStr) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: SelectableText(
        jsonStr,
        style: TextStyle(
          fontSize: 12,
          height: 1.8,
          color: colorScheme.onSurfaceVariant,
          fontFamily: 'Monospace',
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ===== 格式化请求头为可读 JSON =====
  String _formatHeaders(Map<String, String> headers) {
    if (headers.isEmpty) return '{}';
    final buffer = StringBuffer('{\n');
    final entries = headers.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      buffer.write('  "${entry.key}": "${entry.value}"');
      if (i < entries.length - 1) buffer.write(',');
      buffer.write('\n');
    }
    buffer.write('}');
    return buffer.toString();
  }

  // ===== 加载字幕（完整实现） =====
  void _loadSubtitle() async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json', 'vtt', 'srt', 'ass'],
      );
      if (result == null) return;

      final file = result.xFile;
      final path = file.path;
      final name = file.name;
      final length = controller.subtitles.length;

      if (name.endsWith('.json')) {
        final content = await file.readAsString();
        final jsonData = jsonDecode(content);
        if (jsonData is List) {
          String vttContent = _convertJsonToVtt(jsonData);
          final subId = '${DateTime.now().millisecondsSinceEpoch}';
          controller.vttSubtitles[length] = (isData: true, id: vttContent);
          controller.subtitles.add(
            Subtitle(
              lan: '',
              lanDoc: name.split('.').firstOrNull ?? name,
            ),
          );
          // 等待加载完成
          await controller.setSubtitle(length + 1);
          SmartDialog.showToast('字幕加载成功: $name');
        } else {
          SmartDialog.showToast('无法解析的字幕文件');
        }
      } else {
        // 非 JSON 格式，转换为 file:// URI
        final uri = Uri.file(path).toString();
        controller.vttSubtitles[length] = (isData: false, id: uri);
        controller.subtitles.add(
          Subtitle(
            lan: '',
            lanDoc: name.split('.').firstOrNull ?? name,
          ),
        );
        await controller.setSubtitle(length + 1);
        SmartDialog.showToast('字幕加载成功: $name');
      }
    } catch (e) {
      SmartDialog.showToast('加载字幕失败: $e');
    }
  }

  // 辅助方法：将 JSON 字幕转换为 VTT 格式
  String _convertJsonToVtt(List<dynamic> jsonData) {
    StringBuffer vtt = StringBuffer();
    vtt.writeln('WEBVTT');
    vtt.writeln();
    for (var item in jsonData) {
      if (item['from'] != null && item['to'] != null && item['content'] != null) {
        String from = _formatTime(item['from']);
        String to = _formatTime(item['to']);
        vtt.writeln('$from --> $to');
        vtt.writeln(item['content']);
        vtt.writeln();
      }
    }
    return vtt.toString();
  }

  String _formatTime(num seconds) {
    int hours = (seconds ~/ 3600).toInt();
    int minutes = ((seconds % 3600) ~/ 60).toInt();
    int secs = (seconds % 60).toInt();
    int millis = ((seconds - seconds.floor()) * 1000).round();
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  // ===== 保存字幕（完整实现） =====
  void _exportSubtitle() async {
    final subtitles = controller.subtitles;
    if (subtitles.isEmpty) {
      SmartDialog.showToast('没有可导出的字幕');
      return;
    }

    final index = controller.vttSubtitlesIndex.value;
    if (index <= 0 || index > subtitles.length) {
      SmartDialog.showToast('请先加载字幕');
      return;
    }

    final subtitle = subtitles[index - 1];
    final url = subtitle.subtitleUrl;
    if (url == null || url.isEmpty) {
      SmartDialog.showToast('无法获取字幕数据');
      return;
    }

    try {
      final res = await Dio().get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode == 200) {
        final bytes = Uint8List.fromList(res.data as List<int>);
        final name = 'subtitle_${DateTime.now().millisecondsSinceEpoch}.json';
        StorageUtils.saveBytes2File(
          name: name,
          bytes: bytes,
        );
      } else {
        SmartDialog.showToast('导出字幕失败');
      }
    } catch (e) {
      SmartDialog.showToast('导出字幕失败: $e');
    }
  }

  // ===== 保存封面 =====
  void _saveCover() async {
    try {
      final coverUrl = controller.introController.videoDetail.value?.vodPic;
      if (coverUrl == null || coverUrl.isEmpty) {
        SmartDialog.showToast('当前没有封面图');
        return;
      }

      SmartDialog.showToast('正在下载封面...');

      final dio = Dio();
      final response = await dio.get(
        coverUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 && response.data != null) {
        final bytes = response.data as Uint8List;
        final dir = await getTemporaryDirectory();
        final fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);

        SmartDialog.showToast('封面已保存到: $fileName');
      } else {
        SmartDialog.showToast('下载封面失败');
      }
    } catch (e) {
      SmartDialog.showToast('保存封面失败: $e');
    }
  }

  // ===== 播放信息 =====
  void _showPlayerInfoDialog() {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final colorScheme = Theme.of(Get.context!).colorScheme;

      // 获取基本信息（适用于所有引擎）
      final pos = playerController.position;
      final dur = playerController.duration.value;
      final isPlaying = playerController.playerStatus.value.isPlaying;
      final speed = playerController.playbackSpeed;
      final hwdec = PlayerPref.hardwareDecoding;

      // 分辨率（优先使用 playerController.width/height）
      int width = playerController.width ?? 0;
      int height = playerController.height ?? 0;
      // 如果仍为 0，尝试从底层 state 获取（仅 MediaKit）
      if (width == 0 || height == 0) {
        final player = playerController.videoPlayerController;
        if (player != null) {
          width = player.state.width ?? 0;
          height = player.state.height ?? 0;
        }
      }
      final resolution = (width > 0 && height > 0) ? '${width}x${height}' : '未知';

      // 音轨/视轨名称（仅 MediaKit 有实际值，FVP 下为 '默认'）
      final audioName = playerController.currentAudioTrack.value?.title ?? '默认';
      final videoName = playerController.currentVideoTrack.value?.title ?? '默认';

      showDialog(
        context: Get.context!,
        builder: (context) => AlertDialog(
          title: const Text('播放信息'),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('状态', isPlaying ? '播放中' : '已暂停', colorScheme),
              _infoRow('当前位置', DurationUtils.formatDuration(pos.inSeconds), colorScheme),
              _infoRow('总时长', DurationUtils.formatDuration(dur.inSeconds), colorScheme),
              _infoRow('进度', dur.inSeconds > 0
                  ? '${(pos.inSeconds / dur.inSeconds * 100).toStringAsFixed(1)}%'
                  : '0%', colorScheme),
              _infoRow('倍速', '${speed}X', colorScheme),
              _infoRow('分辨率', resolution, colorScheme),
              _infoRow('当前音轨', audioName, colorScheme),
              _infoRow('当前视轨', videoName, colorScheme),
              _infoRow('硬解模式', hwdec, colorScheme),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.outline,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });
  }

  Widget _infoRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义滑块轨道形状
class _MSliderTrackShape extends RoundedRectSliderTrackShape {
  const _MSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    SliderThemeData? sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    const double trackHeight = 3;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2 + 4;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
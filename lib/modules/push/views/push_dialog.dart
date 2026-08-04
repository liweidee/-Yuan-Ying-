import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';

import 'package:yuanying/core/routes/app_pages.dart';
import 'package:yuanying/t4/models/play_url.dart';
import 'package:yuanying/t4/services/video_api_service.dart';
import 'package:yuanying/t4/services/source_manager.dart';
import 'package:yuanying/services/parser_service.dart';

// ===== 解析模式枚举（必须在类外部定义） =====
enum ParseMode { direct, parser, api, magnet }

/// 推送播放底部弹窗
class PushDialog extends StatefulWidget {
  const PushDialog({super.key});

  @override
  State<PushDialog> createState() => _PushDialogState();
}

class _PushDialogState extends State<PushDialog> {
  // ===== 状态 =====
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final Rx<ParseMode> _selectedMode = ParseMode.direct.obs;
  final RxBool _isLoading = false.obs;
  final RxString _selectedFilePath = ''.obs;

  // ===== 依赖 =====
  final SourceManager _sourceManager = Get.find<SourceManager>();
  final VideoApiService _apiService = VideoApiService();

  @override
  void initState() {
    super.initState();
    final site = _sourceManager.currentSite.value;
    if (site != null && site['api'] != null) {
      _apiService.setBaseUrl(site['api']!.toString());
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ===== 拖动指示器 =====
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ===== 标题 =====
              const Text(
                '推送播放',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // ===== URL 输入行 =====
              _buildUrlInputRow(colorScheme),

              const SizedBox(height: 12),

              // ===== 本地文件行 =====
              _buildLocalFileRow(colorScheme),

              const SizedBox(height: 20),

              // ===== 解析方式切换器 =====
              _buildParseModeSwitcher(colorScheme),

              const SizedBox(height: 24),

              // ===== 播放按钮 =====
              Obx(() {
                final isLoading = _isLoading.value;
                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _onPlay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '播放',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                );
              }),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// URL 输入行
  Widget _buildUrlInputRow(ColorScheme colorScheme) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.search_rounded,
            size: 20,
            color: colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Obx(
              () => Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // ===== 输入框 =====
                  TextField(
                    controller: _inputController,
                    focusNode: _inputFocusNode,
                    onChanged: (text) {
                      if (text.isNotEmpty && _selectedFilePath.value.isNotEmpty) {
                        _selectedFilePath.value = '';
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _selectedFilePath.value.isNotEmpty
                          ? '已选择文件，可继续编辑'
                          : '输入视频URL',
                      hintStyle: TextStyle(
                        color: colorScheme.outline,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    onSubmitted: (_) => _onPlay(),
                  ),
                  // ===== 文件状态提示（仅当有文件时才显示） =====
                  if (_selectedFilePath.value.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          color: colorScheme.surface,
                          child: Text(
                            '已选择文件: ${_selectedFilePath.value.split('/').last}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 粘贴按钮
          IconButton(
            icon: Icon(
              Icons.paste_rounded,
              size: 20,
              color: colorScheme.outline,
            ),
            onPressed: _pasteFromClipboard,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// 本地文件行
  Widget _buildLocalFileRow(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _pickLocalFile,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              Icons.folder_rounded,
              size: 20,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Obx(
              () => Expanded(
                child: Text(
                  _selectedFilePath.value.isNotEmpty
                      ? _selectedFilePath.value.split('/').last
                      : '选择本地视频...',
                  style: TextStyle(
                    color: _selectedFilePath.value.isNotEmpty
                        ? colorScheme.onSurface
                        : colorScheme.outline,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_selectedFilePath.value.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colorScheme.outline,
                ),
                onPressed: () {
                  _selectedFilePath.value = '';
                  _inputController.clear();
                },
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// 解析方式切换器
  Widget _buildParseModeSwitcher(ColorScheme colorScheme) {
    final items = [
      {'label': '直链', 'icon': Icons.check_rounded, 'mode': ParseMode.direct},
      {'label': '解析', 'icon': null, 'mode': ParseMode.parser},
      {'label': '接口', 'icon': null, 'mode': ParseMode.api},
      {'label': '磁力', 'icon': Icons.flash_on_rounded, 'mode': ParseMode.magnet},
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.15),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: items.map((item) {
          final mode = item['mode'] as ParseMode;
          final label = item['label'] as String;
          final icon = item['icon'] as IconData?;

          return Expanded(
            child: Obx(
              () {
                final isSelected = _selectedMode.value == mode;
                return GestureDetector(
                  onTap: () => _selectedMode.value = mode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected && icon != null) ...[
                          Icon(
                            icon,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (icon != null && !isSelected) ...[
                          Icon(
                            icon,
                            size: 14,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.outline,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===== 粘贴 =====
  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData('text/plain');
      final text = clipboardData?.text;
      if (text != null && text.isNotEmpty) {
        if (_selectedFilePath.value.isNotEmpty) {
          _selectedFilePath.value = '';
        }
        _inputController.text = text;
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
        _inputFocusNode.requestFocus();
        SmartDialog.showToast('已粘贴');
      } else {
        SmartDialog.showToast('剪贴板为空');
      }
    } catch (e) {
      SmartDialog.showToast('粘贴失败');
    }
  }

  // ===== 选择本地文件 =====
  Future<void> _pickLocalFile() async {
    try {
      // 使用与项目其他地方一致的 API
      final result = await FilePicker.pickFile(
        type: FileType.video,
        allowedExtensions: null,
      );
      if (result != null) {
        final file = result.xFile;
        _inputController.clear();
        _selectedFilePath.value = file.path;
        SmartDialog.showToast('已选择: ${file.name}');
      }
    } catch (e) {
      SmartDialog.showToast('选择文件失败: $e');
    }
  }

  // ===== 播放核心逻辑 =====
  Future<void> _onPlay() async {
    String input = _inputController.text.trim();

    if (_selectedFilePath.value.isNotEmpty) {
      input = _selectedFilePath.value;
    }

    if (input.isEmpty) {
      SmartDialog.showToast('请输入视频URL或选择本地文件');
      return;
    }

    switch (_selectedMode.value) {
      case ParseMode.direct:
        await _playDirect(input);
        break;
      case ParseMode.parser:
        await _playWithParser(input);
        break;
      case ParseMode.api:
        await _playWithApi(input);
        break;
      case ParseMode.magnet:
        SmartDialog.showToast('磁力播放功能开发中');
        break;
    }
  }

  // ===== 直链播放 =====
  Future<void> _playDirect(String input) async {
    _isLoading.value = true;

    try {
      final tag = 'push_${DateTime.now().millisecondsSinceEpoch}';
      final site = _sourceManager.currentSite.value;

      final isLocalFile = input.startsWith('file://') ||
          (Uri.tryParse(input)?.scheme == 'file') ||
          (File(input).existsSync());

      if (isLocalFile && !File(input).existsSync()) {
        SmartDialog.showToast('文件不存在，请重新选择');
        _isLoading.value = false;
        return;
      }

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': isLocalFile ? 'file://$input' : input,
          'directTitle': '直链播放',  // ← 新增
          '_controllerTag': tag,
        },
        preventDuplicates: false,
      );

      SmartDialog.showToast('正在加载...');
    } catch (e) {
      SmartDialog.showToast('播放失败: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  // ===== 解析播放 =====
  Future<void> _playWithParser(String input) async {
    _isLoading.value = true;

    try {
      final parseList = _sourceManager.parses;
      if (parseList.isEmpty) {
        SmartDialog.showToast('暂无可用解析源，请先在设置中配置');
        _isLoading.value = false;
        return;
      }

      final parser = ParserSource.fromJson(parseList.first);
      if (parser.url.isEmpty) {
        SmartDialog.showToast('解析源配置无效');
        _isLoading.value = false;
        return;
      }

      final fullUrl = '${parser.url}${Uri.encodeComponent(input)}';
      String? parsedUrl;

      // type: 1 → JSON 直接取
      if (parser.type == 1) {
        final response = await Dio().get(
          fullUrl,
          options: Options(headers: parser.headers ?? {}),
        );
        final data = response.data;
        if (data is Map) {
          parsedUrl = data['url']?.toString() ??
              data['playUrl']?.toString() ??
              data['play_url']?.toString();
        }
      }
      // type: 0 → 嗅探
      else {
        try {
          final response = await Dio().get(
            fullUrl,
            options: Options(
              headers: parser.headers ?? {},
              responseType: ResponseType.plain,
            ),
          );
          final html = response.data.toString();

          final patterns = [
            r'https?://[^\s]+\.m3u8[^\s]*',
            r'https?://[^\s]+\.mp4[^\s]*',
            r'https?://[^\s]+\.flv[^\s]*',
          ];
          for (final pattern in patterns) {
            final regExp = RegExp(pattern, caseSensitive: false);
            final match = regExp.firstMatch(html);
            if (match != null) {
              parsedUrl = match.group(0);
              break;
            }
          }
          if (parsedUrl == null) {
            try {
              final jsonData = jsonDecode(html);
              if (jsonData is Map) {
                parsedUrl = jsonData['url']?.toString() ??
                    jsonData['playUrl']?.toString() ??
                    jsonData['play_url']?.toString();
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      if (parsedUrl == null || parsedUrl.isEmpty) {
        SmartDialog.showToast('解析失败，请尝试其他解析源');
        _isLoading.value = false;
        return;
      }

      // ===== 解析成功，传递解析模式参数 =====
      final tag = 'push_${DateTime.now().millisecondsSinceEpoch}';

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'isPush': true,
          'directUrl': parsedUrl,
          'directTitle': '解析播放',
          'isParserMode': true,              // ← 标记解析模式
          'parserSources': parseList,         // ← 解析源列表
          'currentParser': parser.toJson(),   // ← 当前解析源
          '_controllerTag': tag,
        },
        preventDuplicates: false,
      );

      SmartDialog.showToast('解析成功，正在播放...');
    } catch (e) {
      SmartDialog.showToast('解析失败: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  // ===== 接口播放 =====
  Future<void> _playWithApi(String input) async {
    _isLoading.value = true;

    try {
      final sites = _sourceManager.sites;
      Map<String, dynamic>? pushAgentSite;
      for (final site in sites) {
        final key = site['key']?.toString() ?? '';
        final type = site['type'] as int? ?? -1;
        if (key == 'push_agent' && type == 4) {
          pushAgentSite = site;
          break;
        }
      }

      if (pushAgentSite == null) {
        SmartDialog.showToast('需要先配置 push_agent 线路');
        _isLoading.value = false;
        return;
      }

      final api = pushAgentSite['api']?.toString() ?? '';
      if (api.isEmpty) {
        SmartDialog.showToast('push_agent 线路配置无效');
        _isLoading.value = false;
        return;
      }

      // ===== 使用 push_agent 站点的 API 地址 =====
      final uri = Uri.parse(api);
      final pwd = uri.queryParameters['pwd'] ?? 'tinydust';
      _apiService.setBaseUrl(api);

      final detail = await _apiService.getDetail(
        vodId: input,
        pwd: pwd,
      );

      if (detail == null || detail.vodId.isEmpty) {
        SmartDialog.showToast('获取视频详情失败，请检查分享链接是否有效');
        _isLoading.value = false;
        return;
      }

      final tag = 'push_${DateTime.now().millisecondsSinceEpoch}';

      Get.toNamed(
        AppPages.detail,
        arguments: {
          'vodId': detail.vodId,
          'site': pushAgentSite,
          'pwd': pwd,
          '_controllerTag': tag,
        },
        preventDuplicates: false,
      );

      SmartDialog.showToast('已获取详情，正在加载...');
    } catch (e) {
      SmartDialog.showToast('获取详情失败: $e');
    } finally {
      _isLoading.value = false;
    }
  }
}
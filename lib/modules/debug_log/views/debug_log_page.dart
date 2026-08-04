import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:json5/json5.dart';
import 'package:yuanying/core/theme/style.dart';
import 'package:yuanying/services/debug_log_service.dart';
import 'package:yuanying/utils/storage_utils.dart';
import 'package:yuanying/utils/utils.dart';

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _entries = <DebugLogEntry>[].obs;
  final _filteredEntries = <DebugLogEntry>[].obs;
  final _loading = false.obs;
  final _page = 0.obs;
  final _hasMore = true.obs;

  final _selectedSource = '全部'.obs;
  final _sources = <String>[].obs;
  final _expandedId = Rx<String?>(null);

  late final TabController _tabController;

  // ================================================================
  // 生命周期
  // ================================================================

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadMore();
    _scrollController.addListener(_onScroll);
    ever(_entries, (_) => _updateSources());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ================================================================
  // 数据加载与筛选
  // ================================================================

  void _updateSources() {
    final sources = _entries.map((e) => e.source).toSet().toList();
    sources.sort();
    if (!sources.contains('全部')) {
      sources.insert(0, '全部');
    }
    _sources.value = sources;
    if (_selectedSource.value != '全部' && !sources.contains(_selectedSource.value)) {
      _selectedSource.value = '全部';
    }
    _applyFilter();
  }

  void _applyFilter() {
    if (_selectedSource.value == '全部') {
      _filteredEntries.value = List.from(_entries);
    } else {
      _filteredEntries.value = _entries
          .where((e) => e.source == _selectedSource.value)
          .toList();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading.value && _hasMore.value) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading.value) return;
    _loading.value = true;
    try {
      final newEntries = await DebugLogService.instance.readLogs(
        page: _page.value,
        pageSize: 30,
      );
      if (newEntries.isEmpty) {
        _hasMore.value = false;
      } else {
        _entries.addAll(newEntries);
        _page.value++;
      }
    } catch (e) {
      SmartDialog.showToast('加载失败: $e');
    } finally {
      _loading.value = false;
    }
  }

  Future<void> _refresh() async {
    _entries.clear();
    _page.value = 0;
    _hasMore.value = true;
    await _loadMore();
    _updateSources();
  }

  // ================================================================
  // 导出与清除
  // ================================================================

  Future<void> _exportLogs() async {
    try {
      SmartDialog.showLoading(msg: '导出中...');
      final jsonStr = await DebugLogService.instance.exportLogs();
      final fileName =
          'debug_logs_${DateTime.now().toIso8601String().substring(0, 10)}.json';
      await StorageUtils.saveBytes2File(
        name: fileName,
        bytes: utf8.encode(jsonStr),
      );
      SmartDialog.dismiss();
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('导出失败: $e');
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: Style.mdRadius),
        title: const Text('确认清除'),
        content: const Text('确定要清除所有调试日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DebugLogService.instance.clearLogs();
      await _refresh();
      SmartDialog.showToast('已清除');
    }
  }

  // ================================================================
  // 颜色辅助
  // ================================================================

  Color _getStatusColor(int? statusCode) {
    if (statusCode == null) return Colors.grey;
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 300 && statusCode < 400) return Colors.orange;
    return Colors.red;
  }

  Color _getSourceColor(String source) {
    switch (source) {
      case 't4':
        return Colors.blue;
      case 'drpy2':
        return Colors.purple;
      case 'catvod':
        return Colors.teal;
      case 'xbpq':
        return Colors.orange;
      case 'xyq':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  // ================================================================
  // 核心：JSON 精确检测与格式化（使用 json5）
  // ================================================================

  /// 清理 JSON 响应中的干扰前缀（BOM、空白、JSON劫持前缀）
  String _cleanJsonString(String raw) {
    String cleaned = raw.trim().replaceAll(RegExp(r'^[\uFEFF]+'), '');
    if (cleaned.isEmpty) return cleaned;

    final prefixes = [
      ')]}\'\n',
      ')]},\n',
      ')]}\n',
      'while(1);',
      'for(;;);',
    ];
    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
        break;
      }
    }
    return cleaned;
  }

  /// 精准判断是否为有效的 JSON 对象或数组
  bool _isJson(String raw) {
    final cleaned = _cleanJsonString(raw);
    if (cleaned.isEmpty) return false;
    final firstChar = cleaned[0];
    if (firstChar != '{' && firstChar != '[') return false;
    try {
      final decoded = JSON5.parse(cleaned);
      return decoded is Map || decoded is List;
    } catch (_) {
      return false;
    }
  }

  /// 格式化 JSON（支持 JSON5 语法），失败回退原始文本
  String _formatJson(String raw) {
    final cleaned = _cleanJsonString(raw);
    if (cleaned.isEmpty) return raw;
    try {
      final decoded = JSON5.parse(cleaned);
      if (decoded is Map || decoded is List) {
        return const JsonEncoder.withIndent('  ').convert(decoded);
      }
      return raw;
    } catch (_) {
      return raw;
    }
  }

  // ================================================================
  // 请求参数/体处理
  // ================================================================

  String _getQueryString(String url) {
    try {
      final uri = Uri.parse(url);
      final query = uri.query;
      return query.isEmpty ? '' : query;
    } catch (_) {
      return '';
    }
  }

  String _formatRequestBody(String method, String? body) {
    if (body == null || body.isEmpty) return '';
    if (method.toUpperCase() != 'POST') return body;
    if (_isJson(body)) return _formatJson(body);
    return body;
  }

  // ================================================================
  // 复制功能
  // ================================================================

  void _copyToClipboard(DebugLogEntry entry) {
    final content = {
      'method': entry.method,
      'url': entry.url,
      'statusCode': entry.statusCode,
      'responseBody': entry.responseBody,
      'requestBody': entry.requestBody,
      'headers': entry.headers,
      'source': entry.source,
      'timestamp': entry.timestamp.toIso8601String(),
    };
    Utils.copyText(const JsonEncoder.withIndent('  ').convert(content));
  }

  // ================================================================
  // 构建 UI
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('调试日志'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Obx(() {
            final currentSource = _selectedSource.value;
            final sourceList = _sources.value;
            if (sourceList.isEmpty) return const SizedBox.shrink();
            return Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: sourceList.length,
                itemBuilder: (context, index) {
                  final source = sourceList[index];
                  final isSelected = currentSource == source;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(source),
                      selected: isSelected,
                      onSelected: (_) {
                        _selectedSource.value = source;
                        _applyFilter();
                      },
                      backgroundColor: colorScheme.surface,
                      selectedColor: colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                      showCheckmark: false,
                      side: BorderSide(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportLogs,
            tooltip: '导出日志',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: '清除全部',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Obx(() {
        final displayList = _filteredEntries;
        if (displayList.isEmpty && !_loading.value) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 64, color: colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  '暂无日志记录',
                  style: TextStyle(color: colorScheme.outline),
                ),
                const SizedBox(height: 8),
                Text(
                  '请在关于页面开启调试日志开关',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            itemCount: displayList.length + (_loading.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= displayList.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final entry = displayList[index];
              final isExpanded = _expandedId.value == entry.url + entry.timestamp.toString();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ----- 卡片头部 -----
                    InkWell(
                      onTap: () {
                        setState(() {
                          final id = entry.url + entry.timestamp.toString();
                          _expandedId.value = isExpanded ? null : id;
                        });
                      },
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: Row(
                          children: [
                            // 方法标签
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.method,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (entry.statusCode != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(entry.statusCode).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${entry.statusCode}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: _getStatusColor(entry.statusCode),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            // 来源标签
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getSourceColor(entry.source).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.source,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _getSourceColor(entry.source),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (entry.durationMs != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.outline.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${entry.durationMs}ms',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.outline,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            // 复制按钮
                            InkWell(
                              onTap: () => _copyToClipboard(entry),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.copy,
                                  size: 18,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                            // 展开/收起按钮
                            InkWell(
                              onTap: () {
                                setState(() {
                                  final id = entry.url + entry.timestamp.toString();
                                  _expandedId.value = isExpanded ? null : id;
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ----- URL -----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        entry.url,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // ----- 时间 -----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        entry.timestamp.toLocal().toIso8601String().substring(0, 19),
                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                      ),
                    ),
                    // ----- 展开内容 -----
                    if (isExpanded) ...[
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 16,
                        endIndent: 16,
                        color: colorScheme.outline.withOpacity(0.15),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ----- 请求头 -----
                            if (entry.headers != null && entry.headers!.isNotEmpty)
                              _buildInfoSection(
                                label: '请求头',
                                icon: Icons.headset_mic_outlined,
                                content: entry.headers!.entries
                                    .map((e) => '${e.key}: ${e.value}')
                                    .join('\n'),
                              ),
                            // ----- 请求参数（GET 查询参数） -----
                            if (_getQueryString(entry.url).isNotEmpty)
                              _buildInfoSection(
                                label: '请求参数',
                                icon: Icons.search_outlined,
                                content: _getQueryString(entry.url),
                                isPlain: true,
                              ),
                            // ----- 请求体（POST 时格式化 JSON） -----
                            if (entry.requestBody != null && entry.requestBody!.isNotEmpty)
                              _buildInfoSection(
                                label: '请求体',
                                icon: Icons.input_outlined,
                                content: _formatRequestBody(entry.method, entry.requestBody),
                                isJson: _isJson(entry.requestBody!),
                              ),
                            // ----- 响应体 -----
                            if (entry.responseBody != null && entry.responseBody!.isNotEmpty)
                              _buildInfoSection(
                                label: '响应体',
                                icon: Icons.output_outlined,
                                content: _isJson(entry.responseBody!)
                                    ? _formatJson(entry.responseBody!)
                                    : entry.responseBody!,
                                isJson: _isJson(entry.responseBody!),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }

  // ================================================================
  // 信息区域构建（支持内容选择复制）
  // ================================================================

  Widget _buildInfoSection({
    required String label,
    required IconData icon,
    required String content,
    bool isJson = false,
    bool isPlain = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (isJson) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'JSON',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isPlain
                ? SelectableText(
                    content,
                    style: const TextStyle(fontSize: 13),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SelectableText(
                        content,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: isJson ? 'monospace' : null,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
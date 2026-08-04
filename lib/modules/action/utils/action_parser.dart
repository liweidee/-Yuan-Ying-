import 'dart:convert';

import '../models/action_config.dart';
import '../models/action_type.dart';

/// Action 解析工具
/// 严格对应 DrPlayer 的 types.js 中的解析逻辑
class ActionParser {
  /// 解析 Action 配置
  /// 支持 JSON 字符串或 Map 对象
  static ActionConfig? parse(dynamic data) {
    if (data == null) return null;

    try {
      Map<String, dynamic> json;

      if (data is String) {
        try {
          json = jsonDecode(data);
        } catch (_) {
          return null;
        }
      } else if (data is Map<String, dynamic>) {
        json = data;
      } else {
        return null;
      }

      // 验证必要的字段
      if (!json.containsKey('actionId') || json['actionId'] == null) {
        return null;
      }

      // 尝试构建 ActionConfig
      return ActionConfig.fromJson(json);
    } catch (e) {
      print('ActionParser.parse 失败: $e');
      return null;
    }
  }

  /// 检测是否为专项动作
  static bool isSpecialAction(ActionConfig config) {
    return config.isSpecialAction;
  }

  /// 检测是否为专项动作（通过原始数据）
  static bool isSpecialActionFromJson(Map<String, dynamic> json) {
    final hasType = json.containsKey('type');
    final actionId = json['actionId']?.toString() ?? '';
    return !hasType || (actionId.startsWith('__') && actionId.endsWith('__'));
  }

  /// 解析 selectData
  /// 严格对应 DrPlayer 的 parseSelectData 函数
  static List<SelectOption> parseSelectData(String? selectData) {
    if (selectData == null || selectData.isEmpty) {
      return [];
    }

    try {
      // 1. 检查是否为特殊选择器
      if (selectData.startsWith('[') && selectData.endsWith(']')) {
        final inner = selectData.substring(1, selectData.length - 1);
        // 检查是否为特殊类型
        if (['folder', 'calendar', 'file', 'image'].contains(inner.toLowerCase())) {
          return [
            SelectOption(
              name: _getSpecialDisplayName(inner),
              value: selectData,
              isSpecial: true,
            ),
          ];
        }
      }

      // 2. 检查是否为带前缀的特殊选择器: [请选择字母]a,b,c,d
      if (selectData.startsWith('[') && selectData.contains(']')) {
        final bracketEnd = selectData.indexOf(']');
        final prefix = selectData.substring(1, bracketEnd);
        final optionsStr = selectData.substring(bracketEnd + 1);

        if (optionsStr.isNotEmpty) {
          return optionsStr.split(',').map((item) {
            final trimmed = item.trim();
            return SelectOption(
              name: trimmed,
              value: trimmed,
            );
          }).where((item) => item.name.isNotEmpty).toList();
        } else {
          // 只有前缀，可能是特殊选择器
          return [
            SelectOption(
              name: prefix,
              value: selectData,
            ),
          ];
        }
      }

      // 3. 支持标准 JSON 格式
      if ((selectData.startsWith('[') && selectData.endsWith(']')) ||
          (selectData.startsWith('{') && selectData.endsWith('}'))) {
        try {
          final decoded = jsonDecode(selectData);
          if (decoded is List) {
            return decoded.map((item) {
              if (item is Map<String, dynamic>) {
                return SelectOption(
                  name: item['name']?.toString() ?? '',
                  value: item['value']?.toString() ?? '',
                );
              }
              return SelectOption(
                name: item.toString(),
                value: item.toString(),
              );
            }).where((item) => item.name.isNotEmpty).toList();
          }
          if (decoded is Map<String, dynamic>) {
            return decoded.entries.map((entry) {
              return SelectOption(
                name: entry.key,
                value: entry.value.toString(),
              );
            }).toList();
          }
        } catch (_) {
          // JSON 解析失败，继续其他格式
        }
      }

      // 4. 支持 [tag]:=[value] 格式，用逗号分隔
      if (selectData.contains(':=')) {
        return selectData.split(',').map((item) {
          final trimmed = item.trim();
          if (trimmed.contains(':=')) {
            final parts = trimmed.split(':=');
            return SelectOption(
              name: parts[0].trim(),
              value: parts.length > 1 ? parts[1].trim() : parts[0].trim(),
            );
          }
          return SelectOption(
            name: trimmed,
            value: trimmed,
          );
        }).where((item) => item.name.isNotEmpty).toList();
      }

      // 5. 支持简单的分隔符格式（兼容旧格式）
      if (selectData.contains('|')) {
        return selectData.split('|').map((item) {
          final trimmed = item.trim();
          if (trimmed.contains('=')) {
            final parts = trimmed.split('=');
            return SelectOption(
              name: parts[0].trim(),
              value: parts.length > 1 ? parts[1].trim() : parts[0].trim(),
            );
          }
          return SelectOption(
            name: trimmed,
            value: trimmed,
          );
        }).where((item) => item.name.isNotEmpty).toList();
      }

      // 6. 简单逗号分隔
      if (selectData.contains(',')) {
        return selectData.split(',').map((item) {
          final trimmed = item.trim();
          return SelectOption(
            name: trimmed,
            value: trimmed,
          );
        }).where((item) => item.name.isNotEmpty).toList();
      }

      // 7. 单个选项
      return [
        SelectOption(
          name: selectData,
          value: selectData,
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  static String _getSpecialDisplayName(String type) {
    switch (type.toLowerCase()) {
      case 'calendar':
        return '📅 选择日期';
      case 'file':
        return '📄 选择文件';
      case 'folder':
        return '📁 选择文件夹';
      case 'image':
        return '🖼️ 选择图片';
      default:
        return type;
    }
  }

  /// 检查是否包含非特殊选项
  static bool hasNonSpecialOptions(String selectData) {
    final options = parseSelectData(selectData);
    return options.any((option) => !option.isSpecial);
  }

  /// 获取非特殊选项
  static List<SelectOption> getNonSpecialOptions(String selectData) {
    return parseSelectData(selectData).where((option) => !option.isSpecial).toList();
  }

  /// 生成二维码 URL
  static String generateQRCodeUrl(String text, [String size = '200x200']) {
    return 'https://api.qrserver.com/v1/create-qr-code/?size=$size&data=${Uri.encodeComponent(text)}';
  }
}

/// 选择选项
class SelectOption {
  final String name;
  final String value;
  final bool isSpecial;

  SelectOption({
    required this.name,
    required this.value,
    this.isSpecial = false,
  });
}
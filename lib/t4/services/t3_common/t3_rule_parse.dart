import 'dart:convert';
import 'package:json5/json5.dart';

class XBPQParse {
  // ===== 1. 带转义的分割函数 =====
  static List<String> splitWithEscapedDelimiter(String str, String delimiter) {
    final parts = <String>[];
    final buffer = StringBuffer();
    int i = 0;
    while (i < str.length) {
      if (str.startsWith(delimiter, i)) {
        if (i > 0 && str[i - 1] == '\\') {
          buffer.write(delimiter);
          i += delimiter.length;
        } else {
          parts.add(buffer.toString());
          buffer.clear();
          i += delimiter.length;
        }
      } else {
        buffer.write(str[i]);
        i++;
      }
    }
    parts.add(buffer.toString());
    for (int j = 0; j < parts.length; j++) {
      parts[j] = parts[j].replaceAll('\\$delimiter', delimiter);
    }
    return parts;
  }

  static List<String> dealWithRule(String rule) {
    return splitWithEscapedDelimiter(rule, '&&');
  }

  // ===== 2. 通配符转正则 =====
  static String getSplitRule(String rule) {
    if (rule.contains('*') && !rule.contains('\\*')) {
      String escaped = rule.replaceAllMapped(RegExp(r'[.+?^${}()|[\]\\]'), (m) => '\\${m.group(0)}');
      return escaped.replaceAll('*', '.*?');
    }
    return rule;
  }

  // ===== 3. 提取所有 [指令] =====
  static (String, List<String>) getInstructionAndClear(String str) {
    final regex = RegExp(r'\[([^\]]*)\]');
    String cleaned = str;
    final instructions = <String>[];
    for (final match in regex.allMatches(str)) {
      final content = match.group(1)!;
      instructions.add(content);
      cleaned = cleaned.replaceFirst(match.group(0)!, '');
    }
    return (cleaned.trim(), instructions);
  }

  // ===== 4. 文本指令处理 =====
  static String carryInstructionForText(String text, List<String> instructions, {int? arrIndex}) {
    var rtext = text;
    for (final cd in instructions) {
      if (cd.startsWith('替换:')) {
        final pairs = splitWithEscapedDelimiter(cd.substring(3), '#');
        for (final pair in pairs) {
          final idx = pair.lastIndexOf('>>');
          if (idx != -1) {
            final oldStr = pair.substring(0, idx);
            var newStr = pair.substring(idx + 2);
            if (newStr == '空') newStr = '';
            if (newStr.contains('<序号>') && arrIndex != null) {
              newStr = newStr.replaceAll('<序号>', arrIndex.toString());
            }
            rtext = rtext.replaceAll(oldStr, newStr);
          }
        }
      } else if (cd == 'Base64') {
        try {
          rtext = utf8.decode(base64.decode(rtext));
        } catch (_) {}
      }
    }
    return rtext;
  }

  // ===== 5. 数组指令处理 =====
  static List<String> carryInstructionForArray(List<String> array, List<String> instructions) {
    var arr = List<String>.from(array);
    for (final cd in instructions) {
      if (cd.startsWith('排序:')) {
        final order = cd.substring(3).split('>');
        arr = customSort(arr, order);
      } else if (cd.startsWith('不包含:')) {
        final exclude = splitWithEscapedDelimiter(cd.substring(4), '#');
        arr = arr.where((item) => !exclude.any((e) => item.contains(e))).toList();
      } else if (cd.startsWith('包含:')) {
        final include = splitWithEscapedDelimiter(cd.substring(3), '#');
        arr = arr.where((item) => include.any((e) => item.contains(e))).toList();
      } else if (cd.startsWith('不含序号:')) {
        final idxs = splitWithEscapedDelimiter(cd.substring(5), '#');
        final List<int> indexes = [];
        for (final idx in idxs) {
          final num = int.tryParse(idx);
          if (num != null) indexes.add(num);
          else if (idx.contains('-')) {
            final parts = idx.split('-');
            final s = int.tryParse(parts[0]) ?? 0;
            final e = int.tryParse(parts[1]) ?? 0;
            for (int i = s; i <= e; i++) indexes.add(i);
          }
        }
        arr = arr.asMap().entries
            .where((e) => !indexes.contains(e.key))
            .map((e) => e.value)
            .toList();
      } else if (cd.startsWith('含序号:')) {
        final idxs = splitWithEscapedDelimiter(cd.substring(4), '#');
        final List<int> indexes = [];
        for (final idx in idxs) {
          final num = int.tryParse(idx);
          if (num != null) indexes.add(num);
          else if (idx.contains('-')) {
            final parts = idx.split('-');
            final s = int.tryParse(parts[0]) ?? 0;
            final e = int.tryParse(parts[1]) ?? 0;
            for (int i = s; i <= e; i++) indexes.add(i);
          }
        }
        arr = arr.asMap().entries
            .where((e) => indexes.contains(e.key))
            .map((e) => e.value)
            .toList();
      }
    }
    return arr;
  }

  static List<String> customSort(List<String> arr, List<String> order) {
    final orderMap = <String, int>{};
    for (int i = 0; i < order.length; i++) {
      orderMap[order[i]] = i;
    }
    arr.sort((a, b) {
      int idxA = 9999, idxB = 9999;
      for (final key in orderMap.keys) {
        if (a.contains(key)) idxA = orderMap[key]!;
        if (b.contains(key)) idxB = orderMap[key]!;
      }
      return idxA.compareTo(idxB);
    });
    return arr;
  }

  // ===== 6. 核心 JSON 路径提取（严格按官方语法） =====
  static dynamic getJsonPathValue(dynamic obj, String path) {
    if (obj == null || path.isEmpty) return null;
    // 按 . 分割路径，并支持数组下标如 covers[0]
    final segments = path.split('.');
    dynamic current = obj;
    for (final seg in segments) {
      if (current == null) return null;
      // 处理数组下标，如 list[0] 或 covers[0]
      final bracketStart = seg.indexOf('[');
      if (bracketStart != -1) {
        final arrayName = seg.substring(0, bracketStart);
        final indexStr = seg.substring(bracketStart + 1, seg.length - 1);
        final index = int.tryParse(indexStr);
        if (index == null) return null;
        // 先取数组对象
        if (arrayName.isNotEmpty) {
          if (current is Map) {
            current = current[arrayName];
          } else {
            return null;
          }
        }
        // 然后取索引
        if (current is List) {
          if (index >= 0 && index < current.length) {
            current = current[index];
          } else {
            return null;
          }
        } else {
          return null;
        }
      } else {
        // 普通键
        if (current is Map) {
          current = current[seg];
        } else {
          return null;
        }
      }
    }
    return current;
  }

  // ===== 7. getSplitArray（支持 j: 和普通字符串分割） =====
  static List<String> getSplitArray(String text, String rule, {bool complete = false}) {
    // 如果规则以 j: 开头，使用 JSON 路径
    if (rule.startsWith('j:')) {
      final path = rule.substring(2).trim();
      try {
        final data = JSON5.parse(text);
        final result = getJsonPathValue(data, path);
        print('j: 数组路径 "$path" 提取结果类型: ${result.runtimeType}, 长度: ${result is List ? result.length : 'N/A'}');
        if (result is List) {
          // 将列表每个元素转为 JSON 字符串，以便后续字段提取
          return result.map((e) => jsonEncode(e)).toList();
        }
        return [];
      } catch (e) {
        print('j: JSON 解析失败: $e');
        return [];
      }
    }

    // 否则按字符串分割
    final (rulec, instructions) = getInstructionAndClear(rule);
    final parts = dealWithRule(rulec);
    if (parts.length < 2) return [];

    final splitterRaw = parts[0];
    final endSplitterRaw = parts[1];
    final splitterIsReg = splitterRaw.contains('*') && !splitterRaw.contains('\\*');
    final endSplitterIsReg = endSplitterRaw.contains('*') && !endSplitterRaw.contains('\\*');

    final splitterRule = getSplitRule(splitterRaw);
    final endSplitterRule = getSplitRule(endSplitterRaw);

    Pattern splitter;
    if (splitterIsReg) {
      splitter = RegExp(splitterRule);
    } else {
      splitter = splitterRule;
    }

    final arr = <String>[];
    final segments = text.split(splitter);
    for (int i = 1; i < segments.length; i++) {
      String rest = segments[i];
      if (endSplitterRule.isEmpty) {
        final content = carryInstructionForText(rest, instructions, arrIndex: i - 1);
        arr.add(content);
        continue;
      }
      int endIdx;
      if (endSplitterIsReg) {
        final reg = RegExp(endSplitterRule);
        final match = reg.firstMatch(rest);
        endIdx = match != null ? match.start : -1;
      } else {
        endIdx = rest.indexOf(endSplitterRule);
      }
      if (endIdx != -1) {
        final content = rest.substring(0, endIdx);
        arr.add(carryInstructionForText(content, instructions, arrIndex: i - 1));
      } else if (!complete) {
        arr.add(carryInstructionForText(rest, instructions, arrIndex: i - 1));
      }
    }
    return carryInstructionForArray(arr, instructions);
  }

  // ===== 8. getHasRuleSplitStr（支持 j: 和普通字符串分割） =====
  static String? getHasRuleSplitStr(String text, String rule, {String? host, bool complete = false}) {
    // 如果规则以 j: 开头，使用 JSON 路径
    if (rule.startsWith('j:')) {
      final path = rule.substring(2).trim();
      try {
        final data = JSON5.parse(text);
        final result = getJsonPathValue(data, path);
        print('j: 路径 "$path" 提取结果: "$result" (数据类型: ${result.runtimeType})');
        if (result != null) {
          String str = result.toString();
          if (host != null && host.isNotEmpty && !str.contains('://') && str.isNotEmpty) {
            return host + str;
          }
          return str;
        }
        return null;
      } catch (e) {
        print('j: JSON 解析失败: $e');
        return null;
      }
    }

    // 否则按字符串分割
    final (rulec, instructions) = getInstructionAndClear(rule);
    final parts = dealWithRule(rulec);
    if (parts.length < 2) return null;

    final splitterRaw = parts[0];
    final endSplitterRaw = parts[1];
    final splitterIsReg = splitterRaw.contains('*') && !splitterRaw.contains('\\*');
    final endSplitterIsReg = endSplitterRaw.contains('*') && !endSplitterRaw.contains('\\*');

    final splitterRule = getSplitRule(splitterRaw);
    final endSplitterRule = getSplitRule(endSplitterRaw);

    Pattern splitter;
    if (splitterIsReg) {
      splitter = RegExp(splitterRule);
    } else {
      splitter = splitterRule;
    }

    final segments = text.split(splitter);
    for (int i = 1; i < segments.length; i++) {
      String rest = segments[i];
      if (endSplitterRule.isEmpty) {
        String result = carryInstructionForText(rest, instructions);
        if (host != null && host.isNotEmpty && !result.contains('://') && result.isNotEmpty) {
          return host + result;
        }
        return result;
      }
      int endIdx;
      if (endSplitterIsReg) {
        final reg = RegExp(endSplitterRule);
        final match = reg.firstMatch(rest);
        endIdx = match != null ? match.start : -1;
      } else {
        endIdx = rest.indexOf(endSplitterRule);
      }
      if (endIdx != -1) {
        final content = rest.substring(0, endIdx);
        String result = carryInstructionForText(content, instructions);
        if (host != null && host.isNotEmpty && !result.contains('://') && result.isNotEmpty) {
          return host + result;
        }
        return result;
      } else if (!complete) {
        String result = carryInstructionForText(rest, instructions);
        if (host != null && host.isNotEmpty && !result.contains('://') && result.isNotEmpty) {
          return host + result;
        }
        return result;
      }
    }
    return null;
  }

  // ===== 9. getSplitStr（支持 j: 和普通字符串分割） =====
  static String getSplitStr(String text, String rule, [String host = '']) {
    // 如果规则以 j: 开头，直接调用 getHasRuleSplitStr
    if (rule.startsWith('j:')) {
      return getHasRuleSplitStr(text, rule, host: host.isNotEmpty ? host : null) ?? '';
    }

    final (rulec, instructions) = getInstructionAndClear(rule);
    final parts = dealWithRule(rulec);
    if (parts.length < 2) return '';
    final splitterRaw = parts[0];
    final endSplitterRaw = parts[1];
    final splitterIsReg = splitterRaw.contains('*') && !splitterRaw.contains('\\*');
    final endSplitterIsReg = endSplitterRaw.contains('*') && !endSplitterRaw.contains('\\*');
    final splitterRule = getSplitRule(splitterRaw);
    final endSplitterRule = getSplitRule(endSplitterRaw);

    Pattern splitter;
    if (splitterIsReg) {
      splitter = RegExp(splitterRule);
    } else {
      splitter = splitterRule;
    }

    final segments = text.split(splitter);
    for (int i = 1; i < segments.length; i++) {
      String rest = segments[i];
      if (endSplitterRule.isEmpty) {
        String result = carryInstructionForText(rest, instructions);
        if (host.isNotEmpty && !result.contains('://') && result.isNotEmpty) {
          result = host + result;
        }
        return result;
      }
      int endIdx;
      if (endSplitterIsReg) {
        final reg = RegExp(endSplitterRule);
        final match = reg.firstMatch(rest);
        endIdx = match != null ? match.start : -1;
      } else {
        endIdx = rest.indexOf(endSplitterRule);
      }
      if (endIdx != -1) {
        final content = rest.substring(0, endIdx);
        String result = carryInstructionForText(content, instructions);
        if (host.isNotEmpty && !result.contains('://') && result.isNotEmpty) {
          result = host + result;
        }
        return result;
      }
    }
    return '';
  }

  // ===== 10. 旧 JSON 路径兼容 =====
  static dynamic getJson(dynamic obj, String path) {
    return getJsonPathValue(obj, path);
  }

  static List<dynamic> getJsonArray(String jsonStr, String rule) {
    try {
      final data = JSON5.parse(jsonStr);
      final result = getJsonPathValue(data, rule);
      if (result is List) return result;
      return [];
    } catch (_) {
      return [];
    }
  }

  static String getJsonStr(String jsonStr, String rule) {
    try {
      final data = JSON5.parse(jsonStr);
      final parts = splitWithEscapedDelimiter(rule, '+');
      String result = '';
      for (final part in parts) {
        final (ruleCondition, instructions) = getInstructionAndClear(part);
        final value = getJsonPathValue(data, ruleCondition);
        if (value != null) {
          result += carryInstructionForText(value.toString(), instructions);
        }
      }
      return result;
    } catch (_) {
      return '';
    }
  }

  static String base64Decode(String str) {
    return utf8.decode(base64.decode(str));
  }

  static String base64Encode(String str) {
    return base64.encode(utf8.encode(str));
  }
}
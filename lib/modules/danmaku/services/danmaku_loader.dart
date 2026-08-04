import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'package:yuanying/http/browser_ua.dart';
import 'package:yuanying/http/constants.dart';
import 'package:yuanying/modules/danmaku/models/danmaku_model.dart';

/// 弹幕加载服务 - 支持网络和本地（适配B站非标准压缩格式）
class DanmakuLoader {
  final Dio _dio = Dio();

  /// 从网络 URL 加载弹幕
  Future<List<DanmakuItem>> fromUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      print('DanmakuLoader.fromUrl: 开始请求 $url');

      // 简化请求头：弹幕接口不需要Cookie，只需要Referer和UA即可
      final Map<String, String> finalHeaders = {
        'Referer': HttpString.baseUrl, // B站反爬必须带
        'User-Agent': BrowserUa.pc, // 模拟浏览器UA
        'Accept': 'application/xml,text/xml,*/*',
        // 可选：不声明Accept-Encoding也没问题，我们的解压逻辑会自动处理
        // 'Accept-Encoding': 'gzip, deflate',
      };
      // 合并用户自定义headers（如果有）
      if (headers != null) {
        finalHeaders.addAll(headers);
      }

      print('DanmakuLoader.fromUrl: headers = $finalHeaders');

      // 核心：拿原始二进制，不做任何提前解码
      final response = await _dio.get(
        url,
        options: Options(
          headers: finalHeaders,
          responseType: ResponseType.bytes,
        ),
      );

      print('DanmakuLoader.fromUrl: 状态码 ${response.statusCode}');
      print('DanmakuLoader.fromUrl: content-type = ${response.headers.value('content-type')}');
      final contentEncoding = response.headers.value('content-encoding')?.toLowerCase();
      print('DanmakuLoader.fromUrl: content-encoding = $contentEncoding');

      if (response.statusCode != 200 || response.data == null) {
        print('DanmakuLoader.fromUrl: 状态码非200或数据为空');
        return [];
      }

      // 手动解压，完全适配B站的压缩格式
      final Uint8List rawBytes = response.data as Uint8List;
      final xmlContent = _decompressDanmaku(rawBytes, contentEncoding);
      
      print('DanmakuLoader.fromUrl: 解压后字符长度 ${xmlContent.length}');
      final preview = xmlContent.length > 300 ? xmlContent.substring(0, 300) : xmlContent;
      print('DanmakuLoader.fromUrl: 解压后前300字符:\n$preview');

      final result = _parseByContent(xmlContent, uri: url);
      print('DanmakuLoader.fromUrl: 解析完成，共 ${result.length} 条弹幕');
      return result;
    } catch (e, stack) {
      print('DanmakuLoader.fromUrl: 异常 $e');
      print(stack);
      return [];
    }
  }

  /// 手动解压弹幕二进制数据（核心修复：适配B站RAW DEFLATE格式）
  String _decompressDanmaku(Uint8List bytes, String? contentEncoding) {
    // 数据过短，肯定没压缩，直接解码
    if (bytes.length < 10) {
      print('DanmakuLoader: 数据过短，未压缩，直接解码');
      return utf8.decode(bytes, allowMalformed: true);
    }

    // 优先通过二进制魔数判断格式，比响应头可靠得多（B站经常不按规范返回头）
    
    // 1. 先试GZIP：魔数是固定的 0x1F 0x8B
    if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
      try {
        print('DanmakuLoader: 魔数匹配GZIP，尝试解压');
        return utf8.decode(GZipCodec().decode(bytes));
      } catch (e) {
        print('DanmakuLoader: GZIP解压失败，继续尝试其他格式: $e');
      }
    }

    // 2. 试B站专用的RAW DEFLATE（无zlib头/校验尾，这就是之前解压失败的根源）
    try {
      print('DanmakuLoader: 尝试RAW DEFLATE解压（B站list.so专用格式）');
      return utf8.decode(ZLibCodec(raw: true).decode(bytes));
    } catch (e) {
      print('DanmakuLoader: RAW DEFLATE解压失败，继续尝试: $e');
    }

    // 3. 试标准ZLIB DEFLATE（带2字节头+4字节校验尾，常规deflate格式）
    try {
      print('DanmakuLoader: 尝试标准ZLIB DEFLATE解压');
      return utf8.decode(ZLibCodec().decode(bytes));
    } catch (e) {
      print('DanmakuLoader: ZLIB DEFLATE解压失败，继续尝试: $e');
    }

    // 4. 所有解压方式都失败，兜底直接解码（应对未压缩的极端情况）
    print('DanmakuLoader: 所有解压方式失败，兜底直接解码');
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 从本地文件加载弹幕
  Future<List<DanmakuItem>> fromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return [];
      final content = await file.readAsString(encoding: utf8);
      return _parseByContent(content, uri: path);
    } catch (e) {
      print('DanmakuLoader.fromFile: 异常 $e');
      return [];
    }
  }

  /// 根据内容自动检测格式
  List<DanmakuItem> _parseByContent(String content, {String? uri}) {
    print('DanmakuLoader._parseByContent: 开始检测格式');

    // 优先检测 XML 特征
    if (content.contains('<d') && content.contains('</d>')) {
      print('DanmakuLoader._parseByContent: 检测到 XML 标签，尝试解析');
      return _parseBiliXml(content);
    }

    // 尝试 JSON 解析
    try {
      final json = jsonDecode(content);
      print('DanmakuLoader._parseByContent: 检测到 JSON 格式');
      return _parseJson(json);
    } catch (_) {
      print('DanmakuLoader._parseByContent: 不是 JSON');
    }

    // 按文件扩展名兜底
    if (uri != null) {
      final lower = uri.toLowerCase();
      if (lower.endsWith('.xml')) {
        print('DanmakuLoader._parseByContent: 扩展名 .xml，尝试解析');
        return _parseBiliXml(content);
      }
      if (lower.endsWith('.json')) {
        try {
          final json = jsonDecode(content);
          print('DanmakuLoader._parseByContent: 扩展名 .json，解析 JSON');
          return _parseJson(json);
        } catch (_) {}
      }
    }

    // 最后强制尝试 XML（应对部分不规范格式）
    if (content.contains('<d')) {
      print('DanmakuLoader._parseByContent: 强制尝试作为 XML 解析');
      return _parseBiliXml(content);
    }

    print('DanmakuLoader._parseByContent: 无法识别格式');
    return [];
  }

  /// 解析 B站 XML 弹幕
  List<DanmakuItem> _parseBiliXml(String content) {
    final items = <DanmakuItem>[];
    print('DanmakuLoader._parseBiliXml: 开始解析 XML');

    try {
      XmlDocument? document;
      try {
        document = XmlDocument.parse(content);
      } catch (e) {
        print('DanmakuLoader._parseBiliXml: XML 解析失败: $e，尝试手动提取');
        final regExp = RegExp(r'<d\s+p="([^"]*)"\s*>([^<]*)</d>');
        final matches = regExp.allMatches(content);
        print('DanmakuLoader._parseBiliXml: 手动匹配到 ${matches.length} 个 <d> 标签');
        for (final match in matches) {
          if (match.groupCount >= 2) {
            final p = match.group(1) ?? '';
            final text = match.group(2)?.trim() ?? '';
            if (text.isEmpty) continue;
            final parts = p.split(',');
            if (parts.length < 4) continue;
            final time = double.tryParse(parts[0]) ?? 0.0;
            final mode = int.tryParse(parts[1]) ?? 1;
            final fontSize = int.tryParse(parts[2]) ?? 25;
            final color = int.tryParse(parts[3]) ?? 0xFFFFFFFF;
            items.add(DanmakuItem(
              content: text,
              color: color,
              progress: (time * 1000).round(),
              mode: mode,
              fontSize: fontSize,
            ));
          }
        }
        print('DanmakuLoader._parseBiliXml: 手动解析完成，共 ${items.length} 条');
        return items;
      }

      if (document == null) return items;
      final elements = document.findAllElements('d');
      print('DanmakuLoader._parseBiliXml: 找到 ${elements.length} 个 <d> 元素');
      for (final element in elements) {
        final p = element.getAttribute('p') ?? '';
        final parts = p.split(',');
        if (parts.length < 4) continue;

        final time = double.tryParse(parts[0]) ?? 0.0;
        final mode = int.tryParse(parts[1]) ?? 1;
        final fontSize = int.tryParse(parts[2]) ?? 25;
        final color = int.tryParse(parts[3]) ?? 0xFFFFFFFF;

        final text = element.text.trim();
        if (text.isEmpty) continue;

        items.add(DanmakuItem(
          content: text,
          color: color,
          progress: (time * 1000).round(),
          mode: mode,
          fontSize: fontSize,
        ));
      }
      print('DanmakuLoader._parseBiliXml: 解析完成，共 ${items.length} 条');
    } catch (e) {
      print('DanmakuLoader._parseBiliXml: 解析异常 $e');
    }
    return items;
  }

  /// 解析 JSON 弹幕
  List<DanmakuItem> _parseJson(dynamic json) {
    final items = <DanmakuItem>[];
    List<dynamic>? list;

    if (json is Map<String, dynamic>) {
      if (json.containsKey('comments') && json['comments'] is List) {
        list = json['comments'] as List<dynamic>;
        for (final item in list) {
          final content = item['content']?.toString() ?? '';
          final time = _parseTime(item['timepoint']);
          if (content.isNotEmpty) {
            items.add(DanmakuItem(
              content: content,
              color: 0xFFFFFFFF,
              progress: time,
              mode: 1,
              fontSize: 25,
            ));
          }
        }
        return items;
      }

      if (json.containsKey('result') && json['result'] is List) {
        list = json['result'] as List<dynamic>;
        for (final item in list) {
          final content = item['content']?.toString() ?? '';
          final time = _parseTime(item['playat'], isMillis: true);
          if (content.isNotEmpty) {
            items.add(DanmakuItem(
              content: content,
              color: 0xFFFFFFFF,
              progress: time,
              mode: 1,
              fontSize: 25,
            ));
          }
        }
        return items;
      }

      if (json.containsKey('data') && json['data'] is Map) {
        final data = json['data'] as Map<String, dynamic>;
        if (data.containsKey('list') && data['list'] is List) {
          list = data['list'] as List<dynamic>;
          for (final item in list) {
            final content = item['content']?.toString() ?? '';
            final time = _parseTime(item['time']);
            if (content.isNotEmpty) {
              items.add(DanmakuItem(
                content: content,
                color: 0xFFFFFFFF,
                progress: time,
                mode: 1,
                fontSize: 25,
              ));
            }
          }
        }
        return items;
      }
      return items;
    }

    if (json is List) {
      for (final item in json) {
        if (item is Map) {
          final content = item['content']?.toString() ?? '';
          final time = _parseTime(item['time'] ?? item['timepoint'] ?? item['playat']);
          if (content.isNotEmpty) {
            items.add(DanmakuItem(
              content: content,
              color: 0xFFFFFFFF,
              progress: time,
              mode: 1,
              fontSize: 25,
            ));
          }
        }
      }
      return items;
    }

    return items;
  }

  /// 解析时间
  int _parseTime(dynamic value, {bool isMillis = false}) {
    if (value == null) return 0;
    double time = 0.0;
    if (value is String) {
      time = double.tryParse(value) ?? 0.0;
    } else if (value is int) {
      time = value.toDouble();
    } else if (value is double) {
      time = value;
    } else {
      return 0;
    }

    if (isMillis || time > 10000) {
      return time.round();
    }
    return (time * 1000).round();
  }
}
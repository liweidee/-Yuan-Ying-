import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 从 JAR class 结构提取与 native/壳运行时有关的通用信息。
class JarClassProfile {
  final Map<String, JarClassInfo> classes;

  const JarClassProfile._(this.classes);

  factory JarClassProfile.fromArchive(Archive archive) {
    final classes = <String, JarClassInfo>{};
    for (final file in archive.files) {
      if (!file.isFile || !file.name.endsWith('.class')) continue;
      final info = JarClassInfo.tryParse(file.content);
      if (info != null) classes[info.name] = info;
    }
    return JarClassProfile._(classes);
  }

  /// 标准启动类若引用本 JAR 中声明了 native 方法的类，则整个 JAR 的
  /// SpiderHost 启动链都具备 native 激活能力。
  bool get bootstrapUsesNative {
    for (final name in const [
      'com/github/catvod/spider/Init',
      'com/github/catvod/spider/InitOrigin',
    ]) {
      final init = classes[name];
      if (init == null) continue;
      if (init.hasNativeMethods) return true;
      for (final reference in init.classReferences) {
        if (classes[reference]?.hasNativeMethods == true) return true;
      }
    }
    return false;
  }

  /// 判断当前入口是否直接或经父类链接入 native 方法。
  bool entryUsesNative(String className) {
    var current = className.replaceAll('.', '/');
    final visited = <String>{};
    for (var depth = 0; depth < 24 && visited.add(current); depth++) {
      final info = classes[current];
      if (info == null) return false;
      if (info.hasNativeMethods) return true;
      for (final reference in info.classReferences) {
        if (classes[reference]?.hasNativeMethods == true) return true;
      }
      final parent = info.superName;
      if (parent == null || parent.isEmpty) return false;
      current = parent;
    }
    return false;
  }
}

class JarClassInfo {
  final String name;
  final String? superName;
  final bool hasNativeMethods;
  final Set<String> classReferences;

  const JarClassInfo({
    required this.name,
    required this.superName,
    required this.hasNativeMethods,
    required this.classReferences,
  });

  static JarClassInfo? tryParse(dynamic rawContent) {
    if (rawContent is! List<int> || rawContent.length < 10) return null;
    final bytes = rawContent is Uint8List
        ? rawContent
        : Uint8List.fromList(rawContent);
    var offset = 0;

    int u1() {
      if (offset >= bytes.length) throw const FormatException('class EOF');
      return bytes[offset++];
    }

    int u2() => (u1() << 8) | u1();
    int u4() => (u2() << 16) | u2();

    void skip(int length) {
      offset += length;
      if (offset > bytes.length) {
        throw const FormatException('class EOF');
      }
    }

    void skipAttributes(int count) {
      for (var i = 0; i < count; i++) {
        u2();
        skip(u4());
      }
    }

    try {
      if (u4() != 0xCAFEBABE) return null;
      u2();
      u2();
      final constantCount = u2();
      final utf8Values = <int, String>{};
      final classIndexes = <int, int>{};
      for (var index = 1; index < constantCount; index++) {
        final tag = u1();
        switch (tag) {
          case 1:
            final length = u2();
            if (offset + length > bytes.length) return null;
            utf8Values[index] = utf8.decode(
              bytes.sublist(offset, offset + length),
              allowMalformed: true,
            );
            offset += length;
            break;
          case 3:
          case 4:
            skip(4);
            break;
          case 5:
          case 6:
            skip(8);
            index++;
            break;
          case 7:
            classIndexes[index] = u2();
            break;
          case 8:
            skip(2);
            break;
          case 9:
          case 10:
          case 11:
          case 12:
          case 17:
          case 18:
            skip(4);
            break;
          case 15:
            skip(3);
            break;
          case 16:
          case 19:
          case 20:
            skip(2);
            break;
          default:
            return null;
        }
      }

      String? classNameAt(int classIndex) {
        final nameIndex = classIndexes[classIndex];
        return nameIndex == null ? null : utf8Values[nameIndex];
      }

      skip(2); // access flags
      final thisName = classNameAt(u2());
      final superName = classNameAt(u2());
      if (thisName == null || thisName.isEmpty) return null;

      final references = <String>{
        for (final entry in classIndexes.entries)
          if (utf8Values[entry.value] case final String name
              when name.isNotEmpty)
            name,
      };

      final interfaceCount = u2();
      skip(interfaceCount * 2);

      final fieldCount = u2();
      for (var i = 0; i < fieldCount; i++) {
        skip(6);
        skipAttributes(u2());
      }

      var hasNativeMethods = false;
      final methodCount = u2();
      for (var i = 0; i < methodCount; i++) {
        final accessFlags = u2();
        skip(4);
        if (accessFlags & 0x0100 != 0) hasNativeMethods = true;
        skipAttributes(u2());
      }

      return JarClassInfo(
        name: thisName,
        superName: superName,
        hasNativeMethods: hasNativeMethods,
        classReferences: references,
      );
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }
}

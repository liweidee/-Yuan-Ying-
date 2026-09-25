import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// QQ 音乐 / 网易云签名工具
class LxSignUtils {
  LxSignUtils._();

  // ==================== QQ 音乐 zzc 签名 ====================

  static const List<int> _part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19];
  static const List<int> _part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5];
  static const List<int> _scrambleValues = [
    89, 39, 179, 150, 218, 82, 58, 252, 177, 52,
    186, 123, 120, 64, 242, 133, 143, 161, 121, 179,
  ];

  /// QQ 音乐 zzc 签名
  static String zzcSign(String text) {
    final bytes = utf8.encode(text);
    final digest = sha1.convert(bytes);
    final hash = digest.toString();

    String pickHash(int idx) => idx < hash.length ? hash[idx] : '';

    final part1 = _part1Indexes.map(pickHash).join();
    final part2 = _part2Indexes.map(pickHash).join();

    final part3 = List<int>.generate(20, (i) {
      final hashByte = int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16);
      return _scrambleValues[i] ^ hashByte;
    });

    final b64Part = base64.encode(part3).replaceAll(RegExp(r'[\\/+=]'), '');

    return 'zzc${part1}${b64Part}${part2}'.toLowerCase();
  }

  // ==================== 网易云 eapi 加密 ====================

  static const String _eapiKey = 'e82ckenh8dichen8';

  /// 网易云 eapi 参数加密
  static String eapi(String url, String text) {
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = md5.convert(utf8.encode(message)).toString();
    final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';

    final keyBytes = utf8.encode(_eapiKey);
    final key = Key(keyBytes);
    final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: 'PKCS7'));
    final encrypted = encrypter.encryptBytes(utf8.encode(data));

    return encrypted.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  // ==================== 通用工具 ====================

  /// HTML 实体解码
  static String decodeHtml(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// 格式化文件大小
  static String formatSize(dynamic size) {
    final bytes =
        size is int ? size : int.tryParse(size?.toString() ?? '0') ?? 0;
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double sizeValue = bytes.toDouble();
    while (sizeValue >= 1024 && i < units.length - 1) {
      sizeValue /= 1024;
      i++;
    }
    return '${sizeValue.toStringAsFixed(2)} ${units[i]}';
  }
}
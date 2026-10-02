// lib/modules/download/utils/aes_decryptor.dart
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

/// AES-128-CBC 解密（HLS 分片专用）
///
/// HLS 规范：
/// - 加密方法为 AES-128
/// - 模式为 CBC
/// - Padding 为 PKCS7
/// - IV 如果 m3u8 没给，则用 media sequence number 的 16 字节大端表示
abstract final class AesDecryptor {
  /// 解密单个分片
  ///
  /// [encrypted] 加密数据
  /// [keyBytes] 16 字节密钥
  /// [iv] 16 字节 IV；为 null 时用 [mediaSequence] 计算
  /// [mediaSequence] 该分片的媒体序号
  static Uint8List decrypt({
    required Uint8List encrypted,
    required Uint8List keyBytes,
    Uint8List? iv,
    int mediaSequence = 0,
  }) {
    if (keyBytes.length != 16) {
      throw ArgumentError('AES-128 key 必须是 16 字节');
    }

    final key = enc.Key(keyBytes);
    final ivBytes = iv ?? computeIv(mediaSequence);
    final ivObj = enc.IV(ivBytes);

    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc),
    );

    final decrypted = encrypter.decryptBytes(
      enc.Encrypted(encrypted),
      iv: ivObj,
    );

    return Uint8List.fromList(decrypted);
  }

  /// 将 media sequence number 转为 16 字节大端 IV
  static Uint8List computeIv(int mediaSequence) {
    final iv = Uint8List(16);
    final bd = ByteData.view(iv.buffer);
    // 前 8 字节为 0，后 8 字节为 mediaSequence 大端
    bd.setUint64(8, mediaSequence, Endian.big);
    return iv;
  }

  /// 解析 m3u8 中的 IV 字符串
  ///
  /// 支持格式：
  /// - "0x0123456789abcdef0123456789abcdef"
  /// - "0123456789abcdef0123456789abcdef"
  static Uint8List? parseIv(String? ivStr) {
    if (ivStr == null || ivStr.isEmpty) return null;
    var hex = ivStr.trim();
    if (hex.startsWith('0x') || hex.startsWith('0X')) {
      hex = hex.substring(2);
    }
    if (hex.length != 32) return null;

    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
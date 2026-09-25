import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// 酷我 wbd 接口加密工具
class LxWbdCrypto {
  LxWbdCrypto._();

  static const String _aesKeyBase64 = 'cFcnPcf6Kb85RC1y3V6M5A==';
  static const String _appId = 'y67sprxhhpws';

  static final _aesKeyBytes = base64Decode(_aesKeyBase64);

  /// AES-128-ECB + PKCS7 padding 加密
  ///
  /// 输入为 Base64 字符串（内容为 JSON 的 UTF8 字节的 Base64）
  /// 输出为 Base64 字符串
  static String _aesEncrypt(String base64Input) {
    final key = Key(_aesKeyBytes);
    final encrypter = Encrypter(
      AES(key, mode: AESMode.ecb, padding: 'PKCS7'),  // ← 改为 PKCS7
    );
    final inputBytes = base64Decode(base64Input);
    final encrypted = encrypter.encryptBytes(inputBytes);
    return encrypted.base64;
  }

  /// AES-128-ECB + PKCS7 padding 解密
  static String _aesDecrypt(String base64Input) {
    final key = Key(_aesKeyBytes);
    final encrypter = Encrypter(
      AES(key, mode: AESMode.ecb, padding: 'PKCS7'),  // ← 改为 PKCS7
    );
    final encrypted = Encrypted(base64Decode(base64Input));
    return encrypter.decrypt(encrypted);
  }

  static String _createSign(String data, int time) {
    final str = '$_appId$data$time';
    return md5.convert(utf8.encode(str)).toString().toUpperCase();
  }

  static String buildParam(Map<String, dynamic> jsonData) {
    final jsonStr = jsonEncode(jsonData);
    final base64Data = base64Encode(utf8.encode(jsonStr));
    final time = DateTime.now().millisecondsSinceEpoch;
    final encodeData = _aesEncrypt(base64Data);
    final sign = _createSign(encodeData, time);
    return 'data=${Uri.encodeComponent(encodeData)}'
        '&time=$time'
        '&appId=$_appId'
        '&sign=$sign';
  }

  static Map<String, dynamic> decodeData(String raw) {
    var data = raw.trim();
    try {
      data = Uri.decodeComponent(data);
    } catch (_) {}
    final jsonStr = _aesDecrypt(data);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  static String generateReqId() {
    String t() {
      final v = (65536 * (1 + DateTime.now().microsecondsSinceEpoch % 1)).toInt();
      return v.toRadixString(16).substring(1);
    }
    return '${t()}${t()}${t()}${t()}${t()}${t()}${t()}${t()}';
  }
}
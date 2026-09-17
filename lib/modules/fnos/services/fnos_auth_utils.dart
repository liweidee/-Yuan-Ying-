import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// 飞牛影视 Authx 签名工具
class FnosAuthUtils {
  static const _apiKey = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  static const _apiSecret = '16CCEB3D-AB42-077D-36A1-F355324E4237';

  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static String generateNonce() =>
      (100000 + Random().nextInt(900000)).toString();

  /// 生成 Authx 请求头
  ///
  /// [urlPath] 必须是 URI 的 path 部分，例如 `/v/api/v1/login`
  /// [jsonBody] 是 POST 请求体的 JSON 字符串
  /// [query] 是 GET 请求的查询参数（会按 key 排序后拼接再 MD5）
  static String genAuthx(
    String urlPath,
    String? jsonBody, {
    Map<String, dynamic>? query,
  }) {
    final nonce = generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final dataMd5 = _buildDataMd5(jsonBody, query);
    final parts = [_apiKey, urlPath, nonce, timestamp, dataMd5, _apiSecret];
    final sign = md5Hex(parts.join('_'));
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  /// 按 fntv 官方规则计算 dataMd5：
  /// - 有 POST body → md5(body)
  /// - 有 GET query → md5(排序后 k1=v1&k2=v2)
  /// - 都无 → md5('')
  static String _buildDataMd5(String? jsonBody, Map<String, dynamic>? query) {
    if (jsonBody != null) return md5Hex(jsonBody);
    if (query != null && query.isNotEmpty) {
      final sorted = query.entries
          .where((e) => e.value != null)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return md5Hex(sorted.map((e) => '${e.key}=${e.value}').join('&'));
    }
    return md5Hex('');
  }

  /// 播放流请求中 ip 字段使用的账号哈希
  static String md5Account(String account) => md5Hex(account);
}
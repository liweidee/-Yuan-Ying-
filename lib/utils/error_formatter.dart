import 'package:yuanying/utils/business_exception.dart';

/// 统一错误分类器
///
/// 前缀约定：
/// - 网络异常：     Dio/Socket/Timeout/Handshake 层
/// - 接口异常：     HTTP 状态码 4xx/5xx
/// - 解析失败：     JSON/格式解析层
/// - 脚本执行失败： JS/Python 脚本运行时
/// - 源返回错误：   源接口自己返回的 error 字段
/// - 切换源失败：   SourceManager 切源失败（操作层前缀）
/// - 请求异常：     兜底，未知异常类型
///
/// 幂等保证：
/// - 所有方法对"已带对应前缀的输入"原样返回，不重复加
/// - 所有方法对"已带任何已知前缀的 String"不做二次分类
class ErrorFormatter {
  ErrorFormatter._();

  /// 所有已知前缀（用于幂等判断）
  static const _knownPrefixes = [
    '网络异常：',
    '接口异常：',
    '解析失败：',
    '脚本执行失败：',
    '源返回错误：',
    '切换源失败：',
    '请求异常：',
  ];

  /// 判断字符串是否已带任何已知前缀
  static bool hasAnyPrefix(String s) {
    for (final p in _knownPrefixes) {
      if (s.startsWith(p)) return true;
    }
    return false;
  }

  /// 尝试把异常分类为带前缀的文案。
  /// 分类成功返回带前缀文案，分类失败返回 null（不兜底）。
  ///
  /// 与 [formatException] 的区别：本方法分类失败返回 null，
  /// 让调用方能区分"分类成功"和"分类失败"，决定是否用其他兜底。
  static String? tryClassifyException(Object e) {
    final str = e.toString();
    if (str.contains('TimeoutException') || str.contains('timeout')) {
      return '网络异常：请求超时';
    }
    if (str.contains('SocketException') || str.contains('Connection')) {
      return '网络异常：连接失败';
    }
    if (str.contains('HandshakeException')) {
      return '网络异常：SSL 握手失败';
    }
    if (str.contains('FormatException') || str.contains('JsonParse')) {
      return '解析失败：响应格式异常';
    }
    return null;
  }

  /// 通用异常格式化（幂等）
  ///
  /// 优先级：
  /// 1. BusinessException → 原样透传 message（业务提示无前缀）
  /// 2. String 已带前缀 → 原样返回（幂等）
  /// 3. 尝试分类 → 返回分类结果
  /// 4. 分类失败 → 返回 "请求异常：${runtimeType}"
  static String formatException(Object e) {
    if (e is BusinessException) return e.message;
    if (e is String && hasAnyPrefix(e)) return e;
    return tryClassifyException(e) ?? '请求异常：${e.runtimeType}';
  }

  /// HTTP 状态码格式化
  static String formatHttpError(int statusCode) {
    if (statusCode >= 500) return '接口异常：服务器错误 ($statusCode)';
    if (statusCode == 404) return '接口异常：接口不存在 (404)';
    if (statusCode == 403) return '接口异常：拒绝访问 (403)';
    if (statusCode == 401) return '接口异常：需要认证 (401)';
    if (statusCode >= 400) return '接口异常：请求错误 ($statusCode)';
    return '接口异常：HTTP $statusCode';
  }

  /// 源返回的 error 字段格式化（幂等）
  ///
  /// - 已带前缀 → 原样返回
  /// - 裸 String → 先尝试分类，分类失败才加 "源返回错误："
  static String formatSourceError(String sourceError) {
    if (hasAnyPrefix(sourceError)) return sourceError;
    final classified = tryClassifyException(sourceError);
    if (classified != null) return classified;
    return '源返回错误：$sourceError';
  }

  /// 脚本执行异常格式化（幂等）
  static String formatScriptError(Object e) {
    if (e is String && hasAnyPrefix(e)) return e;
    final str = e.toString();
    if (str.contains('TimeoutException') || str.contains('timeout')) {
      return '脚本执行失败：脚本超时';
    }
    if (str.contains('SyntaxError')) {
      return '脚本执行失败：脚本语法错误';
    }
    if (str.contains('ReferenceError')) {
      return '脚本执行失败：脚本引用错误';
    }
    if (str.contains('TypeError')) {
      return '脚本执行失败：脚本类型错误';
    }
    return '脚本执行失败：${e.runtimeType}';
  }

  /// 切源失败格式化（幂等）
  ///
  /// - String 已带 "切换源失败：" → 原样返回（防双重）
  /// - String 已带其他前缀（如 "网络异常："）→ 加 "切换源失败：" 前缀
  /// - String 裸文案 → 加 "切换源失败：" 前缀
  /// - Exception → "切换源失败：" + formatException(e)
  static String formatSwitchError(Object e) {
    if (e is String) {
      if (e.startsWith('切换源失败：')) return e;
      return '切换源失败：$e';
    }
    return '切换源失败：${formatException(e)}';
  }
}
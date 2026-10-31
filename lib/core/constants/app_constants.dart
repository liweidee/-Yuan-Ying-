/// 应用常量
abstract final class AppConstants {
  static const String appName = '源影';
  static const String version = '1.0.0';
  
  static final urlRegex = RegExp(
    r'https?://[-A-Za-z0-9+&@#/%?=~_|!:,.;]+[-A-Za-z0-9+&@#/%=~_|]',
  );
  
  static const baseHeaders = {
    'env': 'prod',
  };
  
  /// 网络请求超时时间
  static const int connectTimeout = 15000;
  static const int receiveTimeout = 30000;
  
  /// 分页大小
  static const int pageSize = 20;
}

/// 详情类型常量（用于收藏/历史记录区分）
class DetailType {
  static const String video = 'video';
  static const String audio = 'audio';
  static const String novel = 'novel';
  static const String manga = 'manga';
}
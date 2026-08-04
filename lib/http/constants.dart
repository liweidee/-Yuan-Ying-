abstract final class HttpString {
  // 仅保留通用常量，删除所有B站域名
  static const String baseUrl = '';  // 后续替换为您自己的域名
  
  // 通用正则
  static final urlRegex = RegExp(
    r'https?://[-A-Za-z0-9+&@#/%?=~_|!:,.;]+[-A-Za-z0-9+&@#/%=~_|]',
  );
}
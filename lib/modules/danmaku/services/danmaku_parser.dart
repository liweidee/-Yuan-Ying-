import 'package:yuanying/modules/danmaku/models/danmaku_model.dart';
import 'danmaku_loader.dart';

/// 弹幕解析器 - 对外统一接口
class DanmakuParser {
  final DanmakuLoader _loader = DanmakuLoader();

  /// 从网络加载弹幕
  Future<List<DanmakuItem>> loadFromUrl(
    String url, {
    Map<String, String>? headers,
  }) {
    return _loader.fromUrl(url, headers: headers);
  }

  /// 从本地文件加载弹幕
  Future<List<DanmakuItem>> loadFromFile(String path) {
    return _loader.fromFile(path);
  }
}
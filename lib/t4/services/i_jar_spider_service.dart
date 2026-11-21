import 'package:yuanying/t4/services/i_spider_service.dart';

/// Android MethodChannel 与 Windows SpiderHost 子进程的共用生命周期契约。
abstract class IJarSpiderService implements ISpiderService {
  void configureJarSource(String source, {String configBaseUrl = ''});

  Future<void> ensureReady();

  Future<void> release();
}

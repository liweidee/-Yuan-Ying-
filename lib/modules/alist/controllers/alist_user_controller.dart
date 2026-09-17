import 'package:collection/collection.dart';
import 'package:get/get.dart';
import '../net/alist_dio_utils.dart';
import 'alist_server_controller.dart';

class AlistUser {
  final String serverUrl;
  final String baseUrl;
  final String username;
  final String? password;
  final String? token;
  final String? basePath;
  final bool guest;

  AlistUser({
    this.serverUrl = '',
    this.baseUrl = '',
    this.username = 'guest',
    this.password,
    this.token,
    this.basePath,
    this.guest = true,
  });

  AlistUser copyWith({
    String? serverUrl,
    String? baseUrl,
    String? username,
    String? password,
    String? token,
    String? basePath,
    bool? guest,
  }) =>
      AlistUser(
        serverUrl: serverUrl ?? this.serverUrl,
        baseUrl: baseUrl ?? this.baseUrl,
        username: username ?? this.username,
        password: password ?? this.password,
        token: token ?? this.token,
        basePath: basePath ?? this.basePath,
        guest: guest ?? this.guest,
      );
}

class AlistUserController extends GetxController {
  final user = AlistUser().obs;
  final searchIndex = ''.obs;

  /// 登录成功后调用（由登录对话框或启动恢复触发）
  void login(AlistUser u, {bool fromCache = false}) {
    user.value = u;
    searchIndex.value = '';
    if (fromCache || u.basePath == null || u.basePath!.isEmpty) {
      requestBasePath();
    }
    loadSettings();
  }

  void logout() {
    searchIndex.value = '';
    final u = user.value;
    user.value = AlistUser(
      serverUrl: u.serverUrl,
      baseUrl: u.baseUrl,
      username: u.username,
      password: u.password,
      guest: false,
      token: null,
    );
  }

  /// 切换服务器时，用新服务器的 token 重新初始化 DioUtils
  String? _lastServerId;

  void switchServer(String serverId, {required String serverUrl, required bool ignoreSSLError}) {
    // 如果已经切换到该服务器，跳过
    if (_lastServerId == serverId && user.value.serverUrl == serverUrl) {
      return;
    }
    _lastServerId = serverId;

    AlistDioUtils.instance.configAgain(
      '${serverUrl}api/',
      ignoreSSLError,
      serverId: serverId,
    );
    final serverCtrl = Get.find<AlistServerController>();
    final server = serverCtrl.servers.firstWhereOrNull((s) => s.id == serverId);
    if (server == null) return;
    login(
      AlistUser(
        serverUrl: server.serverUrl,
        baseUrl: '${server.serverUrl}api/',
        username: server.username ?? 'guest',
        password: server.password,
        token: serverCtrl.getToken(serverId),
        guest: server.guest,
        basePath: user.value.basePath,
      ),
      fromCache: true,
    );
  }

  /// 获取 basePath
  Future<void> requestBasePath() async {
    try {
      final info = await AlistDioUtils.instance.getMyInfo();
      final cur = user.value;
      user.value = cur.copyWith(basePath: info.basePath);
    } catch (_) {
      // 忽略（游客模式下可能失败）
    }
  }

  /// 加载公共设置
  Future<void> loadSettings() async {
    try {
      final settings = await AlistDioUtils.instance.getPublicSettings();
      if (settings?.searchIndex != null &&
          settings!.searchIndex!.isNotEmpty &&
          settings.searchIndex != 'none') {
        searchIndex.value = settings.searchIndex!;
      } else {
        searchIndex.value = '';
      }
    } catch (_) {
      searchIndex.value = '';
    }
  }
}
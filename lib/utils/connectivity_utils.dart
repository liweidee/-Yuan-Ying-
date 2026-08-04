import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:yuanying/utils/platform_utils.dart';

abstract final class ConnectivityUtils {
  static Future<bool> get isWiFi async {
    try {
      return PlatformUtils.isMobile &&
          (await Connectivity().checkConnectivity()).contains(
            ConnectivityResult.wifi,
          );
    } catch (_) {
      return true;
    }
  }
}
// lib/utils/storage_stub.dart
// 非 Web 平台的桩实现（Windows/Android/iOS）

class StorageWebHelper {
  static void saveCustomSites(List<Map<String, dynamic>> sites) {
    // 非 Web 平台不使用此方法
  }

  static List<Map<String, dynamic>> getCustomSites() {
    return [];
  }
}
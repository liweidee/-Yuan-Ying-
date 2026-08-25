// lib/modules/live/services/live_storage_service.dart
import 'package:yuanying/core/constants/storage_keys.dart';
import 'package:yuanying/modules/live/models/live_channel.dart';
import 'package:yuanying/utils/storage_manager.dart';

class LiveStorageService {
  /// 加载指定配置的频道列表
  static List<LiveChannel> loadChannels(String configKey) {
    final key = 'live_channels_$configKey';
    final list = StorageManager.getSetting<List<dynamic>>(key) ?? [];
    return list.map((e) => LiveChannel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// 保存频道列表
  static Future<void> saveChannels(String configKey, List<LiveChannel> channels) async {
    final key = 'live_channels_$configKey';
    await StorageManager.setSetting(
      key,
      channels.map((c) => c.toJson()).toList(),
    );
  }

  /// 清除指定配置的缓存
  static Future<void> clearChannels(String configKey) async {
    final key = 'live_channels_$configKey';
    await StorageManager.deleteSetting(key);
  }
}
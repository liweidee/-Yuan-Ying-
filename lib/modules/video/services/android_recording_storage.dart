import 'package:flutter/services.dart';

abstract final class AndroidRecordingStorage {
  static const MethodChannel _channel = MethodChannel(
    'com.example.yuanying/storage',
  );

  static Future<bool> hasAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasRecordingStorageAccess') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestAccess() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestRecordingStorageAccess',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getRecordingDirectory() async {
    try {
      return _channel.invokeMethod<String>('getRecordingDirectory');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> scanFile(String path) async {
    try {
      return await _channel.invokeMethod<bool>('scanRecordingFile', {
            'path': path,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

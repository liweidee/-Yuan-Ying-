import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

export 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart'
    show
        Permission,
        PermissionStatus,
        PermissionStatusGetters,
        PermissionWithService,
        FuturePermissionStatusGetters,
        ServiceStatus,
        ServiceStatusGetters,
        FutureServiceStatusGetters;

PermissionHandlerPlatform get _handler => PermissionHandlerPlatform.instance;

Future<bool> openAppSettings() => _handler.openAppSettings();

extension PermissionActions on Permission {
  static VoidCallback? _onDenied;
  static VoidCallback? _onGranted;
  static VoidCallback? _onPermanentlyDenied;
  static VoidCallback? _onRestricted;
  static VoidCallback? _onLimited;
  static VoidCallback? _onProvisional;

  void onDeniedCallback(VoidCallback? callback) => _onDenied = callback;
  void onGrantedCallback(VoidCallback? callback) => _onGranted = callback;
  void onPermanentlyDeniedCallback(VoidCallback? callback) => _onPermanentlyDenied = callback;
  void onRestrictedCallback(VoidCallback? callback) => _onRestricted = callback;
  void onLimitedCallback(VoidCallback? callback) => _onLimited = callback;
  void onProvisionalCallback(VoidCallback? callback) => _onProvisional = callback;

  Future<PermissionStatus> get status => _handler.checkPermissionStatus(this);
  FutureOr<bool> get shouldShowRequestRationale {
    if (!Platform.isAndroid) return false;
    return _handler.shouldShowRequestPermissionRationale(this);
  }

  Future<PermissionStatus> request() async {
    final permissionStatus = (await [this].request())[this] ?? PermissionStatus.denied;
    (switch (permissionStatus) {
      .denied => _onDenied,
      .granted => _onGranted,
      .restricted => _onRestricted,
      .limited => _onLimited,
      .permanentlyDenied => _onPermanentlyDenied,
      .provisional => _onProvisional,
    })?.call();
    return permissionStatus;
  }
}

extension PermissionCheckShortcuts on Permission {
  Future<bool> get isGranted => status.isGranted;
  Future<bool> get isDenied => status.isDenied;
  Future<bool> get isRestricted => status.isRestricted;
  Future<bool> get isLimited => status.isLimited;
  Future<bool> get isPermanentlyDenied => status.isPermanentlyDenied;
  Future<bool> get isProvisional => status.isProvisional;
}

extension ServicePermissionActions on PermissionWithService {
  Future<ServiceStatus> get serviceStatus => _handler.checkServiceStatus(this);
}

extension PermissionListActions on List<Permission> {
  Future<Map<Permission, PermissionStatus>> request() => _handler.requestPermissions(this);
}
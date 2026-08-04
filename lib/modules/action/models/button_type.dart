// lib/modules/action/models/button_type.dart
/// 按钮类型枚举
/// 严格对应 DrPlayer 的 ButtonType
/// 值必须与 DrPlayer 保持一致：0=确定+取消, 1=仅确定, 2=仅取消, 3=自定义
enum ButtonType {
  /// 确定 + 取消 (0)
  okCancel,

  /// 仅确定 (1)
  okOnly,

  /// 仅取消 (2)
  cancelOnly,

  /// 自定义 (3) - 可能包含重置等额外按钮
  custom,
}

/// ButtonType 扩展方法
extension ButtonTypeExtension on ButtonType {
  /// 从整数解析 ButtonType
  static ButtonType fromInt(int value) {
    switch (value) {
      case 0:
        return ButtonType.okCancel;
      case 1:
        return ButtonType.okOnly;
      case 2:
        return ButtonType.cancelOnly;
      case 3:
        return ButtonType.custom;
      default:
        return ButtonType.okCancel;
    }
  }

  /// 转换为整数
  int get toInt {
    switch (this) {
      case ButtonType.okCancel:
        return 0;
      case ButtonType.okOnly:
        return 1;
      case ButtonType.cancelOnly:
        return 2;
      case ButtonType.custom:
        return 3;
    }
  }

  /// 是否显示确定按钮
  bool get showOk {
    switch (this) {
      case ButtonType.okCancel:
      case ButtonType.okOnly:
      case ButtonType.custom:
        return true;
      case ButtonType.cancelOnly:
        return false;
    }
  }

  /// 是否显示取消按钮
  bool get showCancel {
    switch (this) {
      case ButtonType.okCancel:
      case ButtonType.cancelOnly:
      case ButtonType.custom:
        return true;
      case ButtonType.okOnly:
        return false;
    }
  }

  /// 是否显示重置按钮（仅 custom 类型）
  bool get showReset => this == ButtonType.custom;
}

/// 规范化按钮类型值（对应 DrPlayer 的 normalizeButtonType）
int normalizeButtonType(dynamic value) {
  if (value == null) return 0;
  if (value is int) {
    if (value >= 0 && value <= 3) return value;
  }
  // 无效值默认返回 3（custom），与 DrPlayer 一致
  return 3;
}
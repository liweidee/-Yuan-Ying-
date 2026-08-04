import 'dart:math' as math;
import 'package:flutter/widgets.dart';

extension NumExtension on num {
  int cacheSize(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return (toDouble() * pixelRatio).round();
  }

  double toPrecision(int fractionDigits) {
    if (this == 0) return 0.0;
    final mod = math.pow(10, fractionDigits).toDouble();
    return (this * mod).roundToDouble() / mod;
  }

  /// 判断两个浮点数是否相等（带容差）
  bool equals(num other, [double tolerance = 1e-6]) {
    return (toDouble() - other.toDouble()).abs() < tolerance;
  }
}

extension IntExt on int? {
  int? operator +(int other) => this == null ? null : this! + other;
  int? operator -(int other) => this == null ? null : this! - other;
}

extension DoubleExt on double {
  double lerp(double a, double b) {
    assert(
      a.isFinite,
      'Cannot interpolate between finite and non-finite values',
    );
    assert(
      b.isFinite,
      'Cannot interpolate between finite and non-finite values',
    );
    assert(isFinite, 't must be finite when interpolating between values');
    return a * (1.0 - this) + b * this;
  }
}
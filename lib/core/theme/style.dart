import 'package:flutter/material.dart';

abstract final class Style {
  static const double cardSpace = 8.0;
  static const double safeSpace = 12.0;
  static const double paddingSmall = 4.0;
  static const double paddingMedium = 8.0;
  static const double paddingLarge = 16.0;
  static const double topBarHeight = 52.0;

  static const Radius imgRadius = Radius.circular(10);
  static const BorderRadius mdRadius = BorderRadius.all(imgRadius);
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(16));
  static const BorderRadius bottomSheetRadius = BorderRadius.vertical(
    top: Radius.circular(18),
  );

  static const double aspectRatio = 16 / 10;
  static const double aspectRatio16x9 = 16 / 9;

  static const BoxConstraints dialogFixedConstraints = BoxConstraints.tightFor(
    width: 420,
  );

  static const ButtonStyle buttonStyle = ButtonStyle(
    visualDensity: VisualDensity(horizontal: -2, vertical: -1.25),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static const Duration animDuration = Duration(milliseconds: 300);
  static const Duration shortAnimDuration = Duration(milliseconds: 150);
}
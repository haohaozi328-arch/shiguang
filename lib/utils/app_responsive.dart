import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppResponsive {
  const AppResponsive._();

  static const double compactWidth = 360;
  static const double wideWidth = 600;

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isCompact(BuildContext context) =>
      sizeOf(context).width < compactWidth;

  static bool isWide(BuildContext context) =>
      sizeOf(context).width >= wideWidth;

  static double horizontalPadding(BuildContext context) {
    final width = sizeOf(context).width;
    if (width < compactWidth) {
      return 10;
    }
    if (width >= wideWidth) {
      return 20;
    }
    return 12;
  }

  static double bottomNavReserve(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(92, 76 + bottomInset);
  }

  static double noteFabBottom(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(90, 72 + bottomInset);
  }

  static double courseCardWidth(BuildContext context) {
    final width = sizeOf(context).width;
    return (width * 0.58).clamp(178.0, 220.0).toDouble();
  }

  static double addCardWidth(BuildContext context) {
    final width = sizeOf(context).width;
    return (width * 0.46).clamp(150.0, 170.0).toDouble();
  }

  static double courseCardHeight(BuildContext context) {
    return isCompact(context) ? 156 : 165;
  }

  static double voiceSheetHeight(BuildContext context) {
    final height = sizeOf(context).height;
    final ratio = height < 700 ? 0.62 : 0.52;
    return (height * ratio).clamp(360.0, 560.0).toDouble();
  }
}

import 'package:flutter/material.dart';

class AppColors {
  static const mint = Color(0xFFA8EDDA);
  static const sky = Color(0xFFC2E9FB);
  static const blush = Color(0xFFFDD5E8);
  static const lav = Color(0xFFDDD0FF);
  static const textDark = Color(0xFF1E2D4A);
  static const textSub = Color(0xFF6B82A8);
  static const glass = Color(0x0FFFFFFF);
  static const glass2 = Color(0x0DFFFFFF);
  static const gline = Color(0x4DD1D5DB);
  static const glassLine = gline;

  static const mintGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA8EDDA), Color(0xFFC2E9FB)],
  );
  static const lavGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDDD0FF), Color(0xFFC2D2FF)],
  );
  static const blushGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFDD5E8), Color(0xFFFFDCB9)],
  );
  static const skyGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC2E9FB), Color(0xFFA8EDDA)],
  );
}

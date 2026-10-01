import 'package:flutter/material.dart';

import 'colors.dart';

// Noto Sans covers Devanagari (Hindi/Marathi) + Latin. Falls back to
// system sans where the bundled font is unavailable.
const String kFontFamily = 'Noto Sans';

class AppTypography {
  static const TextStyle display = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: kInk,
    letterSpacing: -0.5,
    height: 1.2,
  );
  static const TextStyle title = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: kInk,
    height: 1.3,
  );
  static const TextStyle titleSmall = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: kInk,
    height: 1.35,
  );
  static const TextStyle body = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: kInk,
    height: 1.5,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: kInkMuted,
    height: 1.45,
  );
  static const TextStyle total = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: kForest,
    height: 1.2,
  );
  static const TextStyle button = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    height: 1.3,
  );

  static TextTheme textTheme() => const TextTheme(
        displaySmall: display,
        titleLarge: title,
        titleMedium: titleSmall,
        bodyLarge: body,
        bodyMedium: bodySmall,
        labelLarge: button,
      );
}

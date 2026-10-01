import 'package:flutter/material.dart';

import 'colors.dart';
import 'dimensions.dart';
import 'typography.dart';

/// Light-first, outdoor-readable theme (design.md palette).
/// No shadows — hierarchy comes from borders + background colour,
/// which is cheaper to render on low-end GPUs.
ThemeData buildLightAppTheme() {
  final colorScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: kForest,
    onPrimary: Colors.white,
    secondary: kSage,
    onSecondary: kInk,
    error: kError,
    onError: Colors.white,
    surface: kSurfaceCard,
    onSurface: kInk,
  );

  final textTheme = AppTypography.textTheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kSurface,
    dividerColor: kSurfaceMuted,
    fontFamily: kFontFamily,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: kInk,
      ),
    ),
    cardTheme: CardThemeData(
      color: kSurfaceCard,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        side: const BorderSide(color: kSurfaceMuted, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kForest,
        side: const BorderSide(color: kForest, width: 1.5),
        minimumSize: const Size(64, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kForest),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kForest,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kSurfaceCard,
      selectedItemColor: kForest,
      unselectedItemColor: kInkMuted,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurfaceCard,
      indicatorColor: kSage.withValues(alpha: 0.35),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kSurfaceMuted),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kSurfaceMuted),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kForest, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSurfaceCard,
      selectedColor: kSage.withValues(alpha: 0.35),
      labelStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: 14,
        color: kInk,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: kSurfaceMuted),
      ),
      side: const BorderSide(color: kSurfaceMuted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

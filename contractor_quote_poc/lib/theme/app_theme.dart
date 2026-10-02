import 'package:flutter/material.dart';

import 'colors.dart';
import 'dimensions.dart';
import 'typography.dart';

/// Light theme for outdoor, glare-prone use: one warm off-white canvas, one
/// deep green accent, and hierarchy carried by borders and spacing instead of
/// shadows (cheaper to render on low-end GPUs).
ThemeData buildLightAppTheme() {
  final colorScheme = const ColorScheme(
    brightness: Brightness.light,
    primary: kForest,
    onPrimary: Colors.white,
    primaryContainer: kSage,
    onPrimaryContainer: kInk,
    secondary: kSage,
    onSecondary: kInk,
    error: kError,
    onError: Colors.white,
    surface: kSurfaceCard,
    onSurface: kInk,
  );

  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppDimensions.buttonRadius)),
    borderSide: BorderSide(color: kSurfaceMuted),
  );
  const focusedFieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppDimensions.buttonRadius)),
    borderSide: BorderSide(color: kForest, width: AppDimensions.focusBorderWidth),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kSurface,
    dividerColor: kSurfaceMuted,
    fontFamily: kFontFamily,
    textTheme: AppTypography.textTheme(),
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
      margin: const EdgeInsets.symmetric(vertical: AppDimensions.gapSm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        side: const BorderSide(
          color: kSurfaceMuted,
          width: AppDimensions.borderWidth,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kSurfaceMuted,
        disabledForegroundColor: kInkMuted,
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
        side: const BorderSide(
          color: kForest,
          width: AppDimensions.focusBorderWidth,
        ),
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
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: focusedFieldBorder,
      labelStyle: const TextStyle(color: kInkMuted),
      hintStyle: const TextStyle(color: kInkMuted),
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
    listTileTheme: const ListTileThemeData(
      iconColor: kForest,
      textColor: kInk,
    ),
    dividerTheme: const DividerThemeData(
      color: kSurfaceMuted,
      thickness: AppDimensions.borderWidth,
      space: AppDimensions.gapMd,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : kInkMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kForest : kSurfaceMuted,
      ),
    ),
  );
}

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────
// Colour palette  — warm saffron/ochre on deep charcoal
// Chosen to feel familiar to Indian contractor apps while
// remaining modern and readable outdoors (high contrast).
// ─────────────────────────────────────────────────────────
const Color _kSaffron = Color(0xFFE8890B); // primary CTA
const Color _kSaffronDark = Color(0xFFC07608); // pressed state
const Color _kSurface = Color(0xFF1E1E2C); // dark card background
const Color _kBackground = Color(0xFF13131F); // page background
const Color _kOnSurface = Color(0xFFF5F0E8); // primary text on dark
const Color _kSubtle = Color(0xFF9E9BA8); // secondary/hint text
const Color _kError = Color(0xFFE05858); // delete / error
const Color _kDivider = Color(0xFF2E2E42);

// ─────────────────────────────────────────────────────────
// Typography
// Using 'Poppins' for headings (bold, readable),
// System font (Roboto on Android) for body to avoid
// bundling extra font assets on Day 1.
// ─────────────────────────────────────────────────────────
const TextTheme _textTheme = TextTheme(
  displaySmall: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: _kOnSurface,
      letterSpacing: -0.5),
  titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _kOnSurface),
  titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _kOnSurface),
  bodyLarge: TextStyle(fontSize: 16, color: _kOnSurface),
  bodyMedium: TextStyle(fontSize: 14, color: _kSubtle),
  labelLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: _kBackground), // text ON saffron button
);

// ─────────────────────────────────────────────────────────
// Shared button dimensions — large targets for contractor
// fingers; 56 px height is the minimum tappable size.
// ─────────────────────────────────────────────────────────
const double kButtonHeight = 56.0;
const double kButtonRadius = 14.0;
const double kPagePadding = 20.0;

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _kSaffron,
    onPrimary: _kBackground,
    secondary: _kSaffronDark,
    onSecondary: _kBackground,
    error: _kError,
    onError: _kOnSurface,
    surface: _kSurface,
    onSurface: _kOnSurface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: _kBackground,
    dividerColor: _kDivider,
    textTheme: _textTheme,

    // ── AppBar ────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: _kBackground,
      foregroundColor: _kOnSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: _kOnSurface),
    ),

    // ── Cards ─────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: _kSurface,
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),

    // ── ElevatedButton — primary CTA ──────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _kSaffron,
        foregroundColor: _kBackground,
        minimumSize: const Size.fromHeight(kButtonHeight),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kButtonRadius)),
        textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700),
        elevation: 0,
      ),
    ),

    // ── OutlinedButton — secondary action ─────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _kSaffron,
        side: const BorderSide(color: _kSaffron, width: 1.5),
        minimumSize: const Size.fromHeight(kButtonHeight),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kButtonRadius)),
        textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    // ── TextButton ────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: _kSaffron),
    ),

    // ── BottomNavigationBar (not used Day 1, but ready) ───
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _kSurface,
      selectedItemColor: _kSaffron,
      unselectedItemColor: _kSubtle,
    ),
  );
}

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

export 'theme/app_theme.dart';
export 'theme/colors.dart';
export 'theme/dimensions.dart';
export 'theme/typography.dart';

// ignore_for_file: unused_element

// ── Legacy dark-theme tokens (kept for compiling old screens) ──
// New code should import theme/colors.dart + theme/app_theme.dart directly.
const Color _kSaffron = Color(0xFFE8890B);
const Color _kSaffronDark = Color(0xFFC07608);
const Color _kSurface = Color(0xFF1E1E2C);
const Color _kBackground = Color(0xFF13131F);
const Color _kOnSurface = Color(0xFFF5F0E8);
const Color _kSubtle = Color(0xFF9E9BA8);
const Color _kError = Color(0xFFE05858);
const Color _kDivider = Color(0xFF2E2E42);

const double kButtonHeight = 56.0;
const double kButtonRadius = 14.0;
const double kPagePadding = 20.0;

/// Legacy entry point — now returns the light theme.
/// Old screens keep their explicit dark colours until rewritten in
/// Phase 2-6, so they continue to compile unchanged.
ThemeData buildAppTheme() => buildLightAppTheme();

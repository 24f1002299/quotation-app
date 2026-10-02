import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/dimensions.dart';

export 'theme/app_theme.dart';
export 'theme/colors.dart';
export 'theme/dimensions.dart';
export 'theme/typography.dart';

/// Screen horizontal padding, kept here because most screens import this
/// barrel instead of the individual token files.
const double kPagePadding = AppDimensions.page;

/// Single theme entry point — the app is light-only.
ThemeData buildAppTheme() => buildLightAppTheme();

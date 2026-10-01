import 'package:flutter/material.dart';

import 'strings_en.dart';
import 'strings_hi.dart';
import 'strings_mr.dart';

/// Global language channel — Settings can switch languages instantly
/// (no restart) by setting [appLanguage]; the app root listens.
final ValueNotifier<String> appLanguage = ValueNotifier<String>('hi');

/// Minimal locale-driven string lookup (no heavy i18n framework for MVP).
/// Supported codes: 'en', 'hi', 'mr'. Anything else falls back to Hindi
/// (Hindi-first product), matching [AppPreferences] defaults.
class AppStrings extends InheritedWidget {
  final String languageCode;

  const AppStrings({
    super.key,
    required this.languageCode,
    required super.child,
  });

  static const _tables = {
    'en': stringsEn,
    'hi': stringsHi,
    'mr': stringsMr,
  };

  /// Look up [key] for [languageCode]; falls back to Hindi then English.
  static String text(String languageCode, String key) {
    return _tables[languageCode]?[key] ??
        stringsHi[key] ??
        stringsEn[key] ??
        key;
  }

  /// Current-language lookup via context. Falls back to Hindi outside scope.
  static String of(BuildContext context, String key) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppStrings>();
    final lang = scope?.languageCode ?? 'hi';
    return text(lang, key);
  }

  /// Non-listening lookup (e.g. inside callbacks).
  static String read(BuildContext context, String key) {
    String? lang;
    context.visitAncestorElements((e) {
      if (e.widget is AppStrings) {
        lang = (e.widget as AppStrings).languageCode;
        return false;
      }
      return true;
    });
    return text(lang ?? 'hi', key);
  }

  @override
  bool updateShouldNotify(AppStrings oldWidget) =>
      oldWidget.languageCode != languageCode;
}

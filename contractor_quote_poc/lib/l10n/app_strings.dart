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

  static const Map<String, Map<String, String>> _tables = {
    'en': stringsEn,
    'hi': stringsHi,
    'mr': stringsMr,
  };

  /// The string table for [languageCode], or the Hindi table when unknown.
  static Map<String, String> tableFor(String languageCode) =>
      _tables[languageCode] ?? stringsHi;

  /// Look up [key] for [languageCode]; falls back to Hindi then English.
  /// An unknown key is returned verbatim so a missing label is visible, never
  /// silently blank.
  static String text(String languageCode, String key) =>
      _tables[languageCode]?[key] ??
      stringsHi[key] ??
      stringsEn[key] ??
      key;

  /// Current-language lookup via context. Falls back to Hindi outside scope.
  static String of(BuildContext context, String key) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStrings>();
    return text(scope?.languageCode ?? 'hi', key);
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

  /// English keys missing from [languageCode]. English is the reference
  /// table, so an empty result means the translation is complete.
  static List<String> missingKeys(String languageCode) {
    final table = tableFor(languageCode);
    return stringsEn.keys.where((key) => !table.containsKey(key)).toList();
  }

  @override
  bool updateShouldNotify(AppStrings oldWidget) =>
      oldWidget.languageCode != languageCode;
}

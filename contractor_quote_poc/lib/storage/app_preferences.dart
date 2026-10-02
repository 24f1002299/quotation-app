import 'package:shared_preferences/shared_preferences.dart';

import '../templates/template_data.dart';

/// Day 19 — Minimal app preferences: capture language + one-time tutorial.
///
/// - Language codes: 'hi' (default when device locale supports it),
///   'mr', 'auto'. Persisted so Home and Voice screens stay in sync.
/// - Tutorial: single in-context hint on Home, shown once, dismissible.
class AppPreferences {
  static const _languageKey = 'app_language_v1';
  static const _tutorialSeenKey = 'home_tutorial_seen_v1';
  static const _languageChosenKey = 'app_language_chosen_v1';
  static const _lastBusinessTypeKey = 'app_last_businessType_v1';

  /// Pure helper: Hindi default when the device locale is Hindi/Marathi
  /// (or Hinglish romanized variants); testable without platform calls.
  static String defaultLanguageForLocale(String localeName) {
    final lower = localeName.toLowerCase();
    if (lower.startsWith('hi') || lower.startsWith('mr')) return 'hi';
    return 'hi'; // Hindi-first product: default to Hindi otherwise too.
  }

  static String labelFor(String code) {
    switch (code) {
      case 'mr':
        return 'मराठी';
      case 'en':
        return 'English';
      case 'auto':
        return 'Auto';
      case 'hi':
      default:
        return 'हिंदी';
    }
  }

  /// First-launch gate: true once the user picks a language.
  /// Older installs (language saved, flag missing) count as chosen.
  static Future<bool> hasChosenLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_languageChosenKey) ?? false) return true;
    return prefs.getString(_languageKey) != null;
  }

  static Future<void> setLanguageChosen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_languageChosenKey, true);
  }

  /// Last-used business type for pre-selecting chips, stored as the stable
  /// [BusinessTypeInfo.id] slug so all 12 types round-trip (not just tiling).
  static Future<BusinessType?> getLastBusinessType() async {
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString(_lastBusinessTypeKey);
    if (slug == null || slug.isEmpty) return null;
    // businessTypeFromId falls back to tiling for unknown slugs; treat a
    // stored-but-unknown value as "no preference" instead.
    if (!kBusinessTypes.any((info) => info.id == slug)) return null;
    return businessTypeFromId(slug);
  }

  static Future<void> setLastBusinessType(BusinessType businessType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastBusinessTypeKey, businessTypeInfo(businessType).id);
  }

  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'hi';
  }

  static Future<void> setLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  static Future<bool> hasSeenTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tutorialSeenKey) ?? false;
  }

  static Future<void> setTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialSeenKey, true);
  }
}

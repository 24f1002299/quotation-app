import 'package:shared_preferences/shared_preferences.dart';

/// Day 19 — Minimal app preferences: capture language + one-time tutorial.
///
/// - Language codes: 'hi' (default when device locale supports it),
///   'mr', 'auto'. Persisted so Home and Voice screens stay in sync.
/// - Tutorial: single in-context hint on Home, shown once, dismissible.
class AppPreferences {
  static const _languageKey = 'app_language_v1';
  static const _tutorialSeenKey = 'home_tutorial_seen_v1';

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
      case 'auto':
        return 'Auto';
      case 'hi':
      default:
        return 'हिंदी';
    }
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

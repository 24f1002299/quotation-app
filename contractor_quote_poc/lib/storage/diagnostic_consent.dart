import 'package:shared_preferences/shared_preferences.dart';

/// Day 21 — User-visible consent for diagnostic transcript storage.
///
/// - OFF by default. The app never stores raw audio by default and never
///   keeps a diagnostic transcript copy unless the user opts in here.
/// - The functional quote transcript (`SavedQuote.originalTranscript`) needed
///   to build/review the quote is NOT diagnostic storage — it lives with the
///   quote and is deleted with it. This toggle gates only the extra
///   diagnostic copy used for troubleshooting/extraction quality.
class DiagnosticConsent {
  static const _key = 'diagnostic_transcript_opt_in_v1';
  static const _audioKey = 'diagnostic_audio_opt_in_v1'; // always false; reserved

  /// False unless the user explicitly opted in.
  static Future<bool> isOptedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setOptedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// Raw audio diagnostic collection is never enabled in the MVP.
  /// Kept as an explicit always-false gate so a future feature cannot
  /// silently start collecting audio.
  static Future<bool> isAudioOptedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_audioKey) ?? false;
  }
}

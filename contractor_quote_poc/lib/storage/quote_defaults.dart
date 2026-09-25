import 'package:shared_preferences/shared_preferences.dart';

/// Day 15 — Last-used commercial defaults (progressive disclosure support).
/// Keeps data entry minimal: validity, GST, advance and terms prefill from
/// the previous quote. All fields stay optional.
class QuoteDefaults {
  static const _validityKey = 'quote_default_validity_v1';
  static const _gstKey = 'quote_default_gst_v1';
  static const _advanceKey = 'quote_default_advance_v1';
  static const _termsKey = 'quote_default_terms_v1';

  final int validityDays;
  final int? gstPercent;
  final int? advancePercent;
  final String termsText;

  const QuoteDefaults({
    this.validityDays = 15,
    this.gstPercent,
    this.advancePercent,
    this.termsText = '',
  });

  static Future<QuoteDefaults> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return QuoteDefaults(
        validityDays: prefs.getInt(_validityKey) ?? 15,
        gstPercent: prefs.getInt(_gstKey),
        advancePercent: prefs.getInt(_advanceKey),
        termsText: prefs.getString(_termsKey) ?? '',
      );
    } catch (_) {
      return const QuoteDefaults();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_validityKey, validityDays);
      if (gstPercent == null) {
        await prefs.remove(_gstKey);
      } else {
        await prefs.setInt(_gstKey, gstPercent!);
      }
      if (advancePercent == null) {
        await prefs.remove(_advanceKey);
      } else {
        await prefs.setInt(_advanceKey, advancePercent!);
      }
      await prefs.setString(_termsKey, termsText);
    } catch (_) {}
  }
}

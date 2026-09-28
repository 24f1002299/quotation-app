import 'package:shared_preferences/shared_preferences.dart';

/// Day 18 — Opt-in cloud backup toggle for quotation PDFs.
///
/// Default is OFF: PDFs live only in app-scoped storage
/// (`<app-docs>/quotations/Quotation_<quoteId>.pdf`).
/// Cloud backup to Supabase Storage happens only when the user enables this.
class PdfBackupSettings {
  static const _key = 'pdf_backup_opt_in_v1';

  /// Returns true only when the user explicitly enabled PDF backup.
  static Future<bool> isOptedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setOptedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

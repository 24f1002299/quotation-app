import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';
import 'app_preferences.dart';
import 'diagnostic_consent.dart';
import 'encrypted_draft_store.dart';
import 'feedback_repository.dart';
import 'pdf_backup_settings.dart';
import 'profile_repository.dart';
import 'quote_repository.dart';
import 'rate_memory_repository.dart';
import 'sync_outbox.dart';
import 'transcript_draft_repository.dart';

/// Day 22 — User data export + deletion path.
///
/// Export: builds a plain JSON map of everything stored on this phone
/// (profile, rates, quotes incl. transcripts, correction-feedback rows,
/// preferences). No audio is stored on the phone after transcription, so
/// an export never contains audio bytes.
///
/// Delete: removes local quotes, encrypted drafts, outbox, feedback,
/// transcript drafts, profile, rates, preferences/consent flags, and the
/// app-scoped `quotations/` PDF directory (best-effort).
/// Cloud copies must be deleted via the signed-in API per-quote delete
/// (RLS-scoped) — see docs/data-retention.md.
class DataDeletionService {
  const DataDeletionService._();

  /// Returns a JSON-encodable snapshot of on-device data for the user.
  static Future<Map<String, dynamic>> exportAll() async {
    final profile = await ProfileRepository.getProfile();
    final rates = await RateMemoryRepository.getAllRates();
    final quotes = await QuoteRepository.getQuotes();
    final feedback = await FeedbackRepository.getAll();
    final outbox = await SyncOutbox.getPending();
    final language = await AppPreferences.getLanguage();
    final diagnosticOptIn = await DiagnosticConsent.isOptedIn();
    final pdfOptIn = await PdfBackupSettings.isOptedIn();
    final drafts = <String, Object?>{};
    for (final trade in Trade.values) {
      final d = await TranscriptDraftRepository.getDraft(trade);
      if (d != null) {
        drafts[trade.name] = {
          'transcript': d.transcript,
          'language': d.language,
          'updatedAt': d.updatedAt.toIso8601String(),
        };
      }
    }

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': {
        'name': profile.name,
        'businessName': profile.businessName,
        'phone': profile.phone,
        'city': profile.city,
        'trade': profile.trade.name,
        'gstin': profile.gstin,
        'quoteTerms': profile.quoteTerms,
      },
      'rates': [
        for (final r in rates)
          {
            'catalogItemId': r.catalogItemId,
            'trade': r.trade.name,
            'unit': r.unit,
            'unitRatePaise': r.unitRatePaise,
          },
      ],
      'quotes': [for (final q in quotes) q.toJson()],
      'feedback': [for (final f in feedback) f.toJson()],
      'transcriptDrafts': drafts,
      'pendingSyncOperations': outbox.length,
      'preferences': {
        'language': language,
        'diagnosticOptIn': diagnosticOptIn,
        'pdfBackupOptIn': pdfOptIn,
      },
      'note': 'No audio recordings are stored; exports never contain audio.',
    };
  }

  static String exportJson(Map<String, dynamic> snapshot) =>
      const JsonEncoder.withIndent('  ').convert(snapshot);

  /// Deletes everything stored on this phone. Returns a summary for UI.
  /// Cloud data is NOT touched here — per-quote server delete happens
  /// through the authenticated API while signed in (see retention doc).
  static Future<String> deleteAllLocal() async {
    int quoteCount = 0;
    try {
      quoteCount = (await QuoteRepository.getQuotes()).length;
    } catch (_) {}
    final feedbackCount = (await FeedbackRepository.getAll()).length;

    await QuoteRepository.clearAll();
    await EncryptedDraftStore.clearAll();
    await SyncOutbox.clear();
    await FeedbackRepository.clearAll();
    await ProfileRepository.clearProfile();
    await RateMemoryRepository.clearAll();
    for (final trade in Trade.values) {
      try {
        await TranscriptDraftRepository.clearDraft(trade);
      } catch (_) {}
    }
    // Reset consent + preference flags to OFF/defaults.
    await DiagnosticConsent.setOptedIn(false);
    await PdfBackupSettings.setOptedIn(false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_language_v1');
      await prefs.remove('home_tutorial_seen_v1');
      await prefs.remove('quote_default_validity_v1');
      await prefs.remove('quote_default_gst_v1');
      await prefs.remove('quote_default_advance_v1');
      await prefs.remove('quote_default_terms_v1');
    } catch (_) {}

    int pdfsDeleted = 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final quotesDir = Directory('${dir.path}/quotations');
      if (await quotesDir.exists()) {
        await for (final e in quotesDir.list()) {
          try {
            if (e is File) {
              await e.delete();
              pdfsDeleted++;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return 'Deleted $quoteCount quotes, $feedbackCount correction notes, '
        '$pdfsDeleted PDFs and all settings on this phone.';
  }
}

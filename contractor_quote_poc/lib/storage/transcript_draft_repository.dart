import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';
import '../models/transcript_draft.dart';

/// Day 9 — Local repository for persisting in-progress transcript drafts.
///
/// Ensures contractor recordings & typed edits survive app restarts,
/// phone calls, or network interruptions.
class TranscriptDraftRepository {
  static const _keyPrefix = 'contractor_transcript_draft_';

  static String _key(Trade? trade) => '$_keyPrefix${trade?.name ?? "general"}';

  /// Saves or updates the current draft for a trade.
  static Future<void> saveDraft(TranscriptDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(draft.toJson());
    await prefs.setString(_key(draft.trade), jsonStr);
  }

  /// Gets the saved draft for a trade, or null if none exists.
  static Future<TranscriptDraft?> getDraft(Trade? trade) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key(trade));
    if (jsonStr == null || jsonStr.isEmpty) return null;

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      return TranscriptDraft.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Clears the draft for a trade after successful quote generation.
  static Future<void> clearDraft(Trade? trade) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(trade));
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/edit_feedback.dart';
import '../models/quote.dart';
import 'sync_outbox.dart';

/// Day 21 — Privacy-conscious correction feedback store.
///
/// Records ONE minimal record per corrected field when a user alters an
/// extracted line: businessType, serviceItemId, modelResult, finalValue,
/// changedField, quoteIdHash.
///
/// - No raw audio, no full transcript, no customer PII is ever stored here.
/// - Feedback is append-only locally; deletion happens only via
///   [deleteForQuoteId] when its quote is deleted (see docs/feedback-privacy.md).
class FeedbackRepository {
  static const _storageKey = 'contractor_edit_feedback_v1';

  /// Records corrections by diffing [original] (extraction snapshot) against
  /// [edited] (user's final values). Creates one [EditFeedback] per changed
  /// field among description/quantity/unit/rate. Returns created records.
  ///
  /// No-ops (returns []) when nothing changed or [businessType] is null/blank.
  /// Any business slug is recorded — feedback is universal, not tiling-only.
  static Future<List<EditFeedback>> recordCorrection({
    required String quoteId,
    required String? businessType,
    required QuoteLineItem original,
    required QuoteLineItem edited,
    String? serviceItemId,
    String? modelResult,
  }) async {
    if (businessType == null || businessType.trim().isEmpty) return [];
    final t = businessType.trim().toLowerCase();

    final hash = hashQuoteId(quoteId);
    final now = DateTime.now();
    final out = <EditFeedback>[];

    void add(String field, String? model, String? finalV) {
      out.add(EditFeedback(
        id: 'fb_${now.microsecondsSinceEpoch}_${out.length}',
        quoteIdHash: hash,
        businessType: t,
        serviceItemId: serviceItemId ?? original.serviceItemId,
        modelResult: model ?? modelResult,
        finalValue: finalV,
        changedField: field,
        createdAt: now,
      ));
    }

    if (original.description.trim() != edited.description.trim()) {
      add('description', original.description.trim(), edited.description.trim());
    }
    if (original.quantity != edited.quantity) {
      add('quantity', '${original.quantity}', '${edited.quantity}');
    }
    if (original.unit.trim() != edited.unit.trim()) {
      add('unit', original.unit.trim(), edited.unit.trim());
    }
    if (original.unitRatePaise != edited.unitRatePaise) {
      add('rate', '${original.unitRatePaise}', '${edited.unitRatePaise}');
    }

    if (out.isEmpty) return out;

    final all = await getAll();
    all.addAll(out);
    await _saveAll(all);

    // Queue for durable sync (outbox is the minimum sync mechanism).
    for (final fb in out) {
      await SyncOutbox.enqueue(OutboxItem(
        operationId: 'feedback_${fb.id}',
        entityType: 'feedback',
        action: 'upsert',
        payload: fb.toJson(),
        idempotencyKey: fb.id,
        retryCount: 0,
        payloadVersion: 1,
        createdAt: fb.createdAt,
      ));
    }
    return out;
  }

  static Future<List<EditFeedback>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return raw
          .map((s) => EditFeedback.fromJson(json.decode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// All feedback rows belonging to [quoteId] (matched via its hash).
  static Future<List<EditFeedback>> getForQuoteId(String quoteId) async {
    final hash = hashQuoteId(quoteId);
    final all = await getAll();
    return all.where((f) => f.quoteIdHash == hash).toList(growable: false);
  }

  /// Day 21 verify: deleting a quote removes its feedback locally and
  /// enqueues a delete marker so the server can delete/anonymize its copy.
  /// Returns the number of removed records.
  static Future<int> deleteForQuoteId(String quoteId) async {
    final hash = hashQuoteId(quoteId);
    final all = await getAll();
    final remaining = all.where((f) => f.quoteIdHash != hash).toList();
    final removed = all.length - remaining.length;
    if (removed == 0) return 0;
    await _saveAll(remaining);
    await SyncOutbox.enqueue(OutboxItem(
      operationId: 'feedback_delete_$hash',
      entityType: 'feedback',
      action: 'delete',
      payload: {'quote_id_hash': hash},
      idempotencyKey: 'feedback_delete_$hash',
      retryCount: 0,
      payloadVersion: 1,
      createdAt: DateTime.now(),
    ));
    return removed;
  }

  static Future<void> _saveAll(List<EditFeedback> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      items.map((f) => json.encode(f.toJson())).toList(),
    );
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

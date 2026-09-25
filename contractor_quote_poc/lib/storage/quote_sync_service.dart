import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import 'encrypted_draft_store.dart';
import 'quote_repository.dart';
import 'saved_quote.dart';
import 'sync_outbox.dart';

/// Represents a detected version conflict between local device changes
/// and concurrent server updates made from another device.
class SyncConflict {
  final SavedQuote localQuote;
  final SavedQuote serverQuote;
  final String message;

  const SyncConflict({
    required this.localQuote,
    required this.serverQuote,
    required this.message,
  });
}

/// Day 16 — Service handling quote synchronization with bounded exponential backoff
/// and optimistic concurrency conflict resolution.
class QuoteSyncService {
  /// Base API URL for quotes synchronization.
  static String get _quotesSyncUrl => '$kApiBaseUrl/quotes/sync';
  static String get _quotesUrl => '$kApiBaseUrl/quotes';

  /// Synchronizes all pending quotes in [SyncOutbox] with bounded exponential backoff.
  /// Returns list of detected version conflicts (if any).
  static Future<List<SyncConflict>> syncPendingQuotes({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final pending = await SyncOutbox.getPending();
    final quoteItems = pending.where((i) => i.entityType == 'quote').toList();

    final List<SyncConflict> conflicts = [];
    final now = DateTime.now();

    for (final item in quoteItems) {
      // Respect bounded exponential backoff schedule
      if (item.nextRetryAt != null && item.nextRetryAt!.isAfter(now)) {
        continue;
      }

      // If already flagged with an unresolved conflict, do not resend until user resolves
      if (item.hasConflict && item.conflictingPayload != null) {
        try {
          final localQuote = SavedQuote.fromJson(item.payload);
          final serverQuote = SavedQuote.fromJson(item.conflictingPayload!);
          conflicts.add(SyncConflict(
            localQuote: localQuote,
            serverQuote: serverQuote,
            message: 'Quote modified on another device',
          ));
        } catch (_) {}
        continue;
      }

      try {
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Idempotency-Key': item.idempotencyKey,
        };

        // Attach Supabase bearer token if available
        try {
          final session = Supabase.instance.client.auth.currentSession;
          if (session?.accessToken != null) {
            headers['Authorization'] = 'Bearer ${session!.accessToken}';
          }
        } catch (_) {}

        final response = await httpClient
            .post(
              Uri.parse(_quotesSyncUrl),
              headers: headers,
              body: json.encode(item.payload),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Sync succeeded!
          final bodyMap = json.decode(response.body) as Map<String, dynamic>;
          final serverDisplayNum = bodyMap['displayNumber'] as String?;
          final serverVersion = bodyMap['version'] as int? ?? (item.payloadVersion);

          // Update local quote repository and encrypted draft store with assigned numbers
          final quoteId = item.payload['id'] as String? ?? item.operationId;
          final localQuote = await QuoteRepository.getQuoteById(quoteId);
          if (localQuote != null) {
            final updatedLocal = localQuote.copyWith(
              serverDisplayNumber: serverDisplayNum ?? localQuote.serverDisplayNumber,
              version: serverVersion,
            );
            await QuoteRepository.saveQuoteLocallyOnly(updatedLocal);
          }

          // Remove completed mutation from outbox
          await SyncOutbox.remove(item.operationId);
        } else if (response.statusCode == 409) {
          // Version conflict! Quote modified on another device
          final bodyMap = json.decode(response.body) as Map<String, dynamic>;
          final serverQuoteMap = bodyMap['serverQuote'] as Map<String, dynamic>? ?? {};
          final serverQuote = SavedQuote.fromJson(serverQuoteMap);
          final localQuote = SavedQuote.fromJson(item.payload);

          // Mark conflict in durable outbox
          final conflictedItem = item.markConflict(serverQuoteMap);
          await SyncOutbox.update(conflictedItem);

          conflicts.add(SyncConflict(
            localQuote: localQuote,
            serverQuote: serverQuote,
            message: bodyMap['message'] as String? ?? 'Quote was modified on another device',
          ));
        } else {
          // Server error / retryable: apply bounded exponential backoff
          final updated = item.incrementRetry(
            error: 'Server returned HTTP ${response.statusCode}',
          );
          await SyncOutbox.update(updated);
        }
      } catch (err) {
        // Network / connectivity dropped: apply bounded exponential backoff
        final updated = item.incrementRetry(
          error: err.toString(),
        );
        await SyncOutbox.update(updated);
      }
    }

    if (client == null) {
      httpClient.close();
    }
    return conflicts;
  }

  // ── Conflict Resolution Options ───────────────────────────────────────────

  /// Option A: Keep Server Version.
  /// Overwrites the local draft with the server's conflicting record and removes outbox item.
  static Future<void> resolveKeepServer(String quoteId) async {
    final pending = await SyncOutbox.getPending();
    final item = pending.firstWhere(
      (i) => (i.payload['id'] == quoteId || i.operationId.contains(quoteId)),
      orElse: () => throw StateError('No pending outbox item found for quote $quoteId'),
    );

    if (item.conflictingPayload != null) {
      final serverQuote = SavedQuote.fromJson(item.conflictingPayload!);
      await QuoteRepository.saveQuoteLocallyOnly(serverQuote);
      await EncryptedDraftStore.saveDraft(serverQuote);
    }
    await SyncOutbox.remove(item.operationId);
  }

  /// Option B: Keep This Phone's Version.
  /// Re-bases the local changes onto the server version, generates a new idempotency key,
  /// updates outbox, and syncs immediately.
  static Future<void> resolveKeepDevice(String quoteId, {http.Client? client}) async {
    final pending = await SyncOutbox.getPending();
    final item = pending.firstWhere(
      (i) => (i.payload['id'] == quoteId || i.operationId.contains(quoteId)),
      orElse: () => throw StateError('No pending outbox item found for quote $quoteId'),
    );

    final localQuote = await QuoteRepository.getQuoteById(quoteId);
    if (localQuote == null) return;

    int newBaseVersion = localQuote.version;
    if (item.conflictingPayload != null) {
      final sVersion = item.conflictingPayload!['version'] as int? ?? 1;
      newBaseVersion = sVersion;
    }

    final newIdempKey = 'rebase_${localQuote.id}_${DateTime.now().millisecondsSinceEpoch}';
    final rebasedQuote = localQuote.copyWith(
      version: newBaseVersion,
      idempotencyKey: newIdempKey,
    );

    await QuoteRepository.saveQuoteLocallyOnly(rebasedQuote);
    await EncryptedDraftStore.saveDraft(rebasedQuote);

    // Re-queue in outbox with cleared conflict
    final updatedItem = OutboxItem(
      operationId: item.operationId,
      entityType: 'quote',
      action: 'upsert',
      payload: rebasedQuote.toJson(),
      idempotencyKey: newIdempKey,
      retryCount: 0,
      payloadVersion: newBaseVersion,
      createdAt: DateTime.now(),
      hasConflict: false,
      conflictingPayload: null,
    );
    await SyncOutbox.update(updatedItem);

    // Re-attempt sync immediately
    await syncPendingQuotes(client: client);
  }

  // ── Server-Side Search and History Pagination ─────────────────────────────

  /// Performs server-side paginated search with offline fallback.
  static Future<({
    List<SavedQuote> quotes,
    int page,
    int size,
    int totalElements,
    int totalPages,
    bool isLast,
    bool isOffline,
  })> searchQuoteHistory({
    int page = 0,
    int size = 10,
    String? client,
    String? status,
    String? date,
    http.Client? httpClient,
  }) async {
    final clientInstance = httpClient ?? http.Client();

    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'size': size.toString(),
      };
      if (client != null && client.trim().isNotEmpty) {
        queryParams['client'] = client.trim();
      }
      if (status != null && status.trim().isNotEmpty) {
        queryParams['status'] = status.trim();
      }
      if (date != null && date.trim().isNotEmpty) {
        queryParams['date'] = date.trim();
      }

      final uri = Uri.parse(_quotesUrl).replace(queryParameters: queryParams);
      final headers = <String, String>{'Accept': 'application/json'};

      try {
        final session = Supabase.instance.client.auth.currentSession;
        if (session?.accessToken != null) {
          headers['Authorization'] = 'Bearer ${session!.accessToken}';
        }
      } catch (_) {}

      final response = await clientInstance.get(uri, headers: headers).timeout(
        const Duration(seconds: 4),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final rawContent = body['content'] as List<dynamic>? ?? [];
        final quotes = rawContent
            .map((item) => SavedQuote.fromJson(item as Map<String, dynamic>))
            .toList();

        final totalElements = body['totalElements'] as int? ?? quotes.length;
        final totalPages = body['totalPages'] as int? ?? 1;
        final isLast = body['isLast'] as bool? ?? (page >= totalPages - 1);

        if (httpClient == null) clientInstance.close();
        return (
          quotes: quotes,
          page: page,
          size: size,
          totalElements: totalElements,
          totalPages: totalPages,
          isLast: isLast,
          isOffline: false,
        );
      }
    } catch (_) {
      // Offline fallback: query local repository
    }

    if (httpClient == null) clientInstance.close();

    // Offline local fallback filtering
    final all = await QuoteRepository.getQuotes();
    final filtered = all.where((q) {
      if (client != null && client.trim().isNotEmpty) {
        if (!q.customerName.toLowerCase().contains(client.toLowerCase().trim())) {
          return false;
        }
      }
      if (status != null && status.trim().isNotEmpty) {
        if (q.status.toLowerCase() != status.toLowerCase().trim()) {
          return false;
        }
      }
      if (date != null && date.trim().isNotEmpty) {
        final dTrim = date.trim();
        final qd = q.quoteDate != null ? q.quoteDate!.toIso8601String() : q.createdAt.toIso8601String();
        if (!qd.contains(dTrim)) {
          return false;
        }
      }
      return true;
    }).toList();

    final from = page * size;
    final to = (from + size).clamp(0, filtered.length);
    final paged = from < filtered.length ? filtered.sublist(from, to) : <SavedQuote>[];
    final totalPages = size > 0 ? (filtered.length / size).ceil() : 1;

    return (
      quotes: paged,
      page: page,
      size: size,
      totalElements: filtered.length,
      totalPages: totalPages,
      isLast: page >= totalPages - 1,
      isOffline: true,
    );
  }
}

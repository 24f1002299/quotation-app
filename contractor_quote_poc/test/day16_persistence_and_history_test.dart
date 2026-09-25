import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/storage/catalog_version_repository.dart';
import 'package:contractor_quote_poc/storage/encrypted_draft_store.dart';
import 'package:contractor_quote_poc/storage/quote_repository.dart';
import 'package:contractor_quote_poc/storage/quote_sync_service.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';
import 'package:contractor_quote_poc/storage/sync_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await QuoteRepository.clearAll();
    await SyncOutbox.clear();
    await CatalogVersionRepository.clearAll();
    await EncryptedDraftStore.clearAll();
    EncryptedDraftStore.setDeviceKeyForTesting('test_secret_encryption_key_32_bytes!');
  });

  tearDown(() async {
    EncryptedDraftStore.setDeviceKeyForTesting(null);
  });

  group('Day 16 — Encrypted Local Draft Store', () {
    test('Draft is encrypted at rest and not stored in plaintext', () async {
      final draft = SavedQuote(
        id: 'draft_enc_1',
        quoteNumber: 'Q-2026-D001',
        createdAt: DateTime(2026, 9, 25),
        customerName: 'Gupta Secret Residence',
        customerPhone: '+91 99999 88888',
        customerAddress: 'Top Secret Bungalow, Bandra',
        notes: 'Confidential 50% discount offered',
        lineItems: const [
          QuoteLineItem(
            description: 'Italian Marble Tiles',
            quantity: 500,
            unit: 'sq ft',
            unitRatePaise: 25000,
          ),
        ],
        version: 1,
      );

      await EncryptedDraftStore.saveDraft(draft);

      // Verify that inspecting raw SharedPreferences storage does NOT show customer name or notes
      final prefs = await SharedPreferences.getInstance();
      final rawStorage = prefs.getString('contractor_encrypted_drafts_v1') ?? '';
      expect(rawStorage.contains('Gupta Secret Residence'), isFalse);
      expect(rawStorage.contains('+91 99999 88888'), isFalse);
      expect(rawStorage.contains('Top Secret Bungalow'), isFalse);
      expect(rawStorage.contains('Italian Marble Tiles'), isFalse);
      expect(rawStorage.contains('Confidential'), isFalse);

      // Verify draft can be decrypted and restored intact
      final restored = await EncryptedDraftStore.getDraft('draft_enc_1');
      expect(restored, isNotNull);
      expect(restored!.customerName, equals('Gupta Secret Residence'));
      expect(restored.customerPhone, equals('+91 99999 88888'));
      expect(restored.lineItems.first.description, equals('Italian Marble Tiles'));
      expect(restored.version, equals(1));
    });

    test('Draft store throws or handles corrupted cipher payload safely', () {
      expect(
        () => EncryptedDraftStore.decryptString('short_bad_payload', 'test_key'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Day 16 — Durable Sync Outbox and Bounded Exponential Backoff', () {
    test('Outbox item contains operationId, idempotencyKey, retryCount, and payloadVersion', () async {
      final item = OutboxItem(
        operationId: 'op_quote_101',
        entityType: 'quote',
        action: 'upsert',
        payload: {'id': 'q_101', 'clientName': 'Verma'},
        idempotencyKey: 'idemp_key_101',
        retryCount: 0,
        payloadVersion: 2,
        createdAt: DateTime(2026, 9, 25),
      );

      await SyncOutbox.enqueue(item);
      final pending = await SyncOutbox.getPending();
      expect(pending.length, equals(1));

      final fetched = pending.first;
      expect(fetched.operationId, equals('op_quote_101'));
      expect(fetched.idempotencyKey, equals('idemp_key_101'));
      expect(fetched.retryCount, equals(0));
      expect(fetched.payloadVersion, equals(2));
    });

    test('Bounded exponential backoff scales from 1s to maximum of 30s', () {
      expect(OutboxItem.calculateBackoff(0), equals(const Duration(seconds: 1)));
      expect(OutboxItem.calculateBackoff(1), equals(const Duration(seconds: 2)));
      expect(OutboxItem.calculateBackoff(2), equals(const Duration(seconds: 4)));
      expect(OutboxItem.calculateBackoff(3), equals(const Duration(seconds: 8)));
      expect(OutboxItem.calculateBackoff(4), equals(const Duration(seconds: 16)));
      expect(OutboxItem.calculateBackoff(5), equals(const Duration(seconds: 30))); // bounded
      expect(OutboxItem.calculateBackoff(10), equals(const Duration(seconds: 30))); // bounded
    });
  });

  group('Day 16 — Offline Draft Lifecycle (Force-close, Reopen, Edit, Reconnect)', () {
    test('Start offline quote, force close, reopen, finish editing, reconnect and sync exactly once', () async {
      // 1. Start a quote offline
      final offlineQuote = SavedQuote(
        id: 'quote_offline_001',
        quoteNumber: 'Q-2026-OFFLINE',
        createdAt: DateTime.now(),
        customerName: 'Patil Residence',
        trade: Trade.tiling,
        lineItems: const [
          QuoteLineItem(description: 'Floor tiles', quantity: 100, unit: 'sq ft', unitRatePaise: 8500),
        ],
        version: 1,
      );

      await QuoteRepository.saveQuote(offlineQuote);

      // Verify stored in both QuoteRepository and EncryptedDraftStore
      final savedDraft = await EncryptedDraftStore.getDraft('quote_offline_001');
      expect(savedDraft, isNotNull);
      expect(savedDraft!.customerName, equals('Patil Residence'));

      // 2. Simulate force-closing and reopening app: reload from QuoteRepository
      final reopenedQuote = await QuoteRepository.getQuoteById('quote_offline_001');
      expect(reopenedQuote, isNotNull);

      // 3. Finish editing (add advance, customer phone, notes)
      final finishedQuote = reopenedQuote!.copyWith(
        customerPhone: '+91 98765 00000',
        advancePercent: 50,
        advanceText: '50% advance before delivery',
        notes: 'Finish by Diwali',
        version: 1,
      );
      await QuoteRepository.saveQuote(finishedQuote);

      // 4. Reconnect and sync to server via MockClient
      int serverHits = 0;
      final mockClient = MockClient((request) async {
        serverHits++;
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        expect(body['customerName'], equals('Patil Residence'));
        expect(body['advancePercent'], equals(50));

        return http.Response(
          json.encode({
            'id': body['id'],
            'displayNumber': 'Q-2026-S101',
            'version': 1,
            'clientName': body['customerName'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final conflicts = await QuoteSyncService.syncPendingQuotes(client: mockClient);
      expect(conflicts, isEmpty);
      expect(serverHits, equals(1));

      // Confirm outbox is now empty (synced exactly once)
      final remainingPending = await SyncOutbox.getPending();
      expect(remainingPending, isEmpty);

      // Confirm local quote received server display number
      final syncedLocal = await QuoteRepository.getQuoteById('quote_offline_001');
      expect(syncedLocal!.displayNumber, equals('Q-2026-S101'));
      expect(syncedLocal.customerPhone, equals('+91 98765 00000'));
    });

    test('Simulated network drop / repeat request does not create extra quote or duplicate', () async {
      final quote = SavedQuote(
        id: 'quote_net_drop_002',
        quoteNumber: 'Q-2026-DROP',
        createdAt: DateTime.now(),
        customerName: 'Asha Ji',
        trade: Trade.painting,
        lineItems: const [
          QuoteLineItem(description: 'Wall Putty', quantity: 200, unit: 'sq ft', unitRatePaise: 1800),
        ],
        version: 1,
      );

      await QuoteRepository.saveQuote(quote);

      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        return http.Response(
          json.encode({
            'id': 'quote_net_drop_002',
            'displayNumber': 'Q-2026-A101',
            'version': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await QuoteSyncService.syncPendingQuotes(client: mockClient);
      expect(callCount, equals(1));

      // Repeat sync when outbox is empty triggers zero network calls
      await QuoteSyncService.syncPendingQuotes(client: mockClient);
      expect(callCount, equals(1));
    });
  });

  group('Day 16 — Two-Device Conflict Resolution', () {
    test('Same-quote edit from another device returns HTTP 409 conflict and allows recovery', () async {
      final quoteId = 'quote_conflict_003';
      final localQuote = SavedQuote(
        id: quoteId,
        quoteNumber: 'Q-2026-CONF',
        createdAt: DateTime.now(),
        customerName: 'Local Device Client',
        lineItems: const [
          QuoteLineItem(description: 'Tile Labour', quantity: 100, unit: 'sq ft', unitRatePaise: 4500),
        ],
        version: 1, // local device thinks it is version 1
      );

      await QuoteRepository.saveQuote(localQuote);

      // Mock server returning HTTP 409 conflict because Device 2 updated it to version 2
      final serverConflictQuote = SavedQuote(
        id: quoteId,
        quoteNumber: 'Q-2026-CONF',
        createdAt: DateTime.now(),
        customerName: 'Device 2 Modified Client',
        lineItems: const [
          QuoteLineItem(description: 'Tile Labour', quantity: 150, unit: 'sq ft', unitRatePaise: 5000),
        ],
        version: 2,
      );

      final conflictClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'code': 'VERSION_CONFLICT',
            'message': 'Quote was modified on another device',
            'serverQuote': serverConflictQuote.toJson(),
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final conflicts = await QuoteSyncService.syncPendingQuotes(client: conflictClient);
      expect(conflicts.length, equals(1));
      expect(conflicts.first.serverQuote.version, equals(2));
      expect(conflicts.first.serverQuote.customerName, equals('Device 2 Modified Client'));

      // Check that outbox item is marked as conflicted
      final pending = await SyncOutbox.getPending();
      expect(pending.first.hasConflict, isTrue);

      // Recovery Choice A: Keep Server Version
      await QuoteSyncService.resolveKeepServer(quoteId);

      final resolvedLocal = await QuoteRepository.getQuoteById(quoteId);
      expect(resolvedLocal!.customerName, equals('Device 2 Modified Client'));
      expect(resolvedLocal.version, equals(2));

      // Outbox item is cleared
      final emptyPending = await SyncOutbox.getPending();
      expect(emptyPending, isEmpty);
    });

    test('Recovery Choice B: Keep This Phone Version rebases and resyncs successfully', () async {
      final quoteId = 'quote_conflict_004';
      final localQuote = SavedQuote(
        id: quoteId,
        quoteNumber: 'Q-2026-REBASE',
        createdAt: DateTime.now(),
        customerName: 'My Local Edit',
        lineItems: const [
          QuoteLineItem(description: 'Tile Labour', quantity: 100, unit: 'sq ft', unitRatePaise: 4500),
        ],
        version: 1,
      );

      await QuoteRepository.saveQuote(localQuote);

      // Flag conflict manually in outbox
      final pending = await SyncOutbox.getPending();
      final conflicted = pending.first.markConflict({
        'id': quoteId,
        'quoteNumber': 'Q-2026-REBASE',
        'customerName': 'Remote Server Client',
        'version': 2,
        'createdAt': DateTime.now().toIso8601String(),
        'lineItems': [],
      });
      await SyncOutbox.update(conflicted);

      // Mock server accepting rebased version 2 -> updates to version 3
      final rebaseClient = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['version'], equals(2)); // rebased version
        return http.Response(
          json.encode({
            'id': quoteId,
            'displayNumber': 'Q-2026-R303',
            'version': 3,
            'clientName': body['customerName'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await QuoteSyncService.resolveKeepDevice(quoteId, client: rebaseClient);

      // Local quote now has version 3 and server display number
      final updatedLocal = await QuoteRepository.getQuoteById(quoteId);
      expect(updatedLocal!.version, equals(3));
      expect(updatedLocal.displayNumber, equals('Q-2026-R303'));
      expect(updatedLocal.customerName, equals('My Local Edit'));

      // Outbox cleared
      final outboxAfter = await SyncOutbox.getPending();
      expect(outboxAfter, isEmpty);
    });
  });

  group('Day 16 — Catalog Version Repository', () {
    test('Default catalog versions are seeded and accessible', () async {
      final tilingVersion = await CatalogVersionRepository.getVersion(Trade.tiling);
      expect(tilingVersion.trade, equals(Trade.tiling));
      expect(tilingVersion.version, equals(1));
      expect(tilingVersion.itemCount, greaterThan(0));

      final paintingVersion = await CatalogVersionRepository.getVersion(Trade.painting);
      expect(paintingVersion.trade, equals(Trade.painting));
      expect(paintingVersion.version, equals(1));

      // Detect stale catalog
      final isStale = await CatalogVersionRepository.isCatalogStale(Trade.tiling, 2);
      expect(isStale, isTrue);

      final isNotStale = await CatalogVersionRepository.isCatalogStale(Trade.tiling, 1);
      expect(isNotStale, isFalse);
    });
  });
}

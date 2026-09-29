import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/edit_feedback.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/storage/diagnostic_consent.dart';
import 'package:contractor_quote_poc/storage/feedback_repository.dart';
import 'package:contractor_quote_poc/storage/quote_repository.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 21 — hashed quote id', () {
    test('hash is deterministic, 64 hex chars, never the raw id', () {
      const raw = 'quote-123-uuid';
      final h1 = hashQuoteId(raw);
      final h2 = hashQuoteId(raw);
      expect(h1, equals(h2));
      expect(h1.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h1), isTrue);
      expect(h1.contains(raw), isFalse);
      // Known SHA-256 vector: hash of "abc".
      expect(
        hashQuoteId('abc'),
        equals(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
      );
    });
  });

  group('Day 21 — recordCorrection', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('editing quantity creates one correctly scoped feedback record', () async {
      const original = QuoteLineItem(
        description: 'Floor tiles',
        quantity: 120,
        unit: 'sq ft',
        unitRatePaise: 8500,
        catalogItemId: 'tiling_floor_tile',
      );
      const edited = QuoteLineItem(
        description: 'Floor tiles',
        quantity: 150,
        unit: 'sq ft',
        unitRatePaise: 8500,
        catalogItemId: 'tiling_floor_tile',
      );

      final created = await FeedbackRepository.recordCorrection(
        quoteId: 'quote-uuid-1',
        trade: 'tiling',
        original: original,
        edited: edited,
      );

      expect(created.length, equals(1));
      expect(created.first.changedField, equals('quantity'));
      expect(created.first.trade, equals('tiling'));
      expect(created.first.catalogItemId, equals('tiling_floor_tile'));
      expect(created.first.modelResult, equals('120'));
      expect(created.first.finalValue, equals('150'));
      expect(created.first.quoteIdHash, equals(hashQuoteId('quote-uuid-1')));

      // Scoped lookup returns it.
      final mine = await FeedbackRepository.getForQuoteId('quote-uuid-1');
      expect(mine.length, equals(1));
      final other = await FeedbackRepository.getForQuoteId('other-quote');
      expect(other, isEmpty);
    });

    test('no change creates no record; feedback JSON has no audio field', () async {
      const item = QuoteLineItem(
        description: 'Paint',
        quantity: 10,
        unit: 'ltr',
        unitRatePaise: 12000,
      );
      final created = await FeedbackRepository.recordCorrection(
        quoteId: 'q2',
        trade: 'painting',
        original: item,
        edited: item,
      );
      expect(created, isEmpty);

      // Multi-field edit creates one record per field.
      const edited = QuoteLineItem(
        description: 'Wall paint',
        quantity: 12,
        unit: 'ltr',
        unitRatePaise: 13000,
      );
      final multi = await FeedbackRepository.recordCorrection(
        quoteId: 'q2',
        trade: 'painting',
        original: item,
        edited: edited,
      );
      expect(multi.length, equals(3)); // description, quantity, rate
      for (final fb in multi) {
        final json = fb.toJson();
        expect(json.containsKey('audio'), isFalse);
        expect(json.containsKey('transcript'), isFalse);
        expect(json.containsKey('customer'), isFalse);
        expect(json['quote_id_hash'], equals(hashQuoteId('q2')));
      }
    });
  });

  group('Day 21 — quote delete removes feedback', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('deleting a quote removes its feedback, keeps others', () async {
      const item = QuoteLineItem(
        description: 'Tiles', quantity: 5, unit: 'sq ft', unitRatePaise: 5000);
      const edited = QuoteLineItem(
        description: 'Tiles', quantity: 6, unit: 'sq ft', unitRatePaise: 5000);

      await FeedbackRepository.recordCorrection(
        quoteId: 'quote-A', trade: 'tiling', original: item, edited: edited);
      await FeedbackRepository.recordCorrection(
        quoteId: 'quote-B', trade: 'tiling', original: item, edited: edited);
      expect((await FeedbackRepository.getAll()).length, equals(2));

      // Simulate Day 21 policy path: QuoteRepository.deleteQuote cleans up.
      final q = SavedQuote(
        id: 'quote-A',
        quoteNumber: 'Q-2026-0001',
        createdAt: DateTime.now(),
        customerName: 'Client',
        lineItems: const [item],
      );
      await QuoteRepository.saveQuote(q);
      await QuoteRepository.deleteQuote('quote-A');

      final remaining = await FeedbackRepository.getAll();
      expect(remaining.length, equals(1));
      expect(remaining.first.quoteIdHash, equals(hashQuoteId('quote-B')));
    });
  });

  group('Day 21 — diagnostic consent off by default', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('opt-in defaults to false, audio gate always false', () async {
      expect(await DiagnosticConsent.isOptedIn(), isFalse);
      expect(await DiagnosticConsent.isAudioOptedIn(), isFalse);
      await DiagnosticConsent.setOptedIn(true);
      expect(await DiagnosticConsent.isOptedIn(), isTrue);
      // Audio collection stays off even when transcript diagnostics are on.
      expect(await DiagnosticConsent.isAudioOptedIn(), isFalse);
    });
  });
}

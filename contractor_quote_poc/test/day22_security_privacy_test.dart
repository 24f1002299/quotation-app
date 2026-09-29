import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/storage/data_deletion_service.dart';
import 'package:contractor_quote_poc/storage/diagnostic_consent.dart';
import 'package:contractor_quote_poc/storage/feedback_repository.dart';
import 'package:contractor_quote_poc/storage/quote_repository.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 22 — privacy defaults', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('diagnostic transcript + audio collection are OFF by default', () async {
      expect(await DiagnosticConsent.isOptedIn(), isFalse);
      expect(await DiagnosticConsent.isAudioOptedIn(), isFalse);
    });

    test('feedback rows carry no audio/transcript/customer PII', () async {
      const original = QuoteLineItem(
        description: 'Floor tiles', quantity: 10, unit: 'sq ft', unitRatePaise: 8500);
      const edited = QuoteLineItem(
        description: 'Floor tiles', quantity: 11, unit: 'sq ft', unitRatePaise: 8500);
      final rows = await FeedbackRepository.recordCorrection(
        quoteId: 'q-22', trade: 'tiling', original: original, edited: edited);
      expect(rows, hasLength(1));
      final json = rows.first.toJson();
      for (final banned in ['audio', 'transcript', 'customer', 'phone', 'address']) {
        expect(json.containsKey(banned), isFalse, reason: 'must not contain $banned');
      }
      // Hashed scope, not raw id.
      expect(json['quote_id_hash'].toString().contains('q-22'), isFalse);
    });
  });

  group('Day 22 — export & delete-my-data', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('export contains quotes/profile/feedback and notes no audio', () async {
      await QuoteRepository.saveQuote(SavedQuote(
        id: 'exp-1',
        quoteNumber: 'Q-2026-0001',
        createdAt: DateTime.now(),
        trade: Trade.tiling,
        customerName: 'Sharma Ji',
        lineItems: const [
          QuoteLineItem(description: 'Tiles', quantity: 5, unit: 'sq ft', unitRatePaise: 5000),
        ],
      ));
      final snapshot = await DataDeletionService.exportAll();
      expect(snapshot['quotes'], isNotEmpty);
      expect(snapshot['profile'], isNotNull);
      expect(snapshot['feedback'], isA<List>());
      expect(snapshot['note'].toString().toLowerCase(), contains('no audio'));
      final text = DataDeletionService.exportJson(snapshot);
      expect(text, contains('exp-1'));
    });

    test('deleteAllLocal wipes quotes, feedback and consent flags', () async {
      const item = QuoteLineItem(
        description: 'Tiles', quantity: 5, unit: 'sq ft', unitRatePaise: 5000);
      const editedItem = QuoteLineItem(
        description: 'Tiles', quantity: 6, unit: 'sq ft', unitRatePaise: 5000);
      await QuoteRepository.saveQuote(SavedQuote(
        id: 'del-1',
        quoteNumber: 'Q-2026-0009',
        createdAt: DateTime.now(),
        customerName: 'Client',
        lineItems: const [item],
      ));
      await FeedbackRepository.recordCorrection(
        quoteId: 'del-1', trade: 'tiling', original: item, edited: editedItem);
      await DiagnosticConsent.setOptedIn(true);
      expect((await FeedbackRepository.getAll()), isNotEmpty);

      final summary = await DataDeletionService.deleteAllLocal();
      expect((await QuoteRepository.getQuotes())
          .where((q) => q.id == 'del-1'), isEmpty);
      expect(await FeedbackRepository.getAll(), isEmpty);
      expect(await DiagnosticConsent.isOptedIn(), isFalse);
      expect(summary, contains('Deleted'));
    });
  });
}

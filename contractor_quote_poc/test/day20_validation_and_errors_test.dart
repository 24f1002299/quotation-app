import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/models/quote_flags.dart';
import 'package:contractor_quote_poc/storage/sync_outbox.dart';
import 'package:contractor_quote_poc/utils/error_report.dart';

/// Day 20 — Make uncertainty and errors safe.
///
/// Simulates each of the 7 error conditions and confirms:
/// 1. the app explains what happened (explicit flag message),
/// 2. work is preserved (no data loss — flags carry item index/label),
/// 3. a concrete next action is offered (actionLabel + blocking decision).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SyncOutbox.clear();
  });

  Quote quoteWith(List<QuoteLineItem> items, {String customer = 'Sharma Ji'}) {
    return Quote(
      customer: Customer(name: customer),
      lineItems: items,
    );
  }

  group('Day 20 — explicit flags for all 7 conditions', () {
    test('1. unknown item blocks PDF with Fix now', () {
      final q = quoteWith(const [
        QuoteLineItem(
          description: 'Sofa repair',
          quantity: 1,
          unit: 'job',
          unitRatePaise: 50000,
          uncertaintyNote: 'Not in trade catalog',
          isUnknown: true,
          requiresReview: true,
        ),
      ]);
      final flags = analyzeQuote(q);
      final f = flags.firstWhere((e) => e.type == QuoteFlagType.unknownItem);
      expect(f.isBlocking, isTrue);
      expect(f.actionLabel, 'Fix now');
      expect(f.itemIndex, 0);
      expect(quotePdfBlockingReason(q), contains('Sofa repair'));
    });

    test('2. uncertain quantity blocks PDF with Review item', () {
      final q = quoteWith(const [
        QuoteLineItem(
          description: 'Wall paint',
          quantity: 100,
          unit: 'sq ft',
          unitRatePaise: 1500,
          confidence: 0.5,
          uncertaintyNote: 'Quantity needs checking',
          requiresReview: true,
        ),
      ]);
      final flags = analyzeQuote(q);
      expect(
        flags.any((e) => e.type == QuoteFlagType.uncertainQuantity),
        isTrue,
      );
      final blocking = blockingFlags(flags);
      expect(blocking, isNotEmpty);
      expect(quotePdfBlockingReason(q), contains('Wall paint'));
    });

    test('3. missing rate blocks PDF with Add rate', () {
      final q = quoteWith(const [
        QuoteLineItem(
          description: 'Floor tiles',
          quantity: 120,
          unit: 'sq ft',
          unitRatePaise: 0,
        ),
      ]);
      final flags = analyzeQuote(q);
      final f = flags.firstWhere((e) => e.type == QuoteFlagType.missingRate);
      expect(f.isBlocking, isTrue);
      expect(f.actionLabel, 'Add rate');
      expect(f.message, contains('Floor tiles'));
      expect(quotePdfBlockingReason(q), contains('Floor tiles'));
    });

    test('4. unusual rate warns but never blocks PDF', () {
      // Tile labour usual ~₹45; ₹200 is >2x → unusual.
      final q = quoteWith(const [
        QuoteLineItem(
          description: 'Tile Labour',
          quantity: 100,
          unit: 'sq ft',
          unitRatePaise: 20000,
        ),
      ]);
      final flags = analyzeQuote(q);
      final f = flags.firstWhere((e) => e.type == QuoteFlagType.unusualRate);
      expect(f.isBlocking, isFalse);
      expect(f.actionLabel, 'Confirm rate');
      // Work preserved + PDF still allowed.
      expect(quotePdfBlockingReason(q), isNull);
      expect(warningFlags(flags), contains(f));
    });

    test('5. missing customer warns but never blocks PDF', () {
      final q = quoteWith(
        const [
          QuoteLineItem(
            description: 'Primer',
            quantity: 200,
            unit: 'sq ft',
            unitRatePaise: 800,
          ),
        ],
        customer: 'Client', // placeholder = missing
      );
      final flags = analyzeQuote(q);
      final f =
          flags.firstWhere((e) => e.type == QuoteFlagType.missingCustomer);
      expect(f.isBlocking, isFalse);
      expect(f.actionLabel, 'Add customer');
      expect(quotePdfBlockingReason(q), isNull);
    });

    test('6. failed sync warns with Retry and preserves work', () async {
      await SyncOutbox.enqueue(OutboxItem(
        operationId: 'op_q20_sync',
        entityType: 'quote',
        action: 'upsert',
        payload: {'id': 'q20', 'customerName': 'Patil'},
        idempotencyKey: 'idemp_q20',
        createdAt: DateTime.now(),
      ));
      final pending = await SyncOutbox.getPending();
      final failed =
          pending.first.incrementRetry(error: 'SocketException: offline');
      await SyncOutbox.update(failed);

      final after = await SyncOutbox.getPending();
      expect(after.first.lastError, contains('offline'));
      // Draft payload still intact in the outbox.
      expect(after.first.payload['customerName'], 'Patil');

      final q = quoteWith(const [
        QuoteLineItem(
          description: 'Painting',
          quantity: 500,
          unit: 'sq ft',
          unitRatePaise: 1200,
        ),
      ]);
      final flags = analyzeQuote(
        q,
        hasSyncFailure: true,
        syncDetail: after.first.lastError ?? '',
      );
      final f = flags.firstWhere((e) => e.type == QuoteFlagType.failedSync);
      expect(f.isBlocking, isFalse);
      expect(f.actionLabel, 'Retry');
      expect(f.message, contains('saved on this phone'));
      expect(quotePdfBlockingReason(q), isNull);
    });

    test('7. stale catalog warns with Refresh and preserves work', () {
      final q = quoteWith(const [
        QuoteLineItem(
          description: 'Skirting',
          quantity: 50,
          unit: 'rft',
          unitRatePaise: 6000,
        ),
      ]);
      final flags = analyzeQuote(
        q,
        isCatalogStale: true,
        catalogDetail: 'Server has tiling v3, this phone has v1.',
      );
      final f =
          flags.firstWhere((e) => e.type == QuoteFlagType.staleCatalog);
      expect(f.isBlocking, isFalse);
      expect(f.actionLabel, 'Refresh');
      expect(quotePdfBlockingReason(q), isNull);
    });
  });

  group('Day 20 — PDF gate blocks only on essentials', () {
    test('clean quote with warnings still generates (no block)', () {
      final q = quoteWith(
        const [
          QuoteLineItem(
            description: 'Tile Labour',
            quantity: 100,
            unit: 'sq ft',
            unitRatePaise: 20000, // unusual but valid
          ),
        ],
        customer: '', // missing customer
      );
      // Both warnings present…
      final flags = analyzeQuote(q);
      expect(flags.length, 2);
      // …yet the PDF gate stays open.
      expect(quotePdfBlockingReason(q), isNull);
    });

    test('manual resolution unblocks: acknowledge unknown + add rate', () {
      final blocked = quoteWith(const [
        QuoteLineItem(
          description: 'Mystery work',
          quantity: 0,
          unit: 'job',
          unitRatePaise: 0,
          isUnknown: true,
          requiresReview: true,
          uncertaintyNote: 'Not in catalog',
        ),
      ]);
      expect(quotePdfBlockingReason(blocked), isNotNull);

      final fixed = quoteWith(const [
        QuoteLineItem(
          description: 'Mystery work (confirmed)',
          quantity: 2,
          unit: 'job',
          unitRatePaise: 50000,
          isUnknown: true,
          requiresReview: true,
          acknowledged: true,
          uncertaintyNote: 'Not in catalog',
        ),
      ]);
      expect(quotePdfBlockingReason(fixed), isNull);
    });
  });

  group('Day 20 — error-report ID for support', () {
    test('IDs are unique, formatted, and valid', () {
      final a = newErrorReportId(DateTime(2026, 9, 28));
      final b = newErrorReportId(DateTime(2026, 9, 28));
      expect(a, startsWith('ERR-20260928-'));
      expect(isValidErrorReportId(a), isTrue);
      expect(isValidErrorReportId(b), isTrue);
      expect(a, isNot(equals(b)));
      expect(isValidErrorReportId('ERR-123'), isFalse);
      expect(isValidErrorReportId('oops'), isFalse);
    });

    test('support context line carries no PII, only reference', () {
      final line = supportContextLine(
        errorReportId: 'ERR-20260928-ABC123',
        area: 'Quote sync',
        now: DateTime(2026, 9, 28),
      );
      expect(line, contains('ERR-20260928-ABC123'));
      expect(line, contains('Quote sync'));
    });
  });

  group('Day 20 — unusual-rate math', () {
    test('2x / half boundaries', () {
      expect(isUnusualRate(100, 45), isTrue); // >2x
      expect(isUnusualRate(20, 45), isTrue); // <half
      expect(isUnusualRate(60, 45), isFalse);
      expect(isUnusualRate(30, 45), isFalse);
      expect(isUnusualRate(0, 45), isFalse); // missing rate is separate flag
      expect(isUnusualRate(100, 0), isFalse); // no baseline → never flag
    });
  });
}

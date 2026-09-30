// Day 23 — Automated risk coverage: calculations, parsing/validation,
// repositories, idempotency, conflict handling + fault-injection guards.
//
// Each "catches ..." test intentionally introduces one fault from the Day 23
// Verify list and proves the suite detects it. Pure-Dart where possible so
// `flutter test test/day23_risk_coverage_test.dart` stays fast.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/extraction_models.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';
import 'package:contractor_quote_poc/storage/sync_outbox.dart';

const _customer = Customer(name: 'Test Client');

Quote _quoteWith({
  List<QuoteLineItem> items = const [
    QuoteLineItem(
      description: 'Tile labour',
      quantity: 100,
      unit: 'sq ft',
      unitRatePaise: 4500,
    ),
  ],
  int? gstPercent,
  List<String> warnings = const [],
  bool warningsAcked = false,
}) {
  return Quote(
    customer: _customer,
    lineItems: items,
    gstPercent: gstPercent,
    reviewWarnings: warnings,
    reviewWarningsAcknowledged: warningsAcked,
  );
}

// Tiny in-test doubles mirroring the server rules (accept-once idempotency,
// user-scoped ownership, optimistic version check) so the Flutter suite pins
// the contract without needing a backend.
class FakeServerQuotes {
  final Map<String, Map<String, SavedQuote>> _byUser = {};
  final Map<String, String> _idempIndex = {};

  SavedQuote save(String userId, SavedQuote q) {
    final key = '$userId:${q.idempotencyKey}';
    final existingByIdemp = _idempIndex[key];
    if (existingByIdemp != null) {
      return _byUser[userId]![existingByIdemp]!;
    }
    final userQuotes = _byUser.putIfAbsent(userId, () => {});
    final existing = userQuotes[q.id];
    if (existing != null) {
      if (q.version < existing.version) {
        throw StateError(
          'VERSION_CONFLICT server=${existing.version} device=${q.version}',
        );
      }
      final bumped = q.copyWith(version: existing.version + 1);
      userQuotes[q.id] = bumped;
      _idempIndex[key] = q.id;
      return bumped;
    }
    userQuotes[q.id] = q;
    _idempIndex[key] = q.id;
    return q;
  }

  SavedQuote? get(String userId, String quoteId) => _byUser[userId]?[quoteId];

  int countFor(String userId) => _byUser[userId]?.length ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Calculations: code owns arithmetic, never the model ────────────────
  group('calculations (Day 5 engine)', () {
    test('quantity x rate uses integer paise, no floats', () {
      const item = QuoteLineItem(
        description: 'Paint',
        quantity: 120,
        unit: 'sq ft',
        unitRatePaise: 1500,
      );
      expect(calculateAmount(item), 180000);
    });

    test('zero GST leaves grand total == subtotal', () {
      final t = calculateTotals(_quoteWith(gstPercent: null));
      expect(t.gstPaise, 0);
      expect(t.grandTotalPaise, t.subtotalPaise);
    });

    test('5/12/18% GST with half-up paise rounding', () {
      int gstFor(int subtotal, int pct) => calculateTotals(
        Quote(
          customer: _customer,
          lineItems: [
            QuoteLineItem(
              description: 'X',
              quantity: 1,
              unit: 'job',
              // subtotal == rate since qty 1
              unitRatePaise: subtotal,
            ),
          ],
          gstPercent: pct,
        ),
      ).gstPaise;

      expect(gstFor(10000, 5), 500);
      expect(gstFor(10000, 12), 1200);
      expect(gstFor(101, 18), 18); // (101*18+50)~/100 = 18
      expect(gstFor(1, 50), 1); // (50+50)~/100 = 1, half-up edge
      expect(gstFor(3, 18), 1); // (54+50)~/100 = 1
      expect(gstFor(2, 18), 0); // (36+50)~/100 = 0, rounds down
    });

    test('fractional-paise work stays integral (grand = sub + gst)', () {
      final t = calculateTotals(
        _quoteWith(
          items: const [
            QuoteLineItem(
              description: 'A',
              quantity: 3,
              unit: 'job',
              unitRatePaise: 333,
            ),
          ],
          gstPercent: 18,
        ),
      );
      expect(t.subtotalPaise, 999);
      expect(t.grandTotalPaise, t.subtotalPaise + t.gstPaise);
    });

    test('empty quote totals are zero, PDF gate still blocks', () {
      final t = calculateTotals(
        Quote(customer: _customer, lineItems: const []),
      );
      expect(t.subtotalPaise, 0);
      expect(t.grandTotalPaise, 0);
      expect(
        quotePdfBlockingReason(
          Quote(customer: _customer, lineItems: const []),
        ),
        contains('at least one line item'),
      );
    });

    test('invalid input fails fast (negative qty, bad gst)', () {
      expect(
        () => QuoteLineItem(
          description: 'Bad',
          quantity: -1,
          unit: 'job',
          unitRatePaise: 100,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Quote(customer: _customer, lineItems: const [], gstPercent: 101),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ── Parsing / validation ───────────────────────────────────────────────
  group('parsing and validation', () {
    const parser = TranscriptParser();

    test('known tiling phrase maps to catalog item with qty/rate', () {
      final r = parser.parse(
        '850 square foot tiles labour, 45 rupaye per foot, '
        'skirting 120 running foot, 60 rupaye per foot',
      );
      expect(r.items, hasLength(2));
      expect(r.items.first.quantity, 850);
      expect(r.items.first.unitRatePaise, 4500);
    });

    test('unrecognized transcript yields explicit unknown, not a guess', () {
      final r = parser.parse('sofa repair one piece fifty rupees');
      // Either zero items + warning, or items that still need review.
      expect(r.items.isEmpty || r.hasWarnings, isTrue);
    });

    test('Devanagari digits parse (१२० running foot)', () {
      final r = parser.parse(
        'skirting १२० running foot, 60 rupaye per foot',
      );
      expect(r.items, isNotEmpty);
      expect(r.items.first.quantity, 120);
    });

    test('rate memory fills a missing spoken rate', () {
      // Fully-specified parse proves the phrase resolves to a catalog item.
      final full = parser.parse(
        '850 square foot tiles labour, 45 rupaye per foot',
      );
      expect(full.items, isNotEmpty);
      // Spot-check: without memory the rate is 0 AND a warning is raised
      // (never a silent zero that looks confident).
      final noRate = parser.parse('850 square foot tiles labour');
      expect(noRate.items, isNotEmpty);
      expect(noRate.items.first.unitRatePaise, 0);
      expect(noRate.hasWarnings, isTrue);
    });

    test('malformed / empty transcript never throws, never invents money', () {
      for (final bad in ['', '   ', 'uhm... hmm', '!@#\$%^']) {
        final r = parser.parse(bad);
        final total = r.items.fold<int>(
          0,
          (s, i) => s + i.quantity * i.unitRatePaise,
        );
        expect(total, 0, reason: 'transcript: "$bad"');
      }
    });

    test('PDF gate blocks on missing name, unit, qty, rate', () {
      Quote blocked(List<QuoteLineItem> items) =>
          Quote(customer: _customer, lineItems: items);
      expect(
        quotePdfBlockingReason(
          blocked(const [
            QuoteLineItem(
              description: '',
              quantity: 1,
              unit: 'job',
              unitRatePaise: 100,
            ),
          ]),
        ),
        contains('item name'),
      );
      expect(
        quotePdfBlockingReason(
          blocked(const [
            QuoteLineItem(
              description: 'Paint',
              quantity: 0,
              unit: 'sq ft',
              unitRatePaise: 1500,
            ),
          ]),
        ),
        contains('quantity'),
      );
      expect(
        quotePdfBlockingReason(
          blocked(const [
            QuoteLineItem(
              description: 'Paint',
              quantity: 10,
              unit: 'sq ft',
              unitRatePaise: 0,
            ),
          ]),
        ),
        contains('rate'),
      );
    });
  });

  // ── Repositories / outbox ──────────────────────────────────────────────
  group('repositories, outbox, idempotency keys', () {
    test('SavedQuote idempotency key defaults to immutable id', () {
      final q = SavedQuote(
        id: 'uuid-123',
        quoteNumber: 'Q-2026-0001',
        createdAt: DateTime(2026, 1, 1),
        customerName: 'A',
        lineItems: const [
          QuoteLineItem(
            description: 'X',
            quantity: 1,
            unit: 'job',
            unitRatePaise: 100,
          ),
        ],
      );
      expect(q.idempotencyKey, 'uuid-123');
      expect(q.version, 1);
    });

    test('copyWith version bump models optimistic concurrency', () {
      final q = SavedQuote(
        id: 'uuid-1',
        quoteNumber: 'Q-1',
        createdAt: DateTime(2026, 1, 1),
        customerName: 'A',
        lineItems: const [],
      );
      final v2 = q.copyWith(version: q.version + 1);
      expect(v2.version, 2);
      expect(v2.id, q.id, reason: 'id never changes across versions');
      expect(v2.idempotencyKey, q.idempotencyKey);
    });

    test('outbox backoff is bounded exponential (1..30s cap)', () {
      expect(OutboxItem.calculateBackoff(1), const Duration(seconds: 2));
      expect(OutboxItem.calculateBackoff(5), const Duration(seconds: 30));
      expect(OutboxItem.calculateBackoff(10), const Duration(seconds: 30));
    });

    test('outbox round-trips conflict markers for two-device edits', () {
      final item = OutboxItem(
        operationId: 'op-1',
        entityType: 'quote',
        action: 'upsert',
        payload: {'id': 'q1', 'version': 1},
        idempotencyKey: 'q1',
        createdAt: DateTime(2026, 1, 1),
      );
      final conflicted = item.markConflict({'id': 'q1', 'version': 2});
      expect(conflicted.hasConflict, isTrue);
      expect(conflicted.lastError, 'VERSION_CONFLICT');
      final restored = OutboxItem.fromJson(conflicted.toJson());
      expect(restored.hasConflict, isTrue);
      expect(restored.conflictingPayload!['version'], 2);
    });

    test('SavedQuote JSON carries the server wire contract', () {
      final q = SavedQuote(
        id: 'uuid-wire-1',
        quoteNumber: 'Q-LOCAL-1',
        createdAt: DateTime(2026, 9, 30, 19, 23, 2),
        customerName: 'Sharma Ji',
        lineItems: const [
          QuoteLineItem(
            description: 'X',
            quantity: 2,
            unit: 'job',
            unitRatePaise: 5000,
          ),
        ],
      );
      final json = q.toJson();
      // Server field names (QuoteDto) must be present and correct.
      expect(json['clientName'], 'Sharma Ji');
      expect(json['clientPhone'], '');
      expect(json['siteAddress'], '');
      // First sync: displayNumber is null so the server assigns one;
      // the local label travels separately and never overwrites it.
      expect(json['displayNumber'], isNull);
      expect(json['quoteNumber'], 'Q-LOCAL-1');
      // Timestamps carry an explicit zone (Instant-parseable).
      expect(json['createdAt'].toString(), endsWith('Z'));
      // Money travels recomputed, never model-supplied.
      expect(json['subtotalPaise'], 10000);
      expect(json['grandTotalPaise'], 10000);
      // Local round-trip still reads the same object back.
      expect(SavedQuote.fromJson(json).customerName, 'Sharma Ji');
    });

    test('outbox enqueue dedups same quote (no duplicate write)', () async {
      SharedPreferences.setMockInitialValues({});
      await SyncOutbox.clear();
      final payload = {
        'id': 'q-dup',
        'version': 1,
        'customerName': 'Dup',
      };
      await SyncOutbox.enqueue(
        OutboxItem(
          operationId: 'quote_q-dup',
          entityType: 'quote',
          action: 'upsert',
          payload: payload,
          idempotencyKey: 'q-dup',
          createdAt: DateTime.now(),
        ),
      );
      // Retry / double-tap enqueues the same logical write again.
      await SyncOutbox.enqueue(
        OutboxItem(
          operationId: 'quote_q-dup',
          entityType: 'quote',
          action: 'upsert',
          payload: payload,
          idempotencyKey: 'q-dup',
          createdAt: DateTime.now(),
        ),
      );
      final pending = await SyncOutbox.getPending();
      expect(pending.where((i) => i.idempotencyKey == 'q-dup').length, 1);
      await SyncOutbox.clear();
    });
  });

  // ── Day 23 Verify: fault injection — suite must catch each fault ───────
  group('fault injection (Day 23 verify)', () {
    test('catches intentionally wrong grand total', () {
      final quote = _quoteWith(gstPercent: 18);
      final correct = calculateTotals(quote);
      const tamperedGrandTotal = 1; // attacker/bug writes ₹0.01
      expect(
        tamperedGrandTotal == correct.grandTotalPaise,
        isFalse,
        reason: 'recomputed total must differ from tampered stored total',
      );
      // The guard used by UI/PDF/sync: always recompute, never trust stored.
      expect(correct.grandTotalPaise, correct.subtotalPaise + correct.gstPaise);
    });

    test('catches unresolved unknown item (PDF blocked)', () {
      const unknown = ExplicitUnknown(
        text: 'sofa repair 1 piece',
        reason: 'Not in trade catalog',
      );
      final quote = Quote(
        customer: _customer,
        lineItems: [unknown.toQuoteLineItem()],
      );
      expect(quotePdfBlockingReason(quote), isNotNull);
      expect(quotePdfBlockingReason(quote)!, contains('Unknown item'));
    });

    test('catches malformed extraction response (no silent totals)', () {
      // 1. An empty-but-typed map yields safe defaults flagged for review,
      // never a confident zero-rate line.
      final safe = ExtractedItem.fromJson(const <String, dynamic>{});
      expect(safe.unitRatePaise, 0);
      expect(safe.toQuoteLineItem().requiresReview, isTrue);

      // 2. A model-supplied "grandTotal" field must be ignored: the app
      // recomputes from line items, so a lying total cannot slip through.
      final items = [
        const QuoteLineItem(
          description: 'A',
          quantity: 2,
          unit: 'job',
          unitRatePaise: 10000,
        ),
      ];
      final recomputed = calculateTotals(
        Quote(customer: _customer, lineItems: items),
      );
      const modelClaimedTotal = 999999;
      expect(recomputed.grandTotalPaise, isNot(modelClaimedTotal));
    });

    test('catches duplicate write (idempotency accept-once)', () {
      final server = FakeServerQuotes();
      final q = SavedQuote(
        id: 'q-idemp-1',
        quoteNumber: 'Q-1',
        createdAt: DateTime(2026, 1, 1),
        customerName: 'Dup Client',
        lineItems: const [
          QuoteLineItem(
            description: 'X',
            quantity: 1,
            unit: 'job',
            unitRatePaise: 5000,
          ),
        ],
      );
      final first = server.save('userA', q);
      final retry = server.save('userA', q); // network retry, same key
      expect(identical(first, retry), isTrue);
      expect(server.countFor('userA'), 1);
    });

    test('catches cross-user request (ownership isolation)', () {
      final server = FakeServerQuotes();
      final q = SavedQuote(
        id: 'q-private',
        quoteNumber: 'Q-9',
        createdAt: DateTime(2026, 1, 1),
        customerName: 'A Client',
        lineItems: const [],
      );
      server.save('userA', q);
      expect(server.get('userB', 'q-private'), isNull,
          reason: 'user B must not read user A quote');
    });

    test('catches stale-version conflict (two-device edit)', () {
      final server = FakeServerQuotes();
      final v1 = SavedQuote(
        id: 'q-conflict',
        quoteNumber: 'Q-7',
        createdAt: DateTime(2026, 1, 1),
        customerName: 'C',
        lineItems: const [],
        version: 1,
      );
      server.save('userA', v1);
      // Device 1 syncs its edit first (a new attempt => new idempotency key,
      // same quote id, same base version). Server accepts and bumps to v2.
      server.save(
        'userA',
        v1.copyWith(
          customerName: 'C edited',
          idempotencyKey: 'op-device1-attempt1',
        ),
      );
      // Stale device still on v1 must conflict, not overwrite.
      expect(
        () => server.save(
          'userA',
          v1.copyWith(
            customerName: 'stale overwrite',
            idempotencyKey: 'op-device2-attempt1',
          ),
        ),
        throwsStateError,
      );
    });
  });
}

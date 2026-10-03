import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/models/service_item.dart';
import 'package:contractor_quote_poc/parser/demo_transcripts.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/templates/template_loader.dart';

/// The parser matches only what the user sells, so these tests run it against
/// the starter service lists a fresh install would be seeded with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const parser = TranscriptParser();

  late List<ServiceItem> tiling;
  late List<ServiceItem> painting;

  setUpAll(() async {
    tiling = await TemplateLoader.starterServiceItems(BusinessType.tiling);
    painting = await TemplateLoader.starterServiceItems(BusinessType.painting);
  });

  // ── Tiling demo phrase ────────────────────────────────────────────────────

  group('tiling demo transcript', () {
    late ParseResult result;

    setUpAll(() {
      result = parser.parse(kTilingDemoTranscript, services: tiling);
    });

    test('produces no warnings', () {
      expect(result.warnings, isEmpty,
          reason: 'Demo phrase should parse cleanly: ${result.warnings}');
    });

    test('produces exactly two line items', () {
      expect(result.items, hasLength(2));
    });

    test('first item is tile fixing — 850 sq ft at ₹45', () {
      final item = result.items[0];
      expect(item.description, contains('Tile fixing'));
      expect(item.quantity, equals(850));
      expect(item.unit, equals('sq ft'));
      expect(item.unitRatePaise, equals(4500)); // ₹45 × 100 paise
      expect(item.serviceItemId, isNotNull);
    });

    test('second item is skirting — 120 rft at ₹60', () {
      final item = result.items[1];
      expect(item.description, contains('Skirting'));
      expect(item.quantity, equals(120));
      expect(item.unit, equals('rft'));
      expect(item.unitRatePaise, equals(6000)); // ₹60 × 100 paise
    });

    test('subtotal equals ₹45,450 (matches Day-2 fixture)', () {
      final quote = Quote(
        customer: const Customer(name: 'Test'),
        lineItems: result.items.map((i) => i.toQuoteLineItem()).toList(),
      );
      final totals = calculateTotals(quote);
      // 850 × 4500 + 120 × 6000 = 3_825_000 + 720_000 = 4_545_000 paise = ₹45,450
      expect(totals.subtotalPaise, equals(4_545_000));
    });
  });

  // ── Painting demo phrase ──────────────────────────────────────────────────

  group('painting demo transcript', () {
    late ParseResult result;

    setUpAll(() {
      result = parser.parse(kPaintingDemoTranscript, services: painting);
    });

    test('produces no warnings', () {
      expect(result.warnings, isEmpty,
          reason: 'Demo phrase should parse cleanly: ${result.warnings}');
    });

    test('produces exactly two line items', () {
      expect(result.items, hasLength(2));
    });

    test('first item is wall putty — 1200 sq ft at ₹18', () {
      final item = result.items[0];
      expect(item.description, contains('Wall putty'));
      expect(item.quantity, equals(1200));
      expect(item.unit, equals('sq ft'));
      expect(item.unitRatePaise, equals(1800)); // ₹18 × 100 paise
    });

    test('second item is painting — 1200 sq ft at ₹12', () {
      final item = result.items[1];
      expect(item.description, contains('Interior wall painting'));
      expect(item.quantity, equals(1200));
      expect(item.unit, equals('sq ft'));
      expect(item.unitRatePaise, equals(1200)); // ₹12 × 100 paise
    });

    test('subtotal equals ₹36,000', () {
      final quote = Quote(
        customer: const Customer(name: 'Test'),
        lineItems: result.items.map((i) => i.toQuoteLineItem()).toList(),
      );
      final totals = calculateTotals(quote);
      // 1200 × 1800 + 1200 × 1200 = 2_160_000 + 1_440_000 = 3_600_000 paise = ₹36,000
      expect(totals.subtotalPaise, equals(3_600_000));
    });
  });

  // ── Unknown work — warning, no fabricated amount ──────────────────────────

  group('work that is not in the user list', () {
    test('produces a warning for an unknown item with numbers', () {
      final result = parser.parse(
        'Brick laying 500 square foot 25 rupaye per foot',
        services: tiling,
      );
      expect(result.items, isEmpty,
          reason: 'Should not fabricate a line item for an unknown item');
      expect(result.warnings, isNotEmpty,
          reason: 'Should warn that nothing was recognized');
      expect(result.warnings.first, contains('No services in your list match'));
    });

    test('returns empty result with no warning for text-only transcript', () {
      final result =
          parser.parse('Test customer name only', services: tiling);
      expect(result.items, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('empty string returns empty result', () {
      final result = parser.parse('', services: tiling);
      expect(result.items, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('an empty service list never invents an item', () {
      final result = parser.parse(kTilingDemoTranscript);
      expect(result.items, isEmpty);
      expect(result.warnings, isNotEmpty);
    });
  });

  // ── Day-24 fuzzy matching (noisy site transcripts) ───────────────────────

  group('bare-root matching', () {
    test('bare Latin "tiles" maps to tile fixing', () {
      final result =
          parser.parse('tiles 120 square feet at 45 rupaye', services: tiling);
      expect(result.items, hasLength(1));
      expect(result.items.first.description, contains('Tile fixing'));
      expect(result.items.first.quantity, equals(120));
      expect(result.items.first.unitRatePaise, equals(4500));
    });

    test('bare Devanagari root maps with real-transcript shape', () {
      final result =
          parser.parse('किचन टाइल 120 वर्ग फुट 45 रुपये', services: tiling);
      expect(result.items, hasLength(1));
      expect(result.items.first.description, contains('Tile fixing'));
      expect(result.items.first.quantity, equals(120));
      expect(result.items.first.unit, equals('sq ft'));
      expect(result.items.first.unitRatePaise, equals(4500));
    });

    test('Devanagari putty root maps to wall putty', () {
      final result =
          parser.parse('पुट्टी 500 square feet at 18 rupaye', services: painting);
      expect(result.items, hasLength(1));
      expect(result.items.first.description, contains('Wall putty'));
      expect(result.items.first.quantity, equals(500));
    });

    test('waterproofing maps when the user sells it', () {
      // The tiling starter list has no waterproofing service, so the test
      // gives the user one — matching depends on what is sold, not the
      // business type.
      final withWaterproofing = [
        ...tiling,
        ServiceItem(
          id: 'svc_waterproofing',
          name: 'Waterproofing',
          unit: 'sq ft',
          ratePaise: 3000,
          businessType: BusinessType.tiling,
          keywords: const ['waterproofing', 'waterproof'],
          updatedAt: DateTime.now(),
        ),
      ];
      final result = parser.parse(
        'bathroom waterproofing 50 sq ft at 30 rupaye',
        services: withWaterproofing,
      );
      expect(result.items, hasLength(1));
      expect(result.items.first.description, contains('Waterproofing'));
    });

    test('root does not match inside a longer Devanagari word', () {
      // 'रंग' (paint root) sits inside 'औरंगाबाद' — strict boundaries
      // must prevent a painting false positive.
      final result = parser.parse(
        'औरंगाबाद tiles 100 square feet at 45 rupaye',
        services: tiling,
      );
      expect(result.items, hasLength(1));
      expect(result.items.first.description, contains('Tile fixing'));
    });

    test('plaster stays an explicit unknown (not in the tiling starter list)',
        () {
      final result = parser.parse(
        'terrace plaster 200 square feet at 30 rupaye',
        services: tiling,
      );
      expect(result.items, isEmpty);
      expect(result.warnings, isNotEmpty);
    });

    test('Devanagari digits are normalised before matching', () {
      final result = parser.parse(
        'tiles १२० running foot at 45 rupaye',
        services: tiling,
      );
      expect(result.items, hasLength(1));
      expect(result.items.first.quantity, equals(120));
      expect(result.items.first.unit, equals('rft'));
    });
  });

  // ── Saved rates ───────────────────────────────────────────────────────────

  test('a saved service rate fills a rate the speaker omitted', () {
    final id = tiling.first.id;
    final result = parser.parse(
      '120 square foot tile fixing',
      services: tiling,
      savedRates: {id: 8500},
    );
    expect(result.items, hasLength(1));
    expect(result.items.first.unitRatePaise, equals(8500));
    expect(result.warnings, isEmpty);
  });

  // ── toQuoteLineItem round-trip ────────────────────────────────────────────

  test('ParsedLineItem.toQuoteLineItem preserves all fields', () {
    const parsed = ParsedLineItem(
      description: 'Tile fixing',
      quantity: 100,
      unit: 'sq ft',
      unitRatePaise: 5000,
      serviceItemId: 'svc_1',
    );
    final li = parsed.toQuoteLineItem();
    expect(li.description, equals(parsed.description));
    expect(li.quantity, equals(parsed.quantity));
    expect(li.unit, equals(parsed.unit));
    expect(li.unitRatePaise, equals(parsed.unitRatePaise));
    expect(li.serviceItemId, equals('svc_1'));
  });
}

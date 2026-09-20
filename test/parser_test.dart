import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/parser/demo_transcripts.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';

void main() {
  const parser = TranscriptParser();

  // ── Tiling demo phrase ────────────────────────────────────────────────────

  group('tiling demo transcript', () {
    late ParseResult result;

    setUpAll(() {
      result = parser.parse(kTilingDemoTranscript);
    });

    test('produces no warnings', () {
      expect(result.warnings, isEmpty,
          reason: 'Demo phrase should parse cleanly: ${result.warnings}');
    });

    test('produces exactly two line items', () {
      expect(result.items, hasLength(2));
    });

    test('first item is tile labour — 850 sq ft at ₹45', () {
      final item = result.items[0];
      expect(item.description, contains('Tile Labour'));
      expect(item.quantity, equals(850));
      expect(item.unit, equals('sq ft'));
      expect(item.unitRatePaise, equals(4500)); // ₹45 × 100 paise
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
      result = parser.parse(kPaintingDemoTranscript);
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
      expect(item.description, contains('Wall Putty'));
      expect(item.quantity, equals(1200));
      expect(item.unit, equals('sq ft'));
      expect(item.unitRatePaise, equals(1800)); // ₹18 × 100 paise
    });

    test('second item is painting — 1200 sq ft at ₹12', () {
      final item = result.items[1];
      expect(item.description, contains('Painting'));
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

  // ── Unknown item — warning, no fabricated amount ──────────────────────────

  group('unrecognized transcript', () {
    test('produces a warning for an unknown item with numbers', () {
      final result = parser.parse(
        'Brick laying 500 square foot 25 rupaye per foot',
      );
      expect(result.items, isEmpty,
          reason: 'Should not fabricate a line item for an unknown item');
      expect(result.warnings, isNotEmpty,
          reason: 'Should warn that nothing was recognized');
      expect(result.warnings.first, contains('No recognized items'));
    });

    test('returns empty result with no warning for text-only transcript', () {
      final result = parser.parse('Test customer name only');
      expect(result.items, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('empty string returns empty result', () {
      final result = parser.parse('');
      expect(result.items, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  // ── toQuoteLineItem round-trip ────────────────────────────────────────────

  test('ParsedLineItem.toQuoteLineItem preserves all fields', () {
    const parsed = ParsedLineItem(
      description: 'Tile Labour / टाइल मजदूरी',
      quantity: 100,
      unit: 'sq ft',
      unitRatePaise: 5000,
    );
    final li = parsed.toQuoteLineItem();
    expect(li.description, equals(parsed.description));
    expect(li.quantity, equals(parsed.quantity));
    expect(li.unit, equals(parsed.unit));
    expect(li.unitRatePaise, equals(parsed.unitRatePaise));
  });
}

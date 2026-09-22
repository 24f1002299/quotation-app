import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/extraction_models.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/models/rate_memory_item.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/screens/voice_screen.dart';
import 'package:contractor_quote_poc/storage/rate_memory_repository.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';
import 'package:contractor_quote_poc/voice/extraction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Day 13 — Capture-to-Extraction: 10 Representative Voice Samples', () {
    // ── Sample 1: Standard Tiling note in Hindi ─────────────────────────────
    test('Sample 1: Standard Tiling note in Hindi extracts items with subtotal ₹45,450', () async {
      const transcript = 'टाइल लगाना 850 स्क्वायर फीट 45 रुपये, स्कर्टिंग 120 रनिंग फीट 60 रुपये';

      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/extract'));
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['trade'], equals('tiling'));
        expect(body['transcript'], equals(transcript));

        return http.Response(
          json.encode({
            'trade': 'tiling',
            'lineItems': [
              {
                'catalogItemId': 'tile_labour',
                'description': 'Tile Labour / टाइल मजदूरी',
                'quantity': 850,
                'unit': 'sq ft',
                'unitRatePaise': 4500,
                'rateSource': 'EXPLICIT',
                'confidence': 0.98,
              },
              {
                'catalogItemId': 'skirting',
                'description': 'Skirting / स्कर्टिंग',
                'quantity': 120,
                'unit': 'rft',
                'unitRatePaise': 6000,
                'rateSource': 'EXPLICIT',
                'confidence': 0.97,
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.tiling,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(2));
      expect(result.lineItems[0].quantity, equals(850));
      expect(result.lineItems[0].unitRatePaise, equals(4500));
      expect(result.lineItems[1].quantity, equals(120));
      expect(result.lineItems[1].unitRatePaise, equals(6000));
      expect(result.requiresReview, isTrue);

      final lineItems = result.lineItems.map((i) => i.toQuoteLineItem()).toList();
      final quote = Quote(
        customer: const Customer(name: 'Suresh Kumar'),
        lineItems: lineItems,
        originalTranscript: transcript,
      );
      expect(calculateTotals(quote).subtotalPaise, equals(4545000)); // ₹45,450
    });

    // ── Sample 2: Standard Painting note in Hindi/English ───────────────────
    test('Sample 2: Standard Painting note in Hindi/English extracts putty & paint ₹36,000', () async {
      const transcript = 'wall putty 1200 square feet rate 18, painting 1200 sq ft 12 rupaye';

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'trade': 'painting',
            'lineItems': [
              {
                'catalogItemId': 'wall_putty',
                'description': 'Wall Putty / पुट्टी',
                'quantity': 1200,
                'unit': 'sq ft',
                'unitRatePaise': 1800,
                'rateSource': 'EXPLICIT',
                'confidence': 0.95,
              },
              {
                'catalogItemId': 'interior_painting',
                'description': 'Interior Painting / पेंटिंग',
                'quantity': 1200,
                'unit': 'sq ft',
                'unitRatePaise': 1200,
                'rateSource': 'EXPLICIT',
                'confidence': 0.95,
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.painting,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(2));
      final lineItems = result.lineItems.map((i) => i.toQuoteLineItem()).toList();
      final quote = Quote(
        customer: const Customer(name: 'Asha Verma'),
        lineItems: lineItems,
        originalTranscript: transcript,
      );
      expect(calculateTotals(quote).subtotalPaise, equals(3600000)); // ₹36,000
    });

    // ── Sample 3: Marathi quantity-only note with contractor rate memory ────
    test('Sample 3: Marathi quantity-only note applies saved rate from rate memory', () async {
      // Seed rate memory for tiling labour at ₹45/sq ft
      await RateMemoryRepository.saveRate(
        RateMemoryItem(
          id: 'rm_tile_labour',
          catalogItemId: 'tile_labour',
          trade: Trade.tiling,
          unit: 'sq ft',
          unitRatePaise: 4500,
          updatedAt: DateTime(2026, 9, 22),
        ),
      );

      const transcript = 'टाईल लेबर 500 स्क्वेअर फूट';

      final mockClient = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        final rateMem = body['rateMemory'] as List<dynamic>;
        expect(rateMem, isNotEmpty);
        expect(rateMem.any((r) => r['catalogItemId'] == 'tile_labour' && r['unitRatePaise'] == 4500), isTrue);

        return http.Response(
          json.encode({
            'trade': 'tiling',
            'lineItems': [
              {
                'catalogItemId': 'tile_labour',
                'description': 'Tile Labour / टाइल मजदूरी',
                'quantity': 500,
                'unit': 'sq ft',
                'unitRatePaise': 4500,
                'rateSource': 'RATE_MEMORY',
                'confidence': 0.94,
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.tiling,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(1));
      expect(result.lineItems[0].unitRatePaise, equals(4500));
      expect(result.lineItems[0].rateSource, equals(ExtractedRateSource.rateMemory));

      final quote = Quote(
        customer: const Customer(name: 'Sunil Patil'),
        lineItems: result.lineItems.map((i) => i.toQuoteLineItem()).toList(),
      );
      expect(calculateTotals(quote).subtotalPaise, equals(2250000)); // 500 * 45 = ₹22,500
    });

    // ── Sample 4: Hinglish mixed numbers note ───────────────────────────────
    test('Sample 4: Hinglish mixed numbers and rates extracts cleanly', () async {
      const transcript = 'kitchen tile 300 sq ft rate 50, skirting 40 rft bhav 55';

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'trade': 'tiling',
            'lineItems': [
              {
                'catalogItemId': 'tile_labour',
                'description': 'Tile Labour / टाइल मजदूरी',
                'quantity': 300,
                'unit': 'sq ft',
                'unitRatePaise': 5000,
                'rateSource': 'EXPLICIT',
                'confidence': 0.95,
              },
              {
                'catalogItemId': 'skirting',
                'description': 'Skirting / स्कर्टिंग',
                'quantity': 40,
                'unit': 'rft',
                'unitRatePaise': 5500,
                'rateSource': 'EXPLICIT',
                'confidence': 0.93,
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.tiling,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(2));
      final quote = Quote(
        customer: const Customer(name: 'Deepak Sharma'),
        lineItems: result.lineItems.map((i) => i.toQuoteLineItem()).toList(),
      );
      // 300 * 50 = 15,000 + 40 * 55 = 2,200 -> ₹17,200
      expect(calculateTotals(quote).subtotalPaise, equals(1720000));
    });

    // ── Sample 5: Mixed with unrecognized work ──────────────────────────────
    test('Sample 5: Mixed with unrecognized work captures explicit unknowns for review', () async {
      const transcript = 'kitchen tile 200 sq ft 50 rupaye, sofa repair 1 piece';

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'trade': 'tiling',
            'lineItems': [
              {
                'catalogItemId': 'tile_labour',
                'description': 'Tile Labour / टाइल मजदूरी',
                'quantity': 200,
                'unit': 'sq ft',
                'unitRatePaise': 5000,
                'rateSource': 'EXPLICIT',
              },
            ],
            'unknowns': [
              {
                'text': 'sofa repair 1 piece',
                'suspectedTerm': 'sofa repair',
                'reason': 'Item is not a tiling trade service',
                'confidence': 0.85,
              },
            ],
            'requiresReview': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.tiling,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(1));
      expect(result.unknowns, hasLength(1));
      expect(result.unknowns[0].text, equals('sofa repair 1 piece'));
      expect(result.requiresReview, isTrue);
    });

    // ── Sample 6: Server timeout simulation ─────────────────────────────────
    test('Sample 6: Server timeout automatically falls back to local parser without data loss', () async {
      const transcript = 'टाइल लगाना 100 स्क्वायर फीट 50 रुपये';

      final mockClient = MockClient((request) async {
        throw TimeoutException('Simulated network timeout after 6s');
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.tiling,
        client: mockClient,
      );

      // Verify zero data loss: local parser extracted the item
      expect(result.isFromLocalFallback, isTrue);
      expect(result.lineItems, isNotEmpty);
      expect(result.lineItems[0].quantity, equals(100));
      expect(result.lineItems[0].unitRatePaise, equals(5000));
      expect(result.errorMessage, contains('timed out'));
    });

    // ── Sample 7: Server 503 / Unavailable simulation ───────────────────────
    test('Sample 7: Server 503 unavailable gracefully falls back to local parser', () async {
      const transcript = 'wall putty 500 sq ft 20 rupaye';

      final mockClient = MockClient((request) async {
        return http.Response('Service Temporarily Unavailable', 503);
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.painting,
        client: mockClient,
      );

      expect(result.isFromLocalFallback, isTrue);
      expect(result.lineItems, isNotEmpty);
      expect(result.lineItems[0].quantity, equals(500));
      expect(result.lineItems[0].unitRatePaise, equals(2000));
      expect(result.errorMessage, contains('503'));
    });

    // ── Sample 8: Malformed JSON response simulation ────────────────────────
    test('Sample 8: Malformed JSON response gracefully falls back to local parser', () async {
      const transcript = 'painting 800 sq ft 15 rupaye';

      final mockClient = MockClient((request) async {
        return http.Response('{invalid json syntax string', 200);
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.painting,
        client: mockClient,
      );

      expect(result.isFromLocalFallback, isTrue);
      expect(result.lineItems, isNotEmpty);
      expect(result.lineItems[0].quantity, equals(800));
      expect(result.lineItems[0].unitRatePaise, equals(1500));
    });

    // ── Sample 9: Conversational preamble-only speech ───────────────────────
    test('Sample 9: Conversational preamble-only speech does not crash and preserves draft', () async {
      const transcript = 'नमस्ते भाई साहब मुझे कल का कोटेशन चाहिए';

      final mockClient = MockClient((request) async {
        return http.Response(
          json.encode({
            'trade': 'tiling',
            'lineItems': [],
            'unknowns': [
              {
                'text': transcript,
                'reason': 'No measurable quantities or items found in conversational preamble',
              },
            ],
            'requiresReview': true,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        trade: Trade.tiling,
        client: mockClient,
      );

      expect(result.lineItems, isEmpty);
      expect(result.unknowns, hasLength(1));
      expect(result.requiresReview, isTrue);
    });

    // ── Sample 10: Explicit type-it-instead / manual quote path ─────────────
    test('Sample 10: Explicit manual quote creation produces needsReview draft', () {
      final manualQuote = SavedQuote(
        id: 'quote_manual_101',
        quoteNumber: 'Q-2026-0101',
        createdAt: DateTime(2026, 9, 22),
        trade: Trade.tiling,
        customerName: 'Vinod Mehra',
        customerPhone: '+91 99887 76655',
        lineItems: const [
          QuoteLineItem(
            description: 'Granite Flooring / ग्रेनाइट फर्श',
            quantity: 150,
            unit: 'sq ft',
            unitRatePaise: 8000, // ₹80
          ),
        ],
        status: 'needsReview',
      );

      expect(manualQuote.status, equals('needsReview'));
      expect(manualQuote.grandTotalPaise, equals(1200000)); // ₹12,000

      // Serialization round-trip
      final jsonMap = manualQuote.toJson();
      expect(jsonMap['status'], equals('needsReview'));

      final restored = SavedQuote.fromJson(jsonMap);
      expect(restored.status, equals('needsReview'));
      expect(restored.grandTotalPaise, equals(1200000));
    });
  });

  group('Day 13 — UI & Recovery Widget Tests', () {
    testWidgets('VoiceScreen provides explicit "Type quote instead" button when idle', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: VoiceScreen(trade: Trade.tiling),
        ),
      );

      expect(find.text('Type quote instead / लिखकर बनाएं'), findsOneWidget);
    });

    testWidgets('VoiceScreen provides "Type quote instead" button when transcript is present', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: VoiceScreen(trade: Trade.tiling),
        ),
      );

      // Tap demo button to populate transcript
      await tester.tap(find.text('Use Tiling Demo / टाइलिंग डेमो'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Create Quote / कोटेशन बनाएं'), findsOneWidget);
      expect(find.text('Type quote instead / लिखकर बनाएं'), findsOneWidget);
    });

    testWidgets('ReviewScreen renders needsReview items and allows manual editing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewScreen(
            trade: Trade.tiling,
            originalTranscript: 'टाइल लगाना 100 स्क्वायर फीट 50 रुपये',
            parsingWarnings: const ['Check rate with customer'],
            initialLineItems: const [
              QuoteLineItem(
                description: 'Tile Labour',
                quantity: 100,
                unit: 'sq ft',
                unitRatePaise: 5000,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Tile Labour'), findsOneWidget);
      expect(find.text('₹5,000'), findsNWidgets(3)); // item amount + summary + bottom bar
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/quote_history_screen.dart';
import 'package:contractor_quote_poc/storage/quote_repository.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedQuote Model & Serialization', () {
    test('SavedQuote serializes to JSON and deserializes back faithfully', () {
      final original = SavedQuote(
        id: 'test_123',
        quoteNumber: 'Q-2026-9999',
        createdAt: DateTime(2026, 9, 20, 10, 30),
        trade: Trade.tiling,
        customerName: 'Mahesh Sharma',
        customerPhone: '+91 98765 00000',
        customerAddress: 'Flat 101, Pune',
        validityDays: 30,
        notes: 'Strict deadline',
        originalTranscript: '850 sq ft flooring 45 rate',
        lineItems: const [
          QuoteLineItem(
            description: 'Tile Labour',
            quantity: 850,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
        ],
        gstPercent: 18,
      );

      final json = original.toJson();
      final restored = SavedQuote.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.quoteNumber, equals(original.quoteNumber));
      expect(restored.trade, equals(original.trade));
      expect(restored.customerName, equals(original.customerName));
      expect(restored.customerPhone, equals(original.customerPhone));
      expect(restored.validityDays, equals(original.validityDays));
      expect(restored.notes, equals(original.notes));
      expect(restored.originalTranscript, equals(original.originalTranscript));
      expect(restored.lineItems.length, equals(1));
      expect(restored.lineItems.first.description, equals('Tile Labour'));
      expect(restored.lineItems.first.quantity, equals(850));
      expect(restored.lineItems.first.unitRatePaise, equals(4500));
      expect(restored.gstPercent, equals(18));

      // Domain Quote conversion
      final domainQuote = restored.toQuote();
      expect(domainQuote.customer.name, equals('Mahesh Sharma'));
      final totals = calculateTotals(domainQuote);
      expect(totals.subtotalPaise, equals(850 * 4500));
    });
  });

  group('QuoteRepository Storage Operations', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getQuotes seeds initial demo quotes when storage is empty', () async {
      final quotes = await QuoteRepository.getQuotes();
      expect(quotes, isNotEmpty);
      expect(quotes.length, equals(2));
      expect(quotes.any((q) => q.trade == Trade.tiling), isTrue);
      expect(quotes.any((q) => q.trade == Trade.painting), isTrue);
    });

    test('saveQuote persists new quote and retrieves it', () async {
      final newQuote = SavedQuote(
        id: 'new_quote_test',
        quoteNumber: 'Q-2026-0099',
        createdAt: DateTime.now(),
        customerName: 'Sunil Patil',
        lineItems: const [
          QuoteLineItem(
            description: 'Waterproofing',
            quantity: 500,
            unit: 'sq ft',
            unitRatePaise: 8000,
          ),
        ],
      );

      await QuoteRepository.saveQuote(newQuote);

      final quotes = await QuoteRepository.getQuotes();
      expect(quotes.any((q) => q.id == 'new_quote_test'), isTrue);

      final fetched = await QuoteRepository.getQuoteById('new_quote_test');
      expect(fetched, isNotNull);
      expect(fetched!.customerName, equals('Sunil Patil'));
    });

    test('deleteQuote removes the quote from storage', () async {
      final quotes = await QuoteRepository.getQuotes();
      final idToDelete = quotes.first.id;

      await QuoteRepository.deleteQuote(idToDelete);

      final remaining = await QuoteRepository.getQuotes();
      expect(remaining.any((q) => q.id == idToDelete), isFalse);
    });
  });

  group('QuoteHistoryScreen Widget Test', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Quote History with seeded quotes and totals', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: QuoteHistoryScreen(),
        ),
      );

      // Wait for FutureBuilder to complete
      await tester.pumpAndSettle();

      // Verify screen title
      expect(find.text('Quote History / पुराने कोटेशन'), findsOneWidget);

      // Verify seed customer cards are displayed
      expect(find.text('Sharma Ji / शर्मा जी'), findsOneWidget);
      expect(find.text('Verma Ji / वर्मा जी'), findsOneWidget);

      // Verify totals formatted in Rupees
      expect(find.text('₹45,450'), findsOneWidget);
      expect(find.text('₹36,000'), findsOneWidget);

      // Verify trade badges
      expect(find.text('Tiling'), findsOneWidget);
      expect(find.text('Painting'), findsOneWidget);
    });
  });
}

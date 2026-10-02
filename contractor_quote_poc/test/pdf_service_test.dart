import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/pdf/pdf_service.dart';
import 'package:contractor_quote_poc/screens/pdf_preview_screen.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/storage/quote_repository.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfService A4 Quotation Generation', () {
    test('generates valid PDF document for tiling quote fixture', () async {
      final quote = Quote(
        customer: const Customer(
          name: 'Suresh Sharma / सुरेश शर्मा',
          phone: '+91 98765 43210',
          address: 'Flat 402, Shiv Darshan, Andheri East, Mumbai',
        ),
        lineItems: const [
          QuoteLineItem(
            description: 'Tile Labour / टाइल मजदूरी',
            quantity: 850,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
          QuoteLineItem(
            description: 'Skirting / स्कर्टिंग',
            quantity: 120,
            unit: 'rft',
            unitRatePaise: 6000,
          ),
        ],
      );

      final pdfBytes = await PdfService.generateQuotationPdf(
        quote: quote,
        businessType: BusinessType.tiling,
        quoteNumber: 'Q-2026-0042',
        validityDays: 15,
        notes: '50% advance before tile purchase, balance on work completion.',
      );

      // Verify non-empty byte buffer
      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(1000));

      // Verify PDF header magic bytes "%PDF-"
      final header = ascii.decode(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generates valid PDF document for painting quote fixture', () async {
      final quote = Quote(
        customer: const Customer(
          name: 'Anita Verma',
          phone: '+91 98220 12345',
        ),
        lineItems: const [
          QuoteLineItem(
            description: 'Wall Putty / वॉल पुट्टी',
            quantity: 1200,
            unit: 'sq ft',
            unitRatePaise: 1800,
          ),
          QuoteLineItem(
            description: 'Painting / पेंटिंग',
            quantity: 1200,
            unit: 'sq ft',
            unitRatePaise: 1200,
          ),
        ],
        gstPercent: 18,
      );

      final pdfBytes = await PdfService.generateQuotationPdf(
        quote: quote,
        businessType: BusinessType.painting,
        quoteNumber: 'Q-2026-0043',
        validityDays: 30,
        notes: 'Includes Asian Paints Royale luxury emulsion, 2 coats.',
      );

      expect(pdfBytes.length, greaterThan(1000));
      final header = ascii.decode(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('handles long customer names and edge-case multi-line notes without error', () async {
      final quote = Quote(
        customer: const Customer(
          name: 'Shri Vikramaditya Chandrashekhar Rajopadhye and Associates Construction Private Limited',
          phone: '+91 99887 76655',
          address: 'Plot 105, Near Old Water Tank, Sector 19, Vashi, Navi Mumbai, Maharashtra 400703',
        ),
        lineItems: const [
          QuoteLineItem(
            description: 'Custom Water-Proofing Epoxy Coating with Primer & Double Sealant / वॉटरप्रूफिंग',
            quantity: 550,
            unit: 'sq ft',
            unitRatePaise: 8500,
          ),
        ],
      );

      final pdfBytes = await PdfService.generateQuotationPdf(
        quote: quote,
        notes: 'Note line 1: Material procurement starts post 50% advance.\n'
            'Note line 2: Site readiness to be confirmed by client.\n'
            'Note line 3: Additional coats or repairs will be billed on actuals.',
      );

      expect(pdfBytes.length, greaterThan(1000));
      final header = ascii.decode(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });
  });

  group('PdfPreviewScreen Widget Test', () {
    testWidgets('renders PDF preview screen and businessType badge', (WidgetTester tester) async {
      final quote = Quote(
        customer: const Customer(name: 'Ramesh Patel', phone: '9876543210'),
        lineItems: const [
          QuoteLineItem(
            description: 'Tile Labour',
            quantity: 850,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PdfPreviewScreen(
            quote: quote,
            businessType: BusinessType.tiling,
          ),
        ),
      );

      // Verify app bar title (Day 18: "Quotation ready" per design.md §6)
      expect(find.text('Quotation ready'), findsOneWidget);
      // Verify businessType chip (generic metadata label, all types).
      expect(find.text('Tiling'), findsOneWidget);
    });

    testWidgets('Day-24: Edit quote returns to Review with saved items, never Home',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      const lineItems = [
        QuoteLineItem(
          description: 'Tile Labour',
          quantity: 10,
          unit: 'sq ft',
          unitRatePaise: 4500,
        ),
      ];
      final quote = Quote(
        id: 'edit-flow-1',
        quoteNumber: 'Q-EDIT-1',
        customer: const Customer(name: 'Edit Client'),
        lineItems: lineItems,
      );
      await QuoteRepository.saveQuoteLocallyOnly(
        SavedQuote(
          id: 'edit-flow-1',
          quoteNumber: 'Q-EDIT-1',
          createdAt: DateTime(2026, 9, 30),
          customerName: 'Edit Client',
          lineItems: lineItems,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfPreviewScreen(
                      quote: quote,
                      businessType: BusinessType.tiling,
                    ),
                  ),
                ),
                child: const Text('open preview'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open preview'));
      // PdfPreview keeps a ticker alive, so pumpAndSettle never finishes —
      // advance time explicitly instead.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Quotation ready'), findsOneWidget);

      await tester.tap(find.text('Edit quote'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Must land on the Review screen with the saved line item —
      // not Home, not a blank screen.
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Tile Labour'), findsWidgets);
    });
  });
}

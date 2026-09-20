import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/pdf/pdf_service.dart';
import 'package:contractor_quote_poc/screens/pdf_preview_screen.dart';

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
        trade: Trade.tiling,
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
        trade: Trade.painting,
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
    testWidgets('renders PDF preview screen and trade badge', (WidgetTester tester) async {
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
            trade: Trade.tiling,
          ),
        ),
      );

      // Verify app bar title
      expect(find.text('PDF Preview / पूर्वावलोकन'), findsOneWidget);
      // Verify trade chip
      expect(find.text('🪣 Tiling'), findsOneWidget);
    });
  });
}

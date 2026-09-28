import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/pdf/pdf_service.dart';
import 'package:contractor_quote_poc/screens/pdf_preview_screen.dart';
import 'package:contractor_quote_poc/storage/pdf_backup_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 18 — Share and regenerate PDFs', () {
    test('stable storage name is anchored to quote ID, share name is friendly',
        () {
      // Same quote ID → same storage path even if customer name changes.
      expect(
        PdfService.stableFileNameForQuote('abc-123'),
        PdfService.stableFileNameForQuote('abc-123'),
      );
      expect(
        PdfService.stableFileNameForQuote('abc-123'),
        'Quotation_abc-123.pdf',
      );
      // Different quotes → different files.
      expect(
        PdfService.stableFileNameForQuote('id-1') ==
            PdfService.stableFileNameForQuote('id-2'),
        isFalse,
      );
      // Share-sheet label stays human-friendly.
      expect(
        PdfService.shareFileNameForQuote('Ravi Kumar'),
        'Quotation_Ravi_Kumar.pdf',
      );
      expect(
        PdfService.shareFileNameForQuote('  '),
        'Quotation_Client.pdf',
      );
    });

    test('PDF backup is opt-in only and defaults to OFF', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PdfBackupSettings.isOptedIn(), isFalse);

      await PdfBackupSettings.setOptedIn(true);
      expect(await PdfBackupSettings.isOptedIn(), isTrue);

      await PdfBackupSettings.setOptedIn(false);
      expect(await PdfBackupSettings.isOptedIn(), isFalse);
    });

    test('edit a value, regenerate, new total is reflected', () async {
      const v1Items = [
        QuoteLineItem(
          description: 'Tile labour',
          quantity: 100,
          unit: 'sq ft',
          unitRatePaise: 4000,
        ),
      ];
      const v2Items = [
        QuoteLineItem(
          description: 'Tile labour',
          quantity: 200, // edited quantity
          unit: 'sq ft',
          unitRatePaise: 4000,
        ),
      ];

      final v1 = Quote(
        id: 'day18-regen-1',
        quoteNumber: 'Q-2026-R1',
        customer: const Customer(name: 'Ravi Kumar'),
        lineItems: v1Items,
      );
      final v2 = Quote(
        id: 'day18-regen-1', // same immutable ID → same local file
        quoteNumber: 'Q-2026-R1',
        customer: const Customer(name: 'Ravi Kumar'),
        lineItems: v2Items,
      );

      expect(calculateTotals(v1).grandTotalPaise, 400000); // ₹4,000
      expect(calculateTotals(v2).grandTotalPaise, 800000); // ₹8,000

      // Both revisions render valid PDFs; stable path is identical.
      final pdf1 = await PdfService.generateQuotationPdf(quote: v1);
      final pdf2 = await PdfService.generateQuotationPdf(quote: v2);
      for (final bytes in [pdf1, pdf2]) {
        expect(bytes, isA<Uint8List>());
        expect(bytes.length, greaterThan(1000));
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      }
      expect(
        PdfService.stableFileNameForQuote(v1.id!),
        PdfService.stableFileNameForQuote(v2.id!),
      );
    });

    testWidgets('Share PDF is the primary completion action', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final quote = Quote(
        customer: Customer(name: 'Ravi Kumar'),
        lineItems: [
          QuoteLineItem(
            description: 'Tile labour',
            quantity: 100,
            unit: 'sq ft',
            unitRatePaise: 4000,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfPreviewScreen(quote: quote)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Sole primary CTA + secondary edit path (design.md §6).
      expect(find.widgetWithText(ElevatedButton, 'Share PDF'), findsOneWidget);
      expect(find.text('Edit quote'), findsOneWidget);
      // Meta line with quote number + total.
      expect(find.textContaining('Quote'), findsAtLeastNWidgets(1));
      // Local-only note + opt-in backup toggle.
      expect(find.textContaining('Saved on this phone'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/pdf/pdf_service.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';
import 'package:contractor_quote_poc/utils/quote_ids.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 15 — Customer and Quote Terms Domain & Verification', () {
    test('A complete quotation can be made with only client name plus line items', () async {
      final minimalQuote = Quote(
        customer: const Customer(name: 'Ravi Kumar'),
        lineItems: const [
          QuoteLineItem(
            description: 'Tile labour',
            quantity: 500,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
        ],
      );

      // Verify no blocking reason
      expect(quotePdfBlockingReason(minimalQuote), isNull);

      // Verify totals (no GST)
      final totals = calculateTotals(minimalQuote);
      expect(totals.subtotalPaise, 2_250_000);
      expect(totals.gstPaise, 0);
      expect(totals.grandTotalPaise, 2_250_000);

      // Verify default commercial terms are supplied as fallback
      expect(minimalQuote.effectiveTerms, kDefaultQuoteTerms);
      expect(minimalQuote.validityDays, 15);
      expect(minimalQuote.effectiveAdvanceText, '');

      // Verify PDF generates without errors for minimal quote
      final pdfBytes = await PdfService.generateQuotationPdf(
        quote: minimalQuote,
      );
      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, isTrue);
    });

    test('All optional commercial fields render and calculate correctly when supplied', () async {
      final quoteDate = DateTime(2026, 9, 25);
      const customTerms = [
        'Water and power supply by client.',
        'Debris disposal charged separately.',
      ];

      final commercialQuote = Quote(
        id: '12345678-1234-4234-8234-123456789abc',
        quoteNumber: 'Q-2026-A101',
        serverDisplayNumber: 'Q-2026-SRV1',
        customer: const Customer(
          name: 'Verma Ji / वर्मा जी',
          phone: '+91 98765 43210',
          address: 'Flat 402, Green Meadows, Pune',
        ),
        lineItems: const [
          QuoteLineItem(
            description: 'Wall Paint',
            quantity: 1000,
            unit: 'sq ft',
            unitRatePaise: 2000,
          ),
        ],
        gstPercent: 18,
        quoteDate: quoteDate,
        validityDays: 30,
        advancePercent: 50,
        advanceText: '50% advance before paint delivery',
        notes: 'Includes primer and 2 coats of Royale emulsion.',
        terms: customTerms,
      );

      expect(commercialQuote.displayNumber, 'Q-2026-SRV1');
      expect(commercialQuote.customer.phone, '+91 98765 43210');
      expect(commercialQuote.customer.address, 'Flat 402, Green Meadows, Pune');
      expect(commercialQuote.effectiveAdvanceText, '50% advance before paint delivery');
      expect(commercialQuote.effectiveTerms, customTerms);

      final totals = calculateTotals(commercialQuote);
      expect(totals.subtotalPaise, 2_000_000); // ₹20,000
      expect(totals.gstPaise, 360_000);       // ₹3,600 (18%)
      expect(totals.grandTotalPaise, 2_360_000); // ₹23,600

      final pdfBytes = await PdfService.generateQuotationPdf(
        quote: commercialQuote,
      );
      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('SavedQuote retains local UUID idempotency anchor and serverDisplayNumber precedence', () {
      final localId = newQuoteId();
      final localDisplay = newDisplayNumber();

      final saved = SavedQuote(
        id: localId,
        quoteNumber: localDisplay,
        serverDisplayNumber: 'Q-2026-BACKEND',
        createdAt: DateTime(2026, 9, 25),
        customerName: 'Patil Residence',
        customerPhone: '9822012345',
        customerAddress: 'Bungalow 5, Kothrud',
        validityDays: 60,
        advancePercent: 30,
        advanceText: '30% token advance',
        notes: 'Completion in 10 working days',
        terms: const ['Custom term 1'],
        gstPercent: 12,
        lineItems: const [
          QuoteLineItem(
            description: 'Tiling',
            quantity: 100,
            unit: 'sq ft',
            unitRatePaise: 5000,
          ),
        ],
      );

      // Backend number takes precedence in displayNumber getter
      expect(saved.displayNumber, 'Q-2026-BACKEND');
      expect(saved.idempotencyKey, localId);

      // JSON roundtrip
      final json = saved.toJson();
      final restored = SavedQuote.fromJson(json);

      expect(restored.id, localId);
      expect(restored.quoteNumber, localDisplay);
      expect(restored.serverDisplayNumber, 'Q-2026-BACKEND');
      expect(restored.displayNumber, 'Q-2026-BACKEND');
      expect(restored.customerAddress, 'Bungalow 5, Kothrud');
      expect(restored.advanceText, '30% token advance');
      expect(restored.validityDays, 60);
      expect(restored.gstPercent, 12);
      expect(restored.terms, ['Custom term 1']);

      final quote = restored.toQuote();
      expect(quote.id, localId);
      expect(quote.displayNumber, 'Q-2026-BACKEND');
      expect(quote.customer.address, 'Bungalow 5, Kothrud');
    });
  });

  group('Day 15 — Review Screen Progressive Disclosure UI', () {
    testWidgets('Renders customer fields and progressive disclosure accordion for more details', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: ReviewScreen(
            initialLineItems: [
              QuoteLineItem(
                description: 'Tile Labour',
                quantity: 100,
                unit: 'sq ft',
                unitRatePaise: 4000,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Customer fields are present
      expect(find.text('Client name / ग्राहक का नाम *'), findsOneWidget);
      expect(find.text('Phone / फ़ोन (optional)'), findsOneWidget);
      expect(find.text('Site / Address / कार्यस्थल (optional)'), findsOneWidget);

      // Progressive disclosure header is present
      expect(find.text('More quote details / अतिरिक्त विवरण'), findsOneWidget);
      expect(find.text('Expand'), findsOneWidget);

      // Tap to expand
      await tester.tap(find.text('Expand'));
      await tester.pumpAndSettle();

      // Expanded commercial fields are now visible
      expect(find.text('Quote Number / कोटेशन संख्या'), findsOneWidget);
      expect(find.text('Offline ID / पहचान'), findsOneWidget);
      expect(find.text('Quote Date / दिनांक'), findsOneWidget);
      expect(find.text('Validity / मान्यता (दिन)'), findsOneWidget);
      expect(find.text('GST / जीएसटी कर'), findsOneWidget);
      expect(find.text('Advance / अग्रिम भुगतान (optional)'), findsOneWidget);
      expect(find.text('Terms & Conditions / नियम व शर्तें'), findsOneWidget);

      // Toggle GST to 18%
      await tester.tap(find.text('18% GST'));
      await tester.pumpAndSettle();

      // Subtotal was ₹4,000, 18% GST is ₹720, total is ₹4,720
      expect(find.text('₹720'), findsOneWidget);
      expect(find.text('₹4,720'), findsAtLeastNWidgets(1));

      // Reset defaults button resets terms
      expect(find.text('Reset defaults / डिफ़ॉल्ट'), findsOneWidget);
      await tester.tap(find.text('Reset defaults / डिफ़ॉल्ट'));
      await tester.pumpAndSettle();
    });
  });
}

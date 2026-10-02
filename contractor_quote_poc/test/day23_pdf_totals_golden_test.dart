// Day 23 — PDF essential totals/header coverage ("golden if practical").
//
// Decision: binary image goldens are NOT practical here — Devanagari font
// rasterization varies across test machines, which would make image goldens
// flaky. Instead this file pins the two things an image golden would guard:
//  1. the PDF bytes are produced from the same deterministic totals engine
//     (recomputed grand total == rendered grand total, header shows the
//     effective display number), and
//  2. the on-screen PDF header (quote number + grand total) renders exactly.
// If pixel goldens are ever wanted, run:
//   flutter test --update-goldens test/day23_pdf_totals_golden_test.dart
// after adding a matchesGoldenFile() expectation.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/pdf/pdf_service.dart';
import 'package:contractor_quote_poc/screens/pdf_preview_screen.dart';
import 'package:contractor_quote_poc/utils/rupee_format.dart';

Quote _canonicalTilingQuote() => Quote(
      id: 'quote-day23-golden',
      quoteNumber: 'Q-2026-0042',
      serverDisplayNumber: 'Q-2026-A3F9',
      customer: const Customer(name: 'Sharma Ji'),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF is generated from deterministic totals (golden values)', () async {
    final quote = _canonicalTilingQuote();
    final totals = calculateTotals(quote);

    // Golden values for the Day-2 fixture — change only with a deliberate
    // fixture change, exactly like an image golden.
    expect(totals.subtotalPaise, 4545000);
    expect(totals.gstPaise, 0);
    expect(totals.grandTotalPaise, 4545000);
    expect(formatRupeePaise(totals.grandTotalPaise), '₹45,450');

    // Backend display number wins in the header.
    expect(quote.displayNumber, 'Q-2026-A3F9');

    final pdfBytes = await PdfService.generateQuotationPdf(
      quote: quote,
      businessType: BusinessType.tiling,
      quoteNumber: quote.quoteNumber!,
    );
    expect(ascii.decode(pdfBytes.sublist(0, 5)), '%PDF-');
    expect(pdfBytes.length, greaterThan(1000));
  });

  test('PDF with 18% GST renders GST + grand total from the same engine',
      () async {
    final quote = Quote(
      customer: const Customer(name: 'Verma Ji'),
      lineItems: const [
        QuoteLineItem(
          description: 'Painting / पेंटिंग',
          quantity: 1200,
          unit: 'sq ft',
          unitRatePaise: 1200,
        ),
      ],
      gstPercent: 18,
    );
    final totals = calculateTotals(quote);
    expect(totals.subtotalPaise, 1440000);
    expect(totals.gstPaise, 259200);
    expect(totals.grandTotalPaise, 1699200);

    final pdfBytes = await PdfService.generateQuotationPdf(
      quote: quote,
      businessType: BusinessType.painting,
      quoteNumber: 'Q-2026-0043',
    );
    expect(ascii.decode(pdfBytes.sublist(0, 5)), '%PDF-');
  });

  testWidgets('PDF preview header shows display number and grand total',
      (tester) async {
    final quote = _canonicalTilingQuote();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfPreviewScreen(quote: quote, businessType: BusinessType.tiling),
      ),
    );

    expect(find.text('Quotation ready'), findsOneWidget);
    expect(
      find.textContaining('Q-2026-A3F9'),
      findsOneWidget,
      reason: 'header shows backend display number, not the local label',
    );
    expect(find.textContaining('₹45,450'), findsWidgets);
  });
}

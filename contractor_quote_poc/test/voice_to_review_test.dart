import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/parser/demo_transcripts.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';

void main() {
  const parser = TranscriptParser();

  // ── 1. Tiling Demo Flow ───────────────────────────────────────────────────

  testWidgets('Tiling demo phrase populates ReviewScreen with 2 items and ₹45,450 subtotal',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final result = parser.parse(kTilingDemoTranscript);
    expect(result.warnings, isEmpty);
    expect(result.items, hasLength(2));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          trade: Trade.tiling,
          originalTranscript: kTilingDemoTranscript,
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );

    // Verify Trade chip in app bar
    expect(find.text('🪣 Tiling'), findsOneWidget);

    // Verify Spoken Note card is present and displays the transcript
    expect(find.text('Spoken Note / मूल आवाज़'), findsOneWidget);
    expect(find.text('“$kTilingDemoTranscript”'), findsOneWidget);

    // Verify items are rendered
    expect(find.text('Tile Labour / टाइल मजदूरी'), findsOneWidget);
    expect(find.text('Skirting / स्कर्टिंग'), findsOneWidget);

    // Verify subtotal ₹45,450 (both in summary and bottom bar)
    expect(find.text('₹45,450'), findsNWidgets(2));

    // No warning banner should be displayed
    expect(find.text('Please Review / ध्यान दें'), findsNothing);
  });

  // ── 2. Painting Demo Flow ─────────────────────────────────────────────────

  testWidgets('Painting demo phrase populates ReviewScreen with 2 items and ₹36,000 subtotal',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final result = parser.parse(kPaintingDemoTranscript);
    expect(result.warnings, isEmpty);
    expect(result.items, hasLength(2));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          trade: Trade.painting,
          originalTranscript: kPaintingDemoTranscript,
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );

    // Verify Trade chip in app bar
    expect(find.text('🖌️ Painting'), findsOneWidget);

    // Verify Spoken Note card
    expect(find.text('Spoken Note / मूल आवाज़'), findsOneWidget);
    expect(find.text('“$kPaintingDemoTranscript”'), findsOneWidget);

    // Verify items
    expect(find.text('Wall Putty / वॉल पुट्टी'), findsOneWidget);
    expect(find.text('Painting / पेंटिंग'), findsOneWidget);

    // Verify subtotal ₹36,000
    expect(find.text('₹36,000'), findsNWidgets(2));
  });

  // ── 3. Unrecognized Transcript & Warning Flow ─────────────────────────────

  testWidgets('Unrecognized phrase shows warning banner and empty-state guidance on ReviewScreen',
      (WidgetTester tester) async {
    const rawText = 'Unknown work 500 square feet 25 rupees';
    final result = parser.parse(rawText);

    expect(result.items, isEmpty);
    expect(result.hasWarnings, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          trade: Trade.tiling,
          originalTranscript: rawText,
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );

    // Spoken note is preserved
    expect(find.text('Spoken Note / मूल आवाज़'), findsOneWidget);
    expect(find.text('“$rawText”'), findsOneWidget);

    // Warning banner is displayed
    expect(find.text('Please Review / ध्यान दें'), findsOneWidget);
    expect(find.textContaining('No recognized items'), findsOneWidget);

    // Empty items hint tailored for voice
    expect(find.text('No items auto-detected from voice'), findsOneWidget);

    // Dismissing warning banner works
    await tester.tap(find.byTooltip('Dismiss warning'));
    await tester.pump();
    expect(find.text('Please Review / ध्यान दें'), findsNothing);
  });

  // ── 4. Transcript Expansion Toggle ────────────────────────────────────────

  testWidgets('Tapping Spoken Note card collapses and expands transcript body',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewScreen(
          trade: Trade.tiling,
          originalTranscript: kTilingDemoTranscript,
          initialLineItems: [],
        ),
      ),
    );

    expect(find.text('“$kTilingDemoTranscript”'), findsOneWidget);

    // Tap to collapse
    await tester.tap(find.text('Spoken Note / मूल आवाज़'));
    await tester.pump();
    expect(find.text('“$kTilingDemoTranscript”'), findsNothing);

    // Tap again to re-expand
    await tester.tap(find.text('Spoken Note / मूल आवाज़'));
    await tester.pump();
    expect(find.text('“$kTilingDemoTranscript”'), findsOneWidget);
  });

  // ── 5. Quote Model Preserves Original Transcript ──────────────────────────

  test('Quote model preserves originalTranscript and computes totals correctly', () {
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
      originalTranscript: kTilingDemoTranscript,
    );

    expect(quote.originalTranscript, equals(kTilingDemoTranscript));
    expect(quote.customer.name, equals('Ramesh Patel'));
    final totals = calculateTotals(quote);
    expect(totals.subtotalPaise, equals(850 * 4500));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/templates/template_loader.dart';

// Demo transcripts previously in lib/parser/demo_transcripts.dart
// (file deleted; inlined here so tests don't depend on lib/).
const kTilingDemoTranscript =
    'Sharma ji ka flat, 850 square foot tiles labour, 45 rupaye per foot, skirting 120 running foot, 60 rupaye per foot.';
const kPaintingDemoTranscript =
    'Verma ji ka flat, 1200 square foot wall putty, 18 rupaye per foot, painting 1200 square foot, 12 rupaye per foot.';

void main() {
  const parser = TranscriptParser();

  // ── 1. Tiling Demo Flow ───────────────────────────────────────────────────

  testWidgets('Tiling demo phrase populates ReviewScreen with 2 items and ₹45,450 subtotal',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // New contract: parse against the user's seeded service list.
    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
    final services =
        await ServiceItemRepository.seedFromTemplate(BusinessType.tiling);
    final rateMap =
        await ServiceItemRepository.getRateMap(BusinessType.tiling);
    final result = parser.parse(
      kTilingDemoTranscript,
      services: services,
      savedRates: rateMap,
    );
    expect(result.warnings, isEmpty);
    expect(result.items, hasLength(2));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          businessType: BusinessType.tiling,
          originalTranscript: kTilingDemoTranscript,
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );

    // Verify BusinessType chip in app bar (generic metadata label)
    expect(find.text('टाइलिंग'), findsOneWidget);

    // Verify Spoken Note card is present and displays the transcript
    expect(find.text('बोली गई बात'), findsOneWidget);
    expect(find.text('“$kTilingDemoTranscript”'), findsOneWidget);

    // Verify items are rendered (user's service names from the template)
    expect(find.text('Tile fixing'), findsOneWidget);
    expect(find.text('Skirting tiles'), findsOneWidget);

    // Verify subtotal ₹45,450 (both in summary and bottom bar)
    expect(find.text('₹45,450'), findsNWidgets(2));

    // No warning banner should be displayed
    expect(find.text('ध्यान दें'), findsNothing);
  });

  // ── 2. Painting Demo Flow ─────────────────────────────────────────────────

  testWidgets('Painting demo phrase populates ReviewScreen with 2 items and ₹36,000 subtotal',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
    final services =
        await ServiceItemRepository.seedFromTemplate(BusinessType.painting);
    final rateMap =
        await ServiceItemRepository.getRateMap(BusinessType.painting);
    final result = parser.parse(
      kPaintingDemoTranscript,
      services: services,
      savedRates: rateMap,
    );
    expect(result.warnings, isEmpty);
    expect(result.items, hasLength(2));

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          businessType: BusinessType.painting,
          originalTranscript: kPaintingDemoTranscript,
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );

    // Verify BusinessType chip in app bar (generic metadata label)
    expect(find.text('पेंटिंग'), findsOneWidget);

    // Verify Spoken Note card
    expect(find.text('बोली गई बात'), findsOneWidget);
    expect(find.text('“$kPaintingDemoTranscript”'), findsOneWidget);

    // Verify items (user's service names from the template)
    expect(find.text('Wall putty'), findsOneWidget);
    expect(find.text('Interior wall painting'), findsOneWidget);

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
          businessType: BusinessType.tiling,
          originalTranscript: rawText,
          parsingWarnings: result.warnings,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );

    // Spoken note is preserved
    expect(find.text('बोली गई बात'), findsOneWidget);
    expect(find.text('“$rawText”'), findsOneWidget);

    // Warning banner is displayed
    expect(find.text('ध्यान दें'), findsOneWidget);
    expect(find.textContaining('No services in your list match'), findsOneWidget);

    // Empty items hint tailored for voice
    expect(find.text('आवाज़ से कोई काम नहीं मिला'), findsOneWidget);

    // Dismissing warning banner works
    await tester.tap(find.byTooltip('हटाएं'));
    await tester.pump();
    expect(find.text('ध्यान दें'), findsNothing);
  });

  // ── 4. Transcript Expansion Toggle ────────────────────────────────────────

  testWidgets('Tapping Spoken Note card collapses and expands transcript body',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewScreen(
          businessType: BusinessType.tiling,
          originalTranscript: kTilingDemoTranscript,
          initialLineItems: [],
        ),
      ),
    );

    expect(find.text('“$kTilingDemoTranscript”'), findsOneWidget);

    // Tap to collapse
    await tester.tap(find.text('बोली गई बात'));
    await tester.pump();
    expect(find.text('“$kTilingDemoTranscript”'), findsNothing);

    // Tap again to re-expand
    await tester.tap(find.text('बोली गई बात'));
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';

/// Day 14 Verify: a contractor can repair all intentionally wrong values in a
/// five-line quote in under two minutes, with totals changing correctly after
/// each edit.
///
/// This widget test simulates that repair run: four lines carry wrong
/// qty/rate values and one line is low-confidence (blocks PDF). Each fix is
/// done through the bottom-sheet form (Edit / Fix now → Save changes) and the
/// on-screen total is asserted after every step. A human doing the same five
/// taps + number corrections takes well under two minutes; the test proves no
/// edit is lost and every edit immediately recalculates via the Day 5 engine.
void main() {
  testWidgets('Day 14 five-line repair: totals update after each fix',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          trade: Trade.tiling,
          initialLineItems: const [
            // Wrong qty: 10 instead of 100 → ₹450 instead of ₹4,500.
            QuoteLineItem(
              description: 'Tile Labour',
              quantity: 10,
              unit: 'sq ft',
              unitRatePaise: 4500,
            ),
            // Wrong rate: ₹6 instead of ₹60 → ₹300 instead of ₹3,000.
            QuoteLineItem(
              description: 'Skirting',
              quantity: 50,
              unit: 'rft',
              unitRatePaise: 600,
            ),
            // Wrong qty: 20 instead of 200 → ₹600 instead of ₹6,000.
            QuoteLineItem(
              description: 'Waterproofing',
              quantity: 20,
              unit: 'sq ft',
              unitRatePaise: 3000,
            ),
            // Wrong rate: ₹8 instead of ₹18 → ₹2,400 instead of ₹5,400.
            QuoteLineItem(
              description: 'Wall Putty',
              quantity: 300,
              unit: 'sq ft',
              unitRatePaise: 800,
            ),
            // Low-confidence line blocks PDF until fixed/acknowledged.
            QuoteLineItem(
              description: 'Painting',
              quantity: 300,
              unit: 'sq ft',
              unitRatePaise: 1200,
              confidence: 0.5,
              uncertaintyNote: 'Quantity needs checking',
              requiresReview: true,
            ),
          ],
        ),
      ),
    );

    // Initial wrong total: 450+300+600+2400+3600 = ₹7,350.
    expect(find.text('₹7,350'), findsNWidgets(2));
    expect(find.text('Needs attention (1)'), findsOneWidget);
    expect(find.text('Fix now'), findsOneWidget);

    // ── Fix 1: Tile Labour qty 10 → 100. New total ₹11,400. ──
    await tester.tap(find.text('Edit').at(0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '100');
    // Sheet shows live read-only amount preview (Day 5 engine).
    expect(find.textContaining('Amount / राशि'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('₹11,400'), findsNWidgets(2));

    // ── Fix 2: Skirting rate 6 → 60. New total ₹14,100. ──
    await tester.ensureVisible(find.text('Edit').at(1));
    await tester.tap(find.text('Edit').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(3), '60');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('₹14,100'), findsNWidgets(2));

    // ── Fix 3: Waterproofing qty 20 → 200. New total ₹19,500. ──
    await tester.ensureVisible(find.text('Edit').at(2));
    await tester.tap(find.text('Edit').at(2));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '200');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('₹19,500'), findsNWidgets(2));

    // ── Fix 4: Wall Putty rate 8 → 18. New total ₹22,500. ──
    await tester.ensureVisible(find.text('Edit').at(3));
    await tester.tap(find.text('Edit').at(3));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(3), '18');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('₹22,500'), findsNWidgets(2));

    // ── Fix 5: low-confidence Painting via "Fix now" → Save changes. ──
    await tester.ensureVisible(find.text('Fix now'));
    await tester.tap(find.text('Fix now'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Item / मद बदलें'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // All resolved: banner gone, total holds, PDF no longer blocked.
    // (Fix-now via Edit marks the item resolved: requiresReview=false, so no
    // "Checked" chip remains — the attention banner disappearing is the signal.)
    expect(find.text('Needs attention (1)'), findsNothing);
    expect(find.text('Fix now'), findsNothing);
    expect(find.text('₹22,500'), findsNWidgets(2));
  });

  test('Day 14 five-line repair math matches Day 5 engine', () {
    final fixed = Quote(
      customer: const Customer(name: 'Repair check'),
      lineItems: const [
        QuoteLineItem(
            description: 'Tile Labour', quantity: 100, unit: 'sq ft', unitRatePaise: 4500),
        QuoteLineItem(
            description: 'Skirting', quantity: 50, unit: 'rft', unitRatePaise: 6000),
        QuoteLineItem(
            description: 'Waterproofing', quantity: 200, unit: 'sq ft', unitRatePaise: 3000),
        QuoteLineItem(
            description: 'Wall Putty', quantity: 300, unit: 'sq ft', unitRatePaise: 1800),
        QuoteLineItem(
            description: 'Painting',
            quantity: 300,
            unit: 'sq ft',
            unitRatePaise: 1200,
            requiresReview: true,
            acknowledged: true),
      ],
    );
    final totals = calculateTotals(fixed);
    expect(totals.lineAmountsPaise, [450000, 300000, 600000, 540000, 360000]);
    expect(totals.subtotalPaise, 2250000);
    expect(quotePdfBlockingReason(fixed), isNull);
  });
}

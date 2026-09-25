import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/extraction_models.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';

void main() {
  const customer = Customer(name: 'Ravi Kumar');

  test('calculates a line amount in paise', () {
    const item = QuoteLineItem(
      description: 'Tile labour',
      quantity: 850,
      unit: 'sq ft',
      unitRatePaise: 4500,
    );

    expect(calculateAmount(item), 3_825_000);
  });

  test(
    'calculates the Day 2 fixture subtotal without floating point totals',
    () {
      final quote = Quote(
        customer: customer,
        lineItems: const [
          QuoteLineItem(
            description: 'Tile labour',
            quantity: 850,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
          QuoteLineItem(
            description: 'Skirting',
            quantity: 120,
            unit: 'rft',
            unitRatePaise: 6000,
          ),
        ],
      );

      final totals = calculateTotals(quote);

      expect(totals.lineAmountsPaise, [3_825_000, 720_000]);
      expect(totals.subtotalPaise, 4_545_000);
      expect(totals.gstPaise, 0);
      expect(totals.grandTotalPaise, 4_545_000);
    },
  );

  test('adds optional GST using whole-paise rounding', () {
    final quote = Quote(
      customer: customer,
      lineItems: const [
        QuoteLineItem(
          description: 'Small repair',
          quantity: 1,
          unit: 'job',
          unitRatePaise: 101,
        ),
      ],
      gstPercent: 18,
    );

    final totals = calculateTotals(quote);

    expect(totals.subtotalPaise, 101);
    expect(totals.gstPaise, 18);
    expect(totals.grandTotalPaise, 119);
  });

  test('blocks PDF when a low-confidence item is not acknowledged', () {
    const item = QuoteLineItem(
      description: 'Wall paint',
      quantity: 100,
      unit: 'sq ft',
      unitRatePaise: 1500,
      confidence: 0.55,
      uncertaintyNote: 'Quantity needs checking',
      requiresReview: true,
    );
    final quote = Quote(customer: customer, lineItems: const [item]);

    expect(quotePdfBlockingReason(quote), contains('Wall paint'));

    final checkedQuote = Quote(
      customer: customer,
      lineItems: const [
        QuoteLineItem(
          description: 'Wall paint',
          quantity: 100,
          unit: 'sq ft',
          unitRatePaise: 1500,
          confidence: 0.55,
          uncertaintyNote: 'Quantity needs checking',
          requiresReview: true,
          acknowledged: true,
        ),
      ],
    );

    expect(quotePdfBlockingReason(checkedQuote), isNull);
  });

  test('converts uncertain extraction results into reviewable line items', () {
    const extracted = ExtractedItem(
      catalogItemId: 'wall_putty',
      description: 'Wall Putty',
      quantity: 1200,
      unit: 'sq ft',
      unitRatePaise: 1800,
      confidence: 0.5,
      uncertaintyNote: 'Check quantity',
    );
    const unknown = ExplicitUnknown(
      text: 'sofa repair 1 piece',
      reason: 'Not in trade catalog',
    );

    final extractedLine = extracted.toQuoteLineItem();
    final unknownLine = unknown.toQuoteLineItem();

    expect(extractedLine.requiresReview, isTrue);
    expect(extractedLine.confidence, 0.5);
    expect(unknownLine.isUnknown, isTrue);
    expect(unknownLine.requiresReview, isTrue);
    expect(unknownLine.quantity, 0);
    expect(unknownLine.unitRatePaise, 0);
  });

  test('saved quotes retain review uncertainty state', () {
    final saved = SavedQuote(
      id: 'quote-review-state',
      quoteNumber: 'Q-1',
      createdAt: DateTime(2026, 1, 1),
      customerName: 'Client',
      reviewWarnings: const ['Check the note'],
      lineItems: const [
        QuoteLineItem(
          description: 'Wall paint',
          quantity: 10,
          unit: 'sq ft',
          unitRatePaise: 1000,
          confidence: 0.6,
          uncertaintyNote: 'Check quantity',
          isUnknown: true,
          requiresReview: true,
        ),
      ],
    );

    final restored = SavedQuote.fromJson(saved.toJson());

    expect(restored.reviewWarnings, ['Check the note']);
    expect(restored.reviewWarningsAcknowledged, isFalse);
    expect(restored.lineItems.single.isUnknown, isTrue);
    expect(restored.lineItems.single.requiresReview, isTrue);
    expect(restored.lineItems.single.acknowledged, isFalse);
  });

  testWidgets('review screen displays the Day 2 fixture subtotal', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReviewScreen()));

    expect(find.text('₹45,450'), findsOneWidget);
  });

  testWidgets('Day 14 blocks PDF until uncertain item is checked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          initialLineItems: const [
            QuoteLineItem(
              description: 'Wall paint',
              quantity: 100,
              unit: 'sq ft',
              unitRatePaise: 1500,
              confidence: 0.5,
              uncertaintyNote: 'Quantity needs checking',
              requiresReview: true,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Needs attention (1)'), findsOneWidget);
    await tester.tap(find.text('Generate PDF / PDF बनाएं'));
    await tester.pump();
    expect(find.text('PDF Preview / पूर्वावलोकन'), findsNothing);
    expect(
      find.textContaining('Please check "Wall paint"'),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('Mark as checked / जांच ली'));
    await tester.pump();
    expect(find.text('Needs attention (1)'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Checked / जांच ली गई'), findsOneWidget);
  });

  testWidgets(
    'Day 14 review supports edit, duplicate, reorder, add, and confirmed delete',
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
              QuoteLineItem(
                description: 'A',
                quantity: 2,
                unit: 'job',
                unitRatePaise: 10000,
              ),
              QuoteLineItem(
                description: 'B',
                quantity: 3,
                unit: 'job',
                unitRatePaise: 5000,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Item 1 / मद 1'), findsOneWidget);
      expect(find.text('₹200'), findsOneWidget);
      expect(find.text('Duplicate'), findsNWidgets(2));

      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit Item / मद बदलें'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '4');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('₹550'), findsNWidgets(2));

      await tester.tap(find.text('Duplicate').first);
      await tester.pumpAndSettle();
      expect(find.text('Item 3 / मद 3'), findsOneWidget);
      expect(find.text('A'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Move item 3 up'));
      await tester.pumpAndSettle();
      final bTop = tester.getTopLeft(find.text('B')).dy;
      final duplicateTop = tester.getTopLeft(find.text('A').last).dy;
      expect(bTop, lessThan(duplicateTop));

      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      final formFields = find.byType(TextFormField);
      await tester.enterText(formFields.at(0), 'C');
      await tester.enterText(formFields.at(1), '1');
      await tester.enterText(formFields.at(2), 'job');
      await tester.enterText(formFields.at(3), '25');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('C'), findsOneWidget);
      expect(find.text('₹975'), findsNWidgets(2));

      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete item / मद हटाएं?'), findsOneWidget);
      await tester.tap(find.text('Delete / हटाएं'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
    },
  );
}

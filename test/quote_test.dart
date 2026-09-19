import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';

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

  testWidgets('review screen displays the Day 2 fixture subtotal', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReviewScreen()));

    expect(find.text('₹45,450'), findsOneWidget);
  });
}

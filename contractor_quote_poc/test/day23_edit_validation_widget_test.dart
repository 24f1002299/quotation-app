// Day 23 — Widget tests for line-item editing and validation.
//
// Proves the review screen (the trust screen) recalculates immediately on
// edit and names the exact item/field that blocks PDF generation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpReview(
  WidgetTester tester, {
  required List<QuoteLineItem> items,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: ReviewScreen(
        businessType: BusinessType.tiling,
        initialLineItems: items,
      ),
    ),
  );
}

Future<void> _tapGenerate(WidgetTester tester) async {
  final btn = find.text('Generate PDF / PDF बनाएं');
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pump();
}

void main() {
  testWidgets('editing quantity recalculates the total immediately',
      (tester) async {
    _usePhoneScreen(tester);
    await _pumpReview(tester, items: const [
      QuoteLineItem(
        description: 'Floor tiles',
        quantity: 2,
        unit: 'job',
        unitRatePaise: 10000, // ₹100
      ),
    ]);

    expect(find.text('₹200'), findsWidgets);

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '5');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('₹500'), findsWidgets);
  });

  testWidgets('zero quantity blocks PDF and names the item', (tester) async {
    _usePhoneScreen(tester);
    await _pumpReview(tester, items: const [
      QuoteLineItem(
        description: 'Wall paint',
        quantity: 0,
        unit: 'sq ft',
        unitRatePaise: 1500,
      ),
    ]);

    await _tapGenerate(tester);
    expect(find.text('PDF Preview / पूर्वावलोकन'), findsNothing);
    expect(
      find.textContaining('quantity greater than 0'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('Wall paint'), findsAtLeastNWidgets(1));
  });

  testWidgets('missing rate blocks PDF with an Add-rate action', (tester) async {
    _usePhoneScreen(tester);
    await _pumpReview(tester, items: const [
      QuoteLineItem(
        description: 'Grouting',
        quantity: 10,
        unit: 'sq ft',
        unitRatePaise: 0,
      ),
    ]);

    await _tapGenerate(tester);
    expect(find.text('PDF Preview / पूर्वावलोकन'), findsNothing);
    expect(find.textContaining('Add a rate'), findsAtLeastNWidgets(1));
  });

  testWidgets('unknown item blocks PDF until acknowledged', (tester) async {
    _usePhoneScreen(tester);
    await _pumpReview(tester, items: const [
      QuoteLineItem(
        description: 'Sofa repair',
        quantity: 0,
        unit: 'item',
        unitRatePaise: 0,
        isUnknown: true,
        requiresReview: true,
        uncertaintyNote: 'Not in businessType catalog',
      ),
    ]);

    expect(find.text('Needs attention (1)'), findsOneWidget);
    await _tapGenerate(tester);
    expect(find.text('PDF Preview / पूर्वावलोकन'), findsNothing);
    expect(find.textContaining('Unknown item'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('I checked this / मैंने जांच ली'));
    await tester.pump();
    expect(find.text('Needs attention (1)'), findsNothing);
  });
}

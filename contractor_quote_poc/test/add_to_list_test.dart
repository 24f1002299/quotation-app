import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';

/// Add-to-my-list: a suggested (unlisted) line item can be saved to the
/// user's service list in one tap, and the row links to the saved service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('suggested item offers Add to my list and saves the service',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewScreen(
          businessType: BusinessType.pestControl,
          initialLineItems: [
            QuoteLineItem(
              description: 'Balcony netting',
              quantity: 1,
              unit: 'visit',
              unitRatePaise: 150000,
              isUnknown: true,
              requiresReview: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to my list'), findsOneWidget);

    await tester.tap(find.text('Add to my list'));
    await tester.pumpAndSettle();

    final services = await ServiceItemRepository.getActiveForBusinessType(
      BusinessType.pestControl,
    );
    expect(
      services.any((s) => s.name == 'Balcony netting'),
      isTrue,
    );
    expect(find.text('Saved to my services / मेरी सेवाओं में सहेजा गया'),
        findsOneWidget);
    // Row is now linked: the action disappears after saving.
    expect(find.text('Add to my list'), findsNothing);
  });

  testWidgets('listed items show no Add to my list action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewScreen(
          businessType: BusinessType.tiling,
          initialLineItems: [
            QuoteLineItem(
              description: 'Tile fixing',
              quantity: 100,
              unit: 'sq ft',
              unitRatePaise: 4500,
              serviceItemId: 'svc_tile',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to my list'), findsNothing);
  });
}

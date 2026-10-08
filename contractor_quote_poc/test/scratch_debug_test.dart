import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/screens/review_screen.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/templates/template_loader.dart';

void main() {
  testWidgets('seed+pump with items', (t) async {
    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
    final services =
        await ServiceItemRepository.seedFromTemplate(BusinessType.tiling);
    debugPrint('A seeded ${services.length}');
    await t.pumpWidget(
      const MaterialApp(
        home: ReviewScreen(
          businessType: BusinessType.tiling,
          initialLineItems: [
            QuoteLineItem(
              description: 'Tile fixing',
              quantity: 850,
              unit: 'sq ft',
              unitRatePaise: 4500,
            ),
          ],
        ),
      ),
    );
    debugPrint('A pumped');
    expect(find.text('Tile fixing'), findsOneWidget);
    debugPrint('A done');
  });

  testWidgets('load after seed+pump', (t) async {
    debugPrint('B load');
    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
    final tpl = await TemplateLoader.load(BusinessType.painting);
    debugPrint('B loaded ${tpl.services.length}');
    expect(tpl.services, isNotEmpty);
  });
}

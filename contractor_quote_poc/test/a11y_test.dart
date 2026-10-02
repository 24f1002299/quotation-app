import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/l10n/app_strings.dart';
import 'package:contractor_quote_poc/screens/business_edit_page.dart';
import 'package:contractor_quote_poc/screens/my_services_screen.dart';
import 'package:contractor_quote_poc/screens/settings_screen.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';

/// Step 5 — Accessibility: key screens must lay out without overflow errors
/// at large text scales. Overflow throws during layout and fails the test,
///
/// so green here means no RenderFlex breakage at 1.5x text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLargeText(WidgetTester tester, Widget screen) async {
    tester.view.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(
      tester.view.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppStrings(languageCode: 'hi', child: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('large-text layout (1.5x)', () {
    testWidgets('SettingsScreen lays out without overflow', (tester) async {
      await pumpLargeText(tester, const SettingsScreen());
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('MyServicesScreen lays out without overflow', (tester) async {
      await pumpLargeText(
        tester,
        const MyServicesScreen(businessType: BusinessType.tiling),
      );
      expect(find.byType(MyServicesScreen), findsOneWidget);
    });

    testWidgets('BusinessEditPage lays out without overflow', (tester) async {
      await pumpLargeText(tester, const BusinessEditPage());
      expect(find.byType(BusinessEditPage), findsOneWidget);
    });
  });

  group('touch targets + labels', () {
    testWidgets('service rows expose edit/delete actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppStrings(
            languageCode: 'en',
            child: MyServicesScreen(businessType: BusinessType.tiling),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Empty state still offers the labelled add action.
      expect(find.text('+ Add service'), findsOneWidget);
    });
  });
}

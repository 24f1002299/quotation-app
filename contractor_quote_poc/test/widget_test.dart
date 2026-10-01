import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contractor_quote_poc/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'app_language_v1': 'hi',
      'app_language_chosen_v1': true,
    });
  });

  testWidgets('App renders HomeScreen smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ContractorQuoteApp());
    // NB: no pumpAndSettle — the hero mic pulse animation never settles.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // Phase 2 voice-first home: hero mic hint in Hindi (one language).
    expect(find.text('बोलने के लिए दबाएं'), findsOneWidget);
  });
}

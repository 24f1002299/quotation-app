import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contractor_quote_poc/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders HomeScreen smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ContractorQuoteApp());
    await tester.pumpAndSettle();
    // Home screen shows the Hindi greeting.
    expect(find.text('नमस्ते 👷'), findsOneWidget);
  });
}

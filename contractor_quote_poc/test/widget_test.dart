import 'package:flutter_test/flutter_test.dart';
import 'package:contractor_quote_poc/main.dart';

void main() {
  testWidgets('App renders HomeScreen smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ContractorQuoteApp());
    // Home screen shows the Hindi greeting.
    expect(find.text('नमस्ते 👷'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/new_quote_screen.dart';
import 'screens/review_screen.dart';
import 'screens/quote_history_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait — typical phone usage for a contractor app.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ContractorQuoteApp());
}

class ContractorQuoteApp extends StatelessWidget {
  const ContractorQuoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contractor Quote',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/new-quote': (_) => const NewQuoteScreen(),
        '/review': (_) => const ReviewScreen(),
        '/history': (_) => const QuoteHistoryScreen(),
      },
    );
  }
}

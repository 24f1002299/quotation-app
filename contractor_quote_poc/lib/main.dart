import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_strings.dart';
import 'screens/app_shell.dart';
import 'screens/home_screen.dart';
import 'screens/language_picker_screen.dart';
import 'screens/new_quote_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/privacy_notice_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/quote_history_screen.dart';
import 'screens/review_screen.dart';
import 'screens/sign_in_screen.dart';
import 'storage/app_preferences.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait — typical phone usage for a contractor app.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ContractorQuoteApp());
}

class ContractorQuoteApp extends StatefulWidget {
  const ContractorQuoteApp({super.key});

  @override
  State<ContractorQuoteApp> createState() => _ContractorQuoteAppState();
}

class _ContractorQuoteAppState extends State<ContractorQuoteApp> {
  String _language = 'hi';
  bool? _languageChosen;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    appLanguage.addListener(_onAppLanguage);
    _bootstrap();
  }

  @override
  void dispose() {
    appLanguage.removeListener(_onAppLanguage);
    super.dispose();
  }

  void _onAppLanguage() {
    final code = appLanguage.value;
    if (code == _language) return;
    setState(() => _language = code);
    AppPreferences.setLanguage(code);
  }

  Future<void> _bootstrap() async {
    final lang = await AppPreferences.getLanguage();
    final chosen = await AppPreferences.hasChosenLanguage();
    final code = (lang == 'en' || lang == 'hi' || lang == 'mr') ? lang : 'hi';
    appLanguage.value = code;
    if (!mounted) return;
    setState(() {
      _language = code;
      _languageChosen = chosen;
      _loading = false;
    });
  }

  void _onLanguageChanged(String code) {
    appLanguage.value = code;
    setState(() {
      _language = code;
      _languageChosen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppStrings(
      languageCode: _language,
      child: MaterialApp(
        title: 'Contractor Quote',
        debugShowCheckedModeBanner: false,
        theme: buildLightAppTheme(),
        home: _loading
            ? const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              )
            : (_languageChosen == true
                ? AppShell(
                    languageCode: _language,
                    onLanguageChanged: _onLanguageChanged,
                  )
                : LanguagePickerScreen(onChosen: _onLanguageChanged)),
        routes: {
          '/shell': (_) => AppStrings(
                languageCode: _language,
                child: AppShell(
                  languageCode: _language,
                  onLanguageChanged: _onLanguageChanged,
                ),
              ),
          '/language': (_) =>
              LanguagePickerScreen(onChosen: _onLanguageChanged),
          '/onboarding': (_) => const OnboardingScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/privacy': (_) => const PrivacyNoticeScreen(),
          '/new-quote': (_) => const NewQuoteScreen(),
          '/review': (_) => const ReviewScreen(),
          '/history': (_) => const QuoteHistoryScreen(),
          '/sign-in': (_) => const SignInScreen(),
          // Legacy home route (pre-shell deep links).
          '/home-legacy': (_) => const HomeScreen(),
        },
      ),
    );
  }
}

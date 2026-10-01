import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/main.dart';
import 'package:contractor_quote_poc/screens/sign_in_screen.dart';
import 'package:contractor_quote_poc/storage/app_preferences.dart';
import 'package:contractor_quote_poc/storage/auth_repository.dart';
import 'package:contractor_quote_poc/storage/quote_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 19 — Onboarding and Home', () {
    test('Hindi is the default language, incl. hi/mr locales', () {
      expect(AppPreferences.defaultLanguageForLocale('hi_IN'), 'hi');
      expect(AppPreferences.defaultLanguageForLocale('mr_IN'), 'hi');
      expect(AppPreferences.defaultLanguageForLocale('en_IN'), 'hi');
      expect(AppPreferences.labelFor('hi'), 'हिंदी');
      expect(AppPreferences.labelFor('mr'), 'मराठी');
    });

    test('tutorial flag persists once dismissed', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppPreferences.hasSeenTutorial(), isFalse);
      await AppPreferences.setTutorialSeen();
      expect(await AppPreferences.hasSeenTutorial(), isTrue);
    });

    test('language preference persists', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppPreferences.getLanguage(), 'hi');
      await AppPreferences.setLanguage('mr');
      expect(await AppPreferences.getLanguage(), 'mr');
    });

    test('Indian phone validation + E164 normalization', () {
      expect(AuthRepository.isValidIndianPhone('98765 43210'), isTrue);
      expect(AuthRepository.isValidIndianPhone('+91 9876543210'), isTrue);
      expect(AuthRepository.isValidIndianPhone('12345'), isFalse);
      expect(AuthRepository.isValidIndianPhone(''), isFalse);
      expect(
        AuthRepository.normalizeToE164('98765 43210'),
        '+919876543210',
      );
    });

    test('drafts survive a simulated restart (same local store)', () async {
      SharedPreferences.setMockInitialValues({});
      await QuoteRepository.clearAll();
      final before = await QuoteRepository.getQuotes();
      expect(before, isNotEmpty); // seeded demo drafts on fresh install
      // Simulate restart: read again from the same SharedPreferences store.
      final after = await QuoteRepository.getQuotes();
      expect(after.length, before.length);
      expect(after.first.id, before.first.id);
    });

    testWidgets('fresh tester reaches recording CTA from Home', (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_language_v1': 'hi',
        'app_language_chosen_v1': true,
      });
      await tester.pumpWidget(const ContractorQuoteApp());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Phase 2 voice-first home: hero mic + one-language hint.
      expect(find.text('बोलने के लिए दबाएं'), findsOneWidget);
      // Inline trade chips (one language each).
      expect(find.text('टाइल्स'), findsOneWidget);
      expect(find.text('पेंटिंग'), findsOneWidget);
      // Drafts section appears only when drafts exist (seeded demo drafts).
      expect(find.textContaining('ड्राफ्ट'), findsAtLeastNWidgets(1));
    });

    testWidgets('sign-in screen renders bilingual form', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: SignInScreen()),
      );
      await tester.pump();
      expect(find.text('Mobile number / मोबाइल नंबर *'), findsOneWidget);
      expect(find.text('Send OTP / OTP भेजें'), findsOneWidget);
    });
  });
}

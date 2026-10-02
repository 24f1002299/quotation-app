import 'package:flutter_test/flutter_test.dart';

import 'package:contractor_quote_poc/l10n/app_strings.dart';

/// Step 5 — Localization completeness: every English reference key exists in
/// Hindi and Marathi, so no screen can fall back to a blank or wrong-language
/// label. English is the reference table (see AppStrings.missingKeys).
void main() {
  group('l10n coverage', () {
    test('Hindi covers every English key', () {
      expect(AppStrings.missingKeys('hi'), isEmpty);
    });

    test('Marathi covers every English key', () {
      expect(AppStrings.missingKeys('mr'), isEmpty);
    });

    test('unknown language falls back to Hindi, unknown key echoes', () {
      expect(AppStrings.text('xx', 'home'), equals(AppStrings.text('hi', 'home')));
      expect(AppStrings.text('hi', 'no_such_key_xyz'), equals('no_such_key_xyz'));
    });

    test('settings rows are translated in all three languages', () {
      for (final key in [
        'sign_in',
        'sign_out',
        'privacy_notice',
        'delete_my_data',
        'pdf_backup',
        'diagnostics',
      ]) {
        for (final lang in ['en', 'hi', 'mr']) {
          final value = AppStrings.text(lang, key);
          expect(value, isNotEmpty);
          expect(value, isNot(equals(key)));
        }
      }
    });
  });
}

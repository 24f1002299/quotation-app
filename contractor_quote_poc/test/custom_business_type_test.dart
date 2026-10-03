import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/business_profile.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';

/// Free-text business type: users whose trade has no bundled template
/// (e.g. "Event Planning") work from scratch, keep their own words on
/// quotes, and sync as a free-form slug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('custom business type', () {
    test('labels prefer the custom name for Other', () {
      expect(
        businessTypeLabel(BusinessType.other, 'Event Planning', 'en'),
        equals('Event Planning'),
      );
      expect(
        businessTypeLabel(BusinessType.tiling, 'ignored', 'en'),
        equals('Tiling'),
      );
      expect(
        quoteBusinessLabel(BusinessType.other, 'Event Planning', 'en'),
        equals('Event Planning'),
      );
      expect(quoteBusinessLabel(null, '', 'en'), equals('Quote'));
    });

    test('slugs are free-form and filename-safe', () {
      expect(
        businessTypeSlug(BusinessType.other, 'Event Planning'),
        equals('event_planning'),
      );
      expect(
        businessTypeSlug(BusinessType.tiling, 'whatever'),
        equals('tiling'),
      );
      // Blank custom falls back to the stable id, never an empty slug.
      expect(businessTypeSlug(BusinessType.other, '  '), equals('other'));
    });

    test('profile round-trips a custom business', () {
      final profile = BusinessProfile(
        id: 'u1',
        businessName: 'Asha Events',
        businessType: BusinessType.other,
        customBusinessType: 'Event Planning',
        updatedAt: DateTime.now(),
      );
      final restored = BusinessProfile.fromJson(profile.toJson());
      expect(restored.businessType, equals(BusinessType.other));
      expect(restored.customBusinessType, equals('Event Planning'));
    });

    test('unknown synced slugs become Other instead of tiling', () {
      final restored = BusinessProfile.fromJson({
        'id': 'u2',
        'business_type': 'event_planning',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      expect(restored.businessType, equals(BusinessType.other));
      expect(restored.customBusinessType, equals('event planning'));
    });

    test('Other seeds nothing: starts from scratch', () async {
      final seeded =
          await ServiceItemRepository.seedFromTemplate(BusinessType.other);
      expect(seeded, isEmpty);
      expect(await ServiceItemRepository.getAll(), isEmpty);
    });
  });
}

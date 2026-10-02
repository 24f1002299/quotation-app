import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/business_profile.dart';
import 'package:contractor_quote_poc/models/service_item.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/storage/profile_repository.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/storage/sync_outbox.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/templates/template_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
  });

  group('BusinessProfile model & persistence', () {
    test('serializes to JSON and deserializes back faithfully', () {
      final profile = BusinessProfile(
        id: 'usr_123',
        ownerName: 'Ramesh Patil',
        businessName: 'Patil Tile Works',
        phone: '+91 98765 43210',
        city: 'Pune, Maharashtra',
        businessType: BusinessType.tiling,
        gstin: '27AAAAA0000A1Z5',
        logoPath: 'usr_123/logos/logo.png',
        logoSignedUrl: 'https://storage.supabase.co/signed?token=abc',
        quoteTerms: '50% advance before tile delivery',
        updatedAt: DateTime(2026, 9, 22, 10, 0),
      );

      final restored = BusinessProfile.fromJson(profile.toJson());

      expect(restored.id, equals('usr_123'));
      expect(restored.ownerName, equals('Ramesh Patil'));
      expect(restored.businessName, equals('Patil Tile Works'));
      expect(restored.phone, equals('+91 98765 43210'));
      expect(restored.city, equals('Pune, Maharashtra'));
      expect(restored.businessType, equals(BusinessType.tiling));
      expect(restored.gstin, equals('27AAAAA0000A1Z5'));
      expect(restored.logoPath, equals('usr_123/logos/logo.png'));
      expect(restored.quoteTerms, equals('50% advance before tile delivery'));
      // Wire contract: timestamps go out as UTC.
      expect(profile.toJson()['updated_at'], endsWith('Z'));
    });

    test('profile repository persists locally and enqueues an outbox mutation',
        () async {
      final initial = await ProfileRepository.getProfile();
      expect(initial.isConfigured, isFalse);

      await ProfileRepository.saveProfile(
        BusinessProfile(
          id: 'contractor_42',
          ownerName: 'Asha Sharma',
          businessName: 'Asha Interiors',
          phone: '+91 98111 22233',
          city: 'Mumbai',
          businessType: BusinessType.painting,
          updatedAt: DateTime.now(),
        ),
      );

      final loaded = await ProfileRepository.getProfile();
      expect(loaded.ownerName, equals('Asha Sharma'));
      expect(loaded.businessName, equals('Asha Interiors'));
      expect(loaded.businessType, equals(BusinessType.painting));
      expect(await ProfileRepository.hasCompletedOnboarding(), isTrue);

      final pending = await SyncOutbox.getPending();
      expect(pending.any((o) => o.entityType == 'profile'), isTrue);
    });
  });

  group('Starter templates', () {
    test('every business type ships a template that parses', () async {
      for (final info in kBusinessTypes) {
        final template = await TemplateLoader.load(info.type);
        expect(template.services, isNotEmpty,
            reason: '${info.id} must seed at least one service');
        expect(template.defaultUnit, isNotEmpty);
      }
    });

    test('businessTypeFromId resolves ids and falls back safely', () {
      expect(businessTypeFromId('appliance_repair'),
          equals(BusinessType.applianceRepair));
      expect(businessTypeFromId('unknown-type'), equals(BusinessType.tiling));
      expect(businessTypeFromId(null), equals(BusinessType.tiling));
    });
  });

  group('ServiceItem CRUD', () {
    test('an empty list stays empty until the template is seeded', () async {
      expect(await ServiceItemRepository.getAll(), isEmpty);

      final seeded =
          await ServiceItemRepository.seedFromTemplate(BusinessType.plumbing);
      expect(seeded, isNotEmpty);

      final stored = await ServiceItemRepository.getActiveForBusinessType(
        BusinessType.plumbing,
      );
      expect(stored.length, equals(seeded.length));
      expect(stored.every((s) => s.businessType == BusinessType.plumbing), isTrue);
    });

    test('seeding twice does not duplicate the user\'s services', () async {
      final first =
          await ServiceItemRepository.seedFromTemplate(BusinessType.carpentry);
      final second =
          await ServiceItemRepository.seedFromTemplate(BusinessType.carpentry);
      expect(second.length, equals(first.length));
      expect(await ServiceItemRepository.getAll(), hasLength(first.length));
    });

    test('upsert creates, updates, and re-reads a service', () async {
      final created = await ServiceItemRepository.upsert(
        name: 'Tile fixing',
        unit: 'sq ft',
        ratePaise: 4500,
        businessType: BusinessType.tiling,
        keywords: ['tiles lagana'],
      );
      expect(created.rateRupees, equals(45));
      expect(created.version, equals(2));

      final updated = await ServiceItemRepository.upsert(
        id: created.id,
        name: 'Tile fixing and supply',
        unit: 'sq ft',
        ratePaise: 8500,
        businessType: BusinessType.tiling,
      );
      expect(updated.id, equals(created.id));
      expect(updated.name, equals('Tile fixing and supply'));
      expect(updated.rateRupees, equals(85));

      final fetched = await ServiceItemRepository.getById(created.id);
      expect(fetched!.ratePaise, equals(8500));
      expect(fetched.name, contains('supply'));

      final outbox = await SyncOutbox.getPending();
      expect(outbox.any((o) => o.entityType == 'service_item'), isTrue);
    });

    test('delete removes the service and queues a delete', () async {
      final item = await ServiceItemRepository.upsert(
        name: 'Bathroom cleaning',
        businessType: BusinessType.cleaning,
      );
      await ServiceItemRepository.delete(item.id);

      expect(await ServiceItemRepository.getById(item.id), isNull);
      final outbox = await SyncOutbox.getPending();
      expect(outbox.any((o) => o.action == 'delete'), isTrue);
    });

    test('rate map only contains services that have a rate', () async {
      await ServiceItemRepository.saveAll([
        ServiceItem(
          id: 'svc_rated',
          name: 'Pipe repair',
          ratePaise: 45000,
          businessType: BusinessType.plumbing,
          updatedAt: DateTime.now(),
        ),
        ServiceItem(
          id: 'svc_unrated',
          name: 'Drain cleaning',
          businessType: BusinessType.plumbing,
          updatedAt: DateTime.now(),
        ),
      ]);

      final map = await ServiceItemRepository.getRateMap(BusinessType.plumbing);
      expect(map['svc_rated'], equals(45000));
      expect(map.containsKey('svc_unrated'), isFalse);
    });

    test('search matches name and keywords, case-insensitively', () async {
      await ServiceItemRepository.saveAll([
        ServiceItem(
          id: 'svc_1',
          name: 'Wall putty',
          keywords: ['putty', 'polish'],
          businessType: BusinessType.painting,
          updatedAt: DateTime.now(),
        ),
      ]);

      expect((await ServiceItemRepository.search('putty')).length, equals(1));
      expect((await ServiceItemRepository.search('PUTTY')).length, equals(1));
      expect((await ServiceItemRepository.search('plumbing')), isEmpty);
    });

    test('service JSON round-trips with keywords and localized names', () {
      final item = ServiceItem(
        id: 'svc_x',
        name: 'Tap installation',
        nameHi: 'टैप लगाना',
        nameMr: 'नळ बसवणे',
        unit: 'point',
        ratePaise: 60000,
        businessType: BusinessType.plumbing,
        keywords: ['tap fitting', 'नळ'],
        updatedAt: DateTime(2026, 9, 22, 10, 0),
      );

      final restored = ServiceItem.fromJson(item.toJson());
      expect(restored.nameHi, equals('टैप लगाना'));
      expect(restored.nameMr, equals('नळ बसवणे'));
      expect(restored.businessType, equals(BusinessType.plumbing));
      expect(restored.keywords, equals(['tap fitting', 'नळ']));
      expect(restored.ratePaise, equals(60000));
    });

    test('matchTerms covers the name, localized names and keywords', () {
      final item = ServiceItem(
        id: 'svc_t',
        name: 'Tile fixing',
        nameHi: 'टाइल लगाना',
        keywords: ['Tiles Lagana'],
        updatedAt: DateTime.now(),
      );
      expect(item.matchTerms,
          containsAll(['tile fixing', 'टाइल लगाना', 'tiles lagana']));
    });
  });

  group('Saved service rates apply to spoken quotes', () {
    test('a saved rate fills in when speech omits it', () async {
      final service = await ServiceItemRepository.upsert(
        name: 'Tile fixing',
        unit: 'sq ft',
        ratePaise: 8500,
        businessType: BusinessType.tiling,
        keywords: ['टाईल लेबर', 'tile labour'],
      );

      final services = await ServiceItemRepository.getActiveForBusinessType(
        BusinessType.tiling,
      );
      final rateMap = await ServiceItemRepository.getRateMap(BusinessType.tiling);
      expect(rateMap[service.id], equals(8500));

      // Quantity only, no rate spoken.
      const transcript = '120 sq ft टाईल लेबर';
      const parser = TranscriptParser();
      final result =
          parser.parse(transcript, services: services, savedRates: rateMap);

      expect(result.items.length, equals(1));
      final item = result.items.first;
      expect(item.description, equals('Tile fixing'));
      expect(item.serviceItemId, equals(service.id));
      expect(item.quantity, equals(120));
      expect(item.unit, equals('sq ft'));
      expect(item.unitRatePaise, equals(8500));
      expect(result.warnings, isEmpty);
    });

    test('a spoken rate overrides the saved rate', () {
      final service = ServiceItem(
        id: 'svc_t',
        name: 'Tile fixing',
        unit: 'sq ft',
        ratePaise: 8500,
        businessType: BusinessType.tiling,
        updatedAt: DateTime.now(),
      );

      final result = const TranscriptParser().parse(
        '120 sq ft tile fixing 95 rate',
        services: [service],
        savedRates: {'svc_t': 8500},
      );

      expect(result.items.length, equals(1));
      expect(result.items.first.unitRatePaise, equals(9500));
      expect(result.warnings, isEmpty);
    });

    test('numbers with no matching service produce a manual-entry warning', () {
      final result = const TranscriptParser()
          .parse('120 sq ft something unknown', services: const []);

      expect(result.items, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.first, contains('manually'));
    });
  });
}

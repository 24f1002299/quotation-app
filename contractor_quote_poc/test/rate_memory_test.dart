import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/catalog/catalog.dart';
import 'package:contractor_quote_poc/models/contractor_profile.dart';
import 'package:contractor_quote_poc/models/rate_memory_item.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/storage/profile_repository.dart';
import 'package:contractor_quote_poc/storage/rate_memory_repository.dart';
import 'package:contractor_quote_poc/storage/sync_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Day 12 — ContractorProfile Model & Persistence', () {
    test('Serializes to JSON and deserializes back faithfully', () {
      final profile = ContractorProfile(
        id: 'usr_123',
        name: 'Ramesh Patil',
        businessName: 'Patil Tile Works',
        phone: '+91 98765 43210',
        city: 'Pune, Maharashtra',
        trade: Trade.tiling,
        gstin: '27AAAAA0000A1Z5',
        logoPath: 'usr_123/logos/logo.png',
        logoSignedUrl: 'https://storage.supabase.co/signed?token=abc',
        quoteTerms: '50% advance before tile delivery',
        updatedAt: DateTime(2026, 9, 22, 10, 0),
      );

      final json = profile.toJson();
      final restored = ContractorProfile.fromJson(json);

      expect(restored.id, equals('usr_123'));
      expect(restored.name, equals('Ramesh Patil'));
      expect(restored.businessName, equals('Patil Tile Works'));
      expect(restored.phone, equals('+91 98765 43210'));
      expect(restored.city, equals('Pune, Maharashtra'));
      expect(restored.trade, equals(Trade.tiling));
      expect(restored.gstin, equals('27AAAAA0000A1Z5'));
      expect(restored.logoPath, equals('usr_123/logos/logo.png'));
      expect(restored.quoteTerms, equals('50% advance before tile delivery'));
    });

    test('ProfileRepository persists profile locally and enqueues outbox', () async {
      final initial = await ProfileRepository.getProfile();
      expect(initial.isConfigured, isFalse);

      final profile = ContractorProfile(
        id: 'contractor_42',
        name: 'Asha Sharma',
        businessName: 'Asha Interiors',
        phone: '+91 98111 22233',
        city: 'Mumbai',
        trade: Trade.painting,
        updatedAt: DateTime.now(),
      );

      await ProfileRepository.saveProfile(profile);

      final loaded = await ProfileRepository.getProfile();
      expect(loaded.name, equals('Asha Sharma'));
      expect(loaded.businessName, equals('Asha Interiors'));
      expect(loaded.trade, equals(Trade.painting));

      // Verify sync outbox contains the mutation
      final pending = await SyncOutbox.getPending();
      expect(pending, isNotEmpty);
      expect(pending.any((o) => o.entityType == 'profile'), isTrue);
    });
  });

  group('Day 12 — Rate Memory Seeding & Persistence', () {
    test('getAllRates seeds catalog items automatically on fresh start', () async {
      final rates = await RateMemoryRepository.getAllRates();
      expect(rates, isNotEmpty);
      expect(rates.length, equals(kCatalog.length));

      // Verify all 6 catalog items are represented
      final itemIds = rates.map((r) => r.catalogItemId).toSet();
      expect(itemIds.contains('tile_labour'), isTrue);
      expect(itemIds.contains('skirting'), isTrue);
      expect(itemIds.contains('waterproofing'), isTrue);
      expect(itemIds.contains('wall_putty'), isTrue);
      expect(itemIds.contains('primer'), isTrue);
      expect(itemIds.contains('painting'), isTrue);
    });

    test('Saving a rate updates cache and enqueues to outbox', () async {
      final tilingRates = await RateMemoryRepository.getRatesForTrade(Trade.tiling);
      final tileLabour = tilingRates.firstWhere((r) => r.catalogItemId == 'tile_labour');

      // Set custom tiling rate: ₹85 / sq ft (8500 paise)
      final updated = tileLabour.copyWith(unitRatePaise: 8500);
      await RateMemoryRepository.saveRate(updated);

      final fetched = await RateMemoryRepository.getRateFor('tile_labour', Trade.tiling);
      expect(fetched, isNotNull);
      expect(fetched!.unitRatePaise, equals(8500));
      expect(fetched.rateRupees, equals(85));

      final outbox = await SyncOutbox.getPending();
      expect(outbox.any((o) => o.entityType == 'rate_memory'), isTrue);
    });
  });

  group('Day 12 — Verification: Set Tiling Rate & Apply to Extracted Item', () {
    test('Setting a tiling rate applies it automatically to quantity-only speech', () async {
      // 1. Contractor sets tiling rate in Rate Memory to ₹85 / sq ft
      final tileItem = RateMemoryItem(
        id: 'test_tile_rate',
        catalogItemId: 'tile_labour',
        trade: Trade.tiling,
        unit: 'sq ft',
        unitRatePaise: 8500, // ₹85/sq ft
        updatedAt: DateTime.now(),
      );
      await RateMemoryRepository.saveRate(tileItem);

      // 2. Load the rate map (as the app does when extracting / parsing)
      final rateMap = await RateMemoryRepository.getRateMap(Trade.tiling);
      expect(rateMap['tile_labour'], equals(8500));

      // 3. User speaks or enters quantity ONLY, without stating the rate:
      // "हॉल मध्ये 120 स्क्वेअर फूट टाईल लेबर" (120 sq ft tile labour)
      const transcript = 'हॉल मध्ये 120 स्क्वेअर फूट टाईल लेबर';

      // 4. Parser parses transcript with contractor's rateMemory
      const parser = TranscriptParser();
      final result = parser.parse(transcript, rateMemory: rateMap);

      // 5. Verification checks:
      // - Item is extracted
      expect(result.items.length, equals(1));
      final item = result.items.first;

      expect(item.description, contains('Tile Labour'));
      expect(item.quantity, equals(120));
      expect(item.unit, equals('sq ft'));

      // - Rate is applied directly from rate memory (8500 paise = ₹85)
      expect(item.unitRatePaise, equals(8500));

      // - Total amount calculated: 120 × ₹85 = ₹10,200 (1020000 paise)
      expect(item.quantity * item.unitRatePaise, equals(120 * 8500));

      // - Crucial: NO warning is emitted because the missing rate was resolved!
      expect(result.warnings, isEmpty);
    });

    test('Spoken rate overrides rate memory if contractor explicitly quotes a different rate', () async {
      // Saved rate is ₹85
      final rateMap = {'tile_labour': 8500};

      // Spoken text explicitly says rate is 95: "120 sq ft tile labour 95 rate"
      const transcript = '120 sq ft tile labour 95 rate';
      const parser = TranscriptParser();
      final result = parser.parse(transcript, rateMemory: rateMap);

      expect(result.items.length, equals(1));
      // Explicitly spoken rate (9500 paise) takes precedence over default memory
      expect(result.items.first.unitRatePaise, equals(9500));
      expect(result.warnings, isEmpty);
    });
  });
}

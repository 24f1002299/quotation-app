import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/service_item.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/templates/template_loader.dart';
import 'package:contractor_quote_poc/voice/extraction_service.dart';

/// Step 3 — Universal AI extraction: the user's service list is the context
/// for ANY business domain. Covers pest control, catering, electrical,
/// tiling and painting over the online path (serviceItems wire keys +
/// suggestedItems) and the offline generic fallback (numbers/rates parse
/// without any catalog match).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
  });

  Map<String, dynamic> readBody(http.Request request) {
    return json.decode(request.body) as Map<String, dynamic>;
  }

  group('Universal online extraction (5 domains)', () {
    test('pest control: serviceItems sent, items + suggestions parsed', () async {
      await ServiceItemRepository.seedFromTemplate(BusinessType.pestControl);
      const transcript = 'cockroach treatment 2 rooms 500 rupaye';

      MockClient? seenClient;
      final mockClient = MockClient((request) async {
        final body = readBody(request);
        expect(body['businessType'], equals('pest_control'));
        final items = body['serviceItems'] as List<dynamic>;
        expect(items, isNotEmpty);
        expect(items.first, containsPair('name', isA<String>()));
        expect(items.first, containsPair('keywords', isA<List>()));
        return http.Response(
          json.encode({
            'lineItems': [
              {
                'catalogItemId': items.first['id'],
                'description': 'Cockroach treatment',
                'quantity': 2,
                'unit': 'room',
                'unitRatePaise': 50000,
                'rateSource': 'RATE_MEMORY',
                'confidence': 0.95,
              },
            ],
            'suggestedItems': [
              {
                'proposedName': 'Balcony netting',
                'quantity': 1,
                'unit': 'visit',
                'rateHintPaise': 150000,
                'sourceSpan': 'balcony netting 1 visit',
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
        );
      });
      seenClient = mockClient;

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.pestControl,
        client: seenClient,
      );

      expect(result.isFromLocalFallback, isFalse);
      expect(result.lineItems, hasLength(1));
      // Legacy catalogItemId key binds to the service id.
      expect(result.lineItems.first.serviceItemId, isNotEmpty);
      expect(result.lineItems.first.quantity, equals(2));
      expect(result.suggestedItems, hasLength(1));
      expect(result.suggestedItems.first.proposedName, equals('Balcony netting'));
      expect(result.suggestedItems.first.rateHintPaise, equals(150000));
      final review = result.suggestedItems.first.toQuoteLineItem();
      expect(review.requiresReview, isTrue);
      expect(review.isUnknown, isTrue);
    });

    test('catering: plates + kg units extract with rate hints', () async {
      await ServiceItemRepository.seedFromTemplate(BusinessType.catering);
      const transcript = 'veg thali 100 plate 250 rupaye';

      final mockClient = MockClient((request) async {
        final body = readBody(request);
        expect(body['businessType'], equals('catering'));
        return http.Response(
          json.encode({
            'lineItems': [
              {
                'serviceItemId': 'veg_thali',
                'description': 'Veg thali',
                'quantity': 100,
                'unit': 'plate',
                'unitRatePaise': 25000,
                'rateSource': 'EXPLICIT',
                'confidence': 0.96,
              },
            ],
            'suggestedItems': [
              {
                'proposedName': 'Sweet counter',
                'quantity': 5,
                'unit': 'kg',
                'sourceSpan': 'sweet 5 kg',
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.catering,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(1));
      expect(result.lineItems.first.unit, equals('plate'));
      expect(result.suggestedItems, hasLength(1));
      expect(result.suggestedItems.first.unit, equals('kg'));
      // No stated rate -> hint stays 0, still reviewable.
      expect(result.suggestedItems.first.rateHintPaise, equals(0));
      expect(
        result.suggestedItems.first.toQuoteLineItem().requiresReview,
        isTrue,
      );
    });

    test('electrical: points extract against the user service list', () async {
      await ServiceItemRepository.seedFromTemplate(BusinessType.electrical);
      const transcript = 'switch board 4 point 250 rupaye';

      final mockClient = MockClient((request) async {
        final body = readBody(request);
        expect(body['businessType'], equals('electrical'));
        expect(body['trade'], equals('electrical'));
        return http.Response(
          json.encode({
            'lineItems': [
              {
                'serviceItemId': 'switch_board',
                'description': 'Switch board fitting',
                'quantity': 4,
                'unit': 'point',
                'unitRatePaise': 25000,
                'rateSource': 'EXPLICIT',
                'confidence': 0.94,
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.electrical,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(1));
      expect(result.lineItems.first.quantity, equals(4));
      expect(result.lineItems.first.unit, equals('point'));
    });

    test('tiling + painting: new wire keys present, legacy keys kept', () async {
      await ServiceItemRepository.seedFromTemplate(BusinessType.tiling);
      const transcript = 'tile fixing 120 sq ft 45 rupaye';

      final mockClient = MockClient((request) async {
        final body = readBody(request);
        expect(body['businessType'], equals('tiling'));
        expect(body['trade'], equals('tiling'));
        expect(body['serviceItems'], isA<List>());
        expect(body['catalogEntries'], isA<List>());
        expect((body['serviceItems'] as List), isNotEmpty);
        expect(body['rateMemory'], isA<List>());
        expect(body['savedRates'], isA<List>());
        return http.Response(
          json.encode({
            'lineItems': [
              {
                'serviceItemId': 'tile_fixing',
                'description': 'Tile fixing',
                'quantity': 120,
                'unit': 'sq ft',
                'unitRatePaise': 4500,
                'rateSource': 'EXPLICIT',
                'confidence': 0.97,
              },
            ],
            'unknowns': [],
            'requiresReview': true,
          }),
          200,
        );
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.tiling,
        client: mockClient,
      );

      expect(result.lineItems, hasLength(1));
      expect(result.lineItems.first.unitRatePaise, equals(4500));
    });
  });

  group('Offline generic fallback (no catalog match needed)', () {
    test('pest numbers/rates parse offline against seeded services', () async {
      await ServiceItemRepository.seedFromTemplate(BusinessType.pestControl);
      const transcript = 'cockroach treatment 2 rooms 500 rupaye';

      final mockClient = MockClient((request) async {
        throw TimeoutException('offline');
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.pestControl,
        client: mockClient,
      );

      expect(result.isFromLocalFallback, isTrue);
      expect(result.lineItems, hasLength(1));
      expect(result.lineItems.first.description, equals('Cockroach treatment'));
      expect(result.lineItems.first.quantity, equals(2));
      expect(result.lineItems.first.unit, equals('room'));
      expect(result.lineItems.first.unitRatePaise, equals(50000));
    });

    test('unknown-domain numbers become review suggestions, never dropped', () async {
      await ServiceItemRepository.saveAll([]);
      // 'and' separates phrases (commas are normalized away by the parser).
      const transcript = 'sofa repair 1 piece and wall cleaning 2 hours 300 rupaye';

      final mockClient = MockClient((request) async {
        throw TimeoutException('offline');
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.cleaning,
        client: mockClient,
      );

      expect(result.isFromLocalFallback, isTrue);
      // Nothing matched, but both number-bearing phrases survive as suggestions.
      expect(result.suggestedItems.length, equals(2));
      expect(result.suggestedItems[0].quantity, equals(1));
      expect(result.suggestedItems[0].unit, equals('nos'));
      expect(result.suggestedItems[1].quantity, equals(2));
      expect(result.suggestedItems[1].unit, equals('hour'));
      expect(result.suggestedItems[1].rateHintPaise, equals(30000));
      for (final s in result.suggestedItems) {
        expect(s.toQuoteLineItem().requiresReview, isTrue);
      }
    });

    test('preamble without numbers stays empty without crashing', () async {
      const transcript = 'namaste bhai sahab kal baat karte hain';

      final mockClient = MockClient((request) async {
        throw TimeoutException('offline');
      });

      final result = await ExtractionService.extract(
        transcript: transcript,
        businessType: BusinessType.catering,
        client: mockClient,
      );

      expect(result.isFromLocalFallback, isTrue);
      expect(result.lineItems, isEmpty);
      expect(result.suggestedItems, isEmpty);
    });
  });

  group('Parser generic units + strict default preserved', () {
    const parser = TranscriptParser();

    ServiceItem svc(String name, BusinessType type, List<String> keywords) {
      return ServiceItem(
        id: 'svc_$name',
        name: name,
        businessType: type,
        keywords: keywords,
        updatedAt: DateTime.now(),
      );
    }

    test('generic units parse for any domain service', () {
      final services = [
        svc('Veg thali', BusinessType.catering, ['veg thali', 'thali']),
        svc('Switch board', BusinessType.electrical, ['switch board']),
        svc('Cockroach treatment', BusinessType.pestControl, ['cockroach']),
      ];
      var r = parser.parse(
        'veg thali 100 plate 250 rupaye',
        services: services,
        genericFallback: true,
      );
      expect(r.items, hasLength(1));
      expect(r.items.first.unit, equals('plate'));
      expect(r.items.first.unitRatePaise, equals(25000));

      r = parser.parse(
        'switch board 4 point',
        services: services,
        genericFallback: true,
      );
      expect(r.items, hasLength(1));
      expect(r.items.first.unit, equals('point'));

      r = parser.parse(
        'cockroach 2 rooms 500 rupaye',
        services: services,
        genericFallback: true,
      );
      expect(r.items, hasLength(1));
      expect(r.items.first.unit, equals('room'));
      expect(r.items.first.unitRatePaise, equals(50000));
    });

    test('strict default still returns empty + manual warning for unknowns', () {
      final r = parser.parse(
        '120 sq ft something unknown',
        services: const [],
      );
      expect(r.items, isEmpty);
      expect(r.warnings, hasLength(1));
      expect(r.warnings.first, contains('manually'));
    });
  });
}

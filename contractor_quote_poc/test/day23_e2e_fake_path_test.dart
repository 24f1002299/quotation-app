// Day 23 — End-to-end happy path with faked transcription + extraction.
//
// speak (fake audio -> transcript) -> extract (fake server JSON) -> review
// (Quote) -> totals/PDF gate -> persist (SavedQuote round-trip) -> sync
// (idempotent save). No microphone, network, or backend required.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:contractor_quote_poc/models/extraction_models.dart';
import 'package:contractor_quote_poc/models/quote.dart';
import 'package:contractor_quote_poc/models/service_item.dart';
import 'package:contractor_quote_poc/parser/transcript_parser.dart';
import 'package:contractor_quote_poc/storage/saved_quote.dart';
import 'package:contractor_quote_poc/storage/service_item_repository.dart';
import 'package:contractor_quote_poc/templates/template_data.dart';
import 'package:contractor_quote_poc/templates/template_loader.dart';
import 'package:contractor_quote_poc/utils/quote_ids.dart';

// Demo transcript previously in lib/parser/demo_transcripts.dart
// (file deleted; inlined here so tests don't depend on lib/).
const kTilingDemoTranscript =
    'Sharma ji ka flat, 850 square foot tiles labour, 45 rupaye per foot, skirting 120 running foot, 60 rupaye per foot.';

// ── Fakes ────────────────────────────────────────────────────────────────

/// Stands in for the mic + Whisper endpoint: deterministic transcript.
class FakeTranscriber {
  Future<String> transcribe() async => kTilingDemoTranscript;
}

/// Stands in for POST /api/extract: returns OpenAPI-shaped JSON built from
/// the deterministic local parser, so the client path (fromJson, rate
/// provenance, unknowns) is exercised exactly as with a real server.
class FakeExtractionServer {
  static Map<String, dynamic> extract(
    String transcript, {
    List<ServiceItem> services = const [],
    Map<String, int>? savedRates,
  }) {
    const parser = TranscriptParser();
    final parsed =
        parser.parse(transcript, services: services, savedRates: savedRates);
    return {
      'business_type': 'tiling',
      'requiresReview': parsed.hasWarnings,
      'lineItems': [
        for (final item in parsed.items)
          {
            'serviceItemId': 'tile_labour_or_skirting',
            'description': item.description,
            'quantity': item.quantity,
            'unit': item.unit,
            'unitRatePaise': item.unitRatePaise,
            'rateSource': 'RATE_MEMORY',
            'confidence': 0.95,
            'sourceSpan': {'text': item.description},
          },
      ],
      'unknowns': [
        for (final w in parsed.warnings)
          {'text': w, 'reason': w, 'confidence': 0.5},
      ],
    };
  }
}

/// Minimal accept-once server double for the sync step.
class FakeSyncServer {
  final Map<String, SavedQuote> _store = {};
  int writes = 0;

  SavedQuote save(SavedQuote q) {
    final existing = _store[q.idempotencyKey];
    if (existing != null) return existing; // retry returns same record
    writes++;
    _store[q.idempotencyKey] = q;
    return q;
  }
}

void main() {
  // Pure unit test, but seeding services reads a template asset via
  // rootBundle — needs a test binding (flutter_test provides assets).
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice -> extract -> review -> totals -> persist -> sync happy path',
      () async {
    // 1. Speak (fake): audio becomes the tiling demo transcript.
    final transcript = await FakeTranscriber().transcribe();
    expect(transcript, isNotEmpty);

    // The universal parser matches against the user's own service list,
    // so the fake server seeds it exactly like the app does on first use.
    SharedPreferences.setMockInitialValues({});
    TemplateLoader.clearCache();
    final services =
        await ServiceItemRepository.seedFromTemplate(BusinessType.tiling);
    final rateMap =
        await ServiceItemRepository.getRateMap(BusinessType.tiling);

    // 2. Extract (fake server): OpenAPI-shaped JSON -> typed candidates.
    final payload = FakeExtractionServer.extract(
      transcript,
      services: services,
      savedRates: rateMap,
    );
    final items = (payload['lineItems'] as List)
        .map((raw) =>
            ExtractedItem.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
    expect(items, hasLength(2));

    // 3. Review: candidates become the source-of-truth line items.
    final lineItems = items.map((e) => e.toQuoteLineItem()).toList();
    final quote = Quote(
      id: newQuoteId(),
      quoteNumber: 'Q-2026-0042',
      customer: const Customer(name: 'Sharma Ji'),
      lineItems: lineItems,
      originalTranscript: transcript,
    );

    // 4. Totals + PDF gate: deterministic engine owns the money.
    final totals = calculateTotals(quote);
    expect(totals.subtotalPaise, 4545000); // ₹45,450 Day-2 fixture
    expect(totals.grandTotalPaise, 4545000); // GST off by default
    expect(quotePdfBlockingReason(quote), isNull);

    // 5. Persist: SavedQuote round-trip keeps totals + idempotency anchor.
    final saved = SavedQuote(
      id: quote.id!,
      quoteNumber: quote.quoteNumber!,
      createdAt: DateTime(2026, 9, 25),
      customerName: quote.customer.name,
      originalTranscript: transcript,
      lineItems: lineItems,
    );
    final restored = SavedQuote.fromJson(saved.toJson());
    expect(restored.idempotencyKey, saved.id);
    expect(restored.grandTotalPaise, 4545000);

    // 6. Sync: retry with the same idempotency key writes exactly once.
    final server = FakeSyncServer();
    final first = server.save(restored);
    final retry = server.save(restored);
    expect(identical(first, retry), isTrue);
    expect(server.writes, 1);
  });

  test('extraction unknowns become review-flagged items, PDF stays blocked',
      () async {
    const unknownPayload = {
      'serviceItemId': 'custom_item',
      'description': 'Sofa repair',
      'quantity': 1.0,
      'unit': 'item',
      'unitRatePaise': 0,
      'rateSource': 'UNKNOWN',
      'confidence': 0.4,
      'uncertaintyNote': 'Not in businessType catalog',
    };
    final item =
        ExtractedItem.fromJson(unknownPayload).toQuoteLineItem();
    expect(item.requiresReview, isTrue);

    final quote = Quote(
      customer: const Customer(name: 'Client'),
      lineItems: [item],
    );
    expect(quotePdfBlockingReason(quote), isNotNull);
  });
}

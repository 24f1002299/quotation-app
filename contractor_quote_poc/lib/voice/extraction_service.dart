import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog.dart';
import '../config/api_config.dart';
import '../models/extraction_models.dart';
import '../parser/transcript_parser.dart';
import '../storage/rate_memory_repository.dart';

/// Day 13 — Client service connecting voice/text transcripts to extraction API.
///
/// Features:
/// - Sends transcript, trade catalog, and contractor rate memory to /api/extract.
/// - Implements conservative timeout (6 seconds).
/// - Resilient zero-data-loss fallback: if server is unreachable, times out, or
///   fails, seamlessly parses with local deterministic engine so work is never lost.
class ExtractionService {
  const ExtractionService._();

  static const Duration _kTimeout = Duration(seconds: 6);

  /// Extracts structured quotation line items from [transcript].
  static Future<ExtractionResult> extract({
    required String transcript,
    required Trade trade,
    String languageHint = 'auto',
    http.Client? client,
  }) async {
    final cleanText = transcript.trim();
    if (cleanText.isEmpty) {
      return ExtractionResult(
        trade: trade.name,
        lineItems: const [],
        requiresReview: false,
      );
    }

    final httpClient = client ?? http.Client();
    final rateMap = await RateMemoryRepository.getRateMap(trade);
    final savedRates = await RateMemoryRepository.getRatesForTrade(trade);

    // 1. Prepare request payload for /api/extract
    final catalogItems = catalogForTrade(trade);
    final catalogEntries = catalogItems.map((c) => {
      'id': c.id,
      'displayName': c.displayName,
      'defaultUnit': c.defaultUnit,
      'synonyms': c.synonyms,
      'trade': c.trade.name,
    }).toList();

    final rateMemoryDtoList = savedRates.map((r) => {
      'catalogItemId': r.catalogItemId,
      'unit': r.unit,
      'unitRatePaise': r.unitRatePaise,
      'trade': r.trade.name,
    }).toList();

    final idempotencyKey = 'ext_${DateTime.now().millisecondsSinceEpoch}_${cleanText.hashCode.abs()}';

    final requestBody = json.encode({
      'transcript': cleanText,
      'trade': trade.name,
      'catalogEntries': catalogEntries,
      'rateMemory': rateMemoryDtoList,
      'language': languageHint,
      'schemaVersion': '1.0',
      'version': 1,
      'idempotencyKey': idempotencyKey,
    });

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
    };

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && session.accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    } catch (_) {
      // Offline / dev mock
    }

    // 2. Perform API call
    try {
      final uri = Uri.parse('$kApiBaseUrl/extract');
      final response = await httpClient
          .post(uri, headers: headers, body: requestBody)
          .timeout(_kTimeout);

      if (response.statusCode == 200) {
        final bodyStr = response.body.isNotEmpty
            ? response.body
            : utf8.decode(response.bodyBytes, allowMalformed: true);
        final data = json.decode(bodyStr) as Map<String, dynamic>;

        final rawItems = data['lineItems'] as List<dynamic>? ?? const [];
        final items = rawItems
            .map((raw) => ExtractedItem.fromJson(raw as Map<String, dynamic>))
            .toList();

        final rawUnknowns = data['unknowns'] as List<dynamic>? ?? const [];
        final unknowns = rawUnknowns
            .map((raw) => ExplicitUnknown.fromJson(raw as Map<String, dynamic>))
            .toList();

        final reqReview = data['requiresReview'] as bool? ?? true;

        return ExtractionResult(
          trade: trade.name,
          lineItems: items,
          unknowns: unknowns,
          requiresReview: reqReview,
          isFromLocalFallback: false,
        );
      } else {
        // Non-200 response -> fall back to local parser without discarding draft
        return _fallbackToLocalParser(
          transcript: cleanText,
          trade: trade,
          rateMap: rateMap,
          errorMessage: 'Server responded with status ${response.statusCode}. Used local extraction.',
        );
      }
    } on TimeoutException {
      // Timeout -> Fallback gracefully
      return _fallbackToLocalParser(
        transcript: cleanText,
        trade: trade,
        rateMap: rateMap,
        errorMessage: 'Extraction request timed out. Used local extraction.',
      );
    } on SocketException {
      // Network/offline -> Fallback gracefully
      return _fallbackToLocalParser(
        transcript: cleanText,
        trade: trade,
        rateMap: rateMap,
        errorMessage: 'Network unavailable. Extracted offline using local catalog.',
      );
    } catch (e) {
      // Any other error -> Fallback gracefully
      return _fallbackToLocalParser(
        transcript: cleanText,
        trade: trade,
        rateMap: rateMap,
        errorMessage: 'Extraction service error: $e. Used local extraction.',
      );
    }
  }

  /// Resilient fallback to deterministic local parser so site work is NEVER lost.
  static ExtractionResult _fallbackToLocalParser({
    required String transcript,
    required Trade trade,
    required Map<String, int> rateMap,
    String? errorMessage,
  }) {
    const parser = TranscriptParser();
    final parseResult = parser.parse(transcript, rateMemory: rateMap);

    final items = parseResult.items.map((pi) {
      // Match back to catalog item ID
      String catId = 'custom_item';
      for (final cat in catalogForTrade(trade)) {
        if (cat.displayName == pi.description) {
          catId = cat.id;
          break;
        }
      }

      final rateFromMem = (rateMap[catId] ?? 0) > 0 && pi.unitRatePaise == rateMap[catId];

      return ExtractedItem(
        catalogItemId: catId,
        description: pi.description,
        quantity: pi.quantity.toDouble(),
        unit: pi.unit,
        unitRatePaise: pi.unitRatePaise,
        rateSource: rateFromMem ? ExtractedRateSource.rateMemory : ExtractedRateSource.unknown,
        confidence: 0.9,
      );
    }).toList();

    final unknowns = parseResult.warnings.map((w) {
      return ExplicitUnknown(
        text: w,
        reason: w,
      );
    }).toList();

    return ExtractionResult(
      trade: trade.name,
      lineItems: items,
      unknowns: unknowns,
      requiresReview: true,
      isFromLocalFallback: true,
      errorMessage: errorMessage,
    );
  }
}

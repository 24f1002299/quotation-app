import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../templates/template_data.dart';
import '../config/api_config.dart';
import '../models/extraction_models.dart';
import '../parser/transcript_parser.dart';
import '../storage/service_item_repository.dart';

/// Day 13 — Client service connecting voice/text transcripts to extraction API.
///
/// Features:
/// - Sends transcript, businessType catalog, and contractor rate memory to /api/extract.
/// - Implements conservative timeout (6 seconds).
/// - Resilient zero-data-loss fallback: if server is unreachable, times out, or
///   fails, seamlessly parses with local deterministic engine so work is never lost.
class ExtractionService {
  const ExtractionService._();

  static const Duration _kTimeout = Duration(seconds: 6);

  /// Extracts structured quotation line items from [transcript].
  ///
  /// The request carries the user's own service list as the recognition
  /// context for ANY business domain — there is no fixed catalog. New wire
  /// keys (businessType/serviceItems/savedRates) are sent alongside the
  /// legacy ones (trade/catalogEntries/rateMemory) so old and new backends
  /// both bind the payload.
  static Future<ExtractionResult> extract({
    required String transcript,
    required BusinessType businessType,
    String languageHint = 'auto',
    http.Client? client,
  }) async {
    final cleanText = transcript.trim();
    if (cleanText.isEmpty) {
      return ExtractionResult(
        businessType: businessType.name,
        lineItems: const [],
        requiresReview: false,
      );
    }

    final httpClient = client ?? http.Client();
    final services = await ServiceItemRepository.getActiveForBusinessType(
      businessType,
    );
    final rateMap = await ServiceItemRepository.getRateMap(businessType);

    // 1. Prepare request payload for /api/extract
    // New-shape service entries (id/name/unit/keywords/businessType).
    final serviceItems = services
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'unit': s.unit,
            'keywords': s.matchTerms,
            'businessType': businessTypeInfo(s.businessType).id,
          },
        )
        .toList();

    // Legacy-shape entries for backward compatibility.
    final serviceEntries = services
        .map(
          (s) => {
            'id': s.id,
            'displayName': s.name,
            'defaultUnit': s.unit,
            'synonyms': s.matchTerms,
          },
        )
        .toList();

    final savedRateDtos = services
        .map(
          (s) => {
            'catalogItemId': s.id,
            'serviceItemId': s.id,
            'unit': s.unit,
            'unitRatePaise': s.ratePaise,
          },
        )
        .toList();

    final idempotencyKey = 'ext_${DateTime.now().millisecondsSinceEpoch}_${cleanText.hashCode.abs()}';
    final businessTypeSlug = businessTypeInfo(businessType).id;

    final requestBody = json.encode({
      'transcript': cleanText,
      'businessType': businessTypeSlug,
      'trade': businessTypeSlug,
      'serviceItems': serviceItems,
      'catalogEntries': serviceEntries,
      'savedRates': savedRateDtos,
      'rateMemory': savedRateDtos,
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

        final rawSuggested =
            data['suggestedItems'] as List<dynamic>? ?? const [];
        final suggested = rawSuggested
            .map((raw) => SuggestedItem.fromJson(raw as Map<String, dynamic>))
            .toList();

        final reqReview = data['requiresReview'] as bool? ?? true;

        return ExtractionResult(
          businessType: businessType.name,
          lineItems: items,
          unknowns: unknowns,
          suggestedItems: suggested,
          requiresReview: reqReview,
          isFromLocalFallback: false,
        );
      } else {
        // Non-200 response -> fall back to local parser without discarding draft
        return await _fallbackToLocalParser(
          transcript: cleanText,
          businessType: businessType,
          rateMap: rateMap,
          errorMessage: 'Server responded with status ${response.statusCode}. Used local extraction.',
        );
      }
    } on TimeoutException {
      // Timeout -> Fallback gracefully
      return await _fallbackToLocalParser(
        transcript: cleanText,
        businessType: businessType,
        rateMap: rateMap,
        errorMessage: 'Extraction request timed out. Used local extraction.',
      );
    } on SocketException {
      // Network/offline -> Fallback gracefully
      return await _fallbackToLocalParser(
        transcript: cleanText,
        businessType: businessType,
        rateMap: rateMap,
        errorMessage: 'Network unavailable. Extracted offline using your saved services.',
      );
    } catch (e) {
      // Any other error -> Fallback gracefully
      return await _fallbackToLocalParser(
        transcript: cleanText,
        businessType: businessType,
        rateMap: rateMap,
        errorMessage: 'Extraction service error: $e. Used local extraction.',
      );
    }
  }

  /// Resilient fallback to deterministic local parser so site work is NEVER lost.
  /// Runs with the generic fallback enabled: number-bearing phrases outside
  /// the user's service list become review-flagged provisional items, and
  /// anything else becomes an explicit unknown carrying the warning text.
  static Future<ExtractionResult> _fallbackToLocalParser({
    required String transcript,
    required BusinessType businessType,
    required Map<String, int> rateMap,
    String? errorMessage,
  }) async {
    const parser = TranscriptParser();
    final services =
        await ServiceItemRepository.getActiveForBusinessType(businessType);
    final parseResult = parser.parse(
      transcript,
      services: services,
      savedRates: rateMap,
      genericFallback: true,
    );

    final items = parseResult.items.where((pi) => !pi.isUnknown).map((pi) {
      // Match back to the user's service id (the parser carries it when known).
      final serviceId = pi.serviceItemId ?? 'custom_item';
      final savedRate = rateMap[serviceId];
      final rateFromSaved = savedRate != null && pi.unitRatePaise == savedRate;

      return ExtractedItem(
        serviceItemId: serviceId,
        description: pi.description,
        quantity: pi.quantity.toDouble(),
        unit: pi.unit,
        unitRatePaise: pi.unitRatePaise,
        rateSource: rateFromSaved ? ExtractedRateSource.rateMemory : ExtractedRateSource.unknown,
        confidence: 0.9,
      );
    }).toList();

    final unknowns = parseResult.warnings.map((w) {
      return ExplicitUnknown(
        text: w,
        reason: w,
      );
    }).toList();

    // Provisional generic items surface as suggestions: one-tap review
    // candidates, never silently priced.
    final suggested = parseResult.items.where((pi) => pi.isUnknown).map((pi) {
      return SuggestedItem(
        proposedName: pi.description,
        quantity: pi.quantity.toDouble() > 0 ? pi.quantity.toDouble() : 1.0,
        unit: pi.unit,
        rateHintPaise: pi.unitRatePaise,
        sourceSpan: transcript.length > 60
            ? '${transcript.substring(0, 57)}...'
            : transcript,
      );
    }).toList();

    return ExtractionResult(
      businessType: businessType.name,
      lineItems: items,
      unknowns: unknowns,
      suggestedItems: suggested,
      requiresReview: true,
      isFromLocalFallback: true,
      errorMessage: errorMessage,
    );
  }
}

import '../models/quote.dart';

/// Provenance of the rate assigned to an extracted item.
enum ExtractedRateSource { rateMemory, suggested, unknown }

/// Extracted candidate line item returned from extraction API or local fallback.
class ExtractedItem {
  final String catalogItemId;
  final String description;
  final double quantity;
  final String unit;
  final int unitRatePaise;
  final ExtractedRateSource rateSource;
  final double confidence;
  final String? sourceSpan;
  final String? uncertaintyNote;

  const ExtractedItem({
    required this.catalogItemId,
    required this.description,
    required this.quantity,
    required this.unit,
    this.unitRatePaise = 0,
    this.rateSource = ExtractedRateSource.unknown,
    this.confidence = 0.95,
    this.sourceSpan,
    this.uncertaintyNote,
  });

  /// Converts this candidate item into an immutable QuoteLineItem for client calculations.
  QuoteLineItem toQuoteLineItem() {
    return QuoteLineItem(
      description: description,
      quantity: quantity.round(),
      unit: unit,
      unitRatePaise: unitRatePaise,
      confidence: confidence,
      uncertaintyNote: uncertaintyNote,
      sourceSpan: sourceSpan,
      requiresReview:
          confidence < 0.8 ||
          unitRatePaise <= 0 ||
          rateSource == ExtractedRateSource.suggested ||
          uncertaintyNote != null,
    );
  }

  factory ExtractedItem.fromJson(Map<String, dynamic> json) {
    ExtractedRateSource source = ExtractedRateSource.unknown;
    final srcStr = (json['rateSource'] as String? ?? '').toUpperCase();
    if (srcStr.contains('RATE_MEMORY')) {
      source = ExtractedRateSource.rateMemory;
    } else if (srcStr.contains('SUGGESTED')) {
      source = ExtractedRateSource.suggested;
    }

    final rawQty = json['quantity'];
    double qty = 1.0;
    if (rawQty is num) {
      qty = rawQty.toDouble();
    } else if (rawQty is String) {
      qty = double.tryParse(rawQty) ?? 1.0;
    }

    final rawRate = json['unitRatePaise'];
    int ratePaise = 0;
    if (rawRate is num) {
      ratePaise = rawRate.toInt();
    } else if (rawRate is String) {
      ratePaise = int.tryParse(rawRate) ?? 0;
    }

    return ExtractedItem(
      catalogItemId: json['catalogItemId'] as String? ?? 'item',
      description: json['description'] as String? ?? 'Unnamed item',
      quantity: qty > 0 ? qty : 1.0,
      unit: json['unit'] as String? ?? 'sq ft',
      unitRatePaise: ratePaise,
      rateSource: source,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.9,
      sourceSpan: json['sourceSpan'] != null
          ? (json['sourceSpan'] is Map
                ? json['sourceSpan']['text'] as String?
                : json['sourceSpan'].toString())
          : null,
      uncertaintyNote: json['uncertaintyNote'] as String?,
    );
  }
}

/// Explicit unknown / uncataloged item identified from transcript.
class ExplicitUnknown {
  final String text;
  final String? suspectedTerm;
  final String reason;
  final double confidence;

  const ExplicitUnknown({
    required this.text,
    this.suspectedTerm,
    required this.reason,
    this.confidence = 0.5,
  });

  factory ExplicitUnknown.fromJson(Map<String, dynamic> json) {
    return ExplicitUnknown(
      text:
          json['text'] as String? ??
          json['sourceSpan'] as String? ??
          'Unknown work',
      suspectedTerm: json['suspectedTerm'] as String?,
      reason:
          json['reason'] as String? ?? 'Item not recognized in trade catalog',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }

  QuoteLineItem toQuoteLineItem() {
    return QuoteLineItem(
      description: suspectedTerm?.trim().isNotEmpty == true
          ? suspectedTerm!.trim()
          : text,
      quantity: 0,
      unit: 'item',
      unitRatePaise: 0,
      confidence: confidence,
      uncertaintyNote: reason,
      isUnknown: true,
      requiresReview: true,
    );
  }
}

/// Complete response produced by extraction service.
class ExtractionResult {
  final String trade;
  final List<ExtractedItem> lineItems;
  final List<ExplicitUnknown> unknowns;
  final bool requiresReview;
  final bool isFromLocalFallback;
  final String? errorMessage;

  const ExtractionResult({
    required this.trade,
    required this.lineItems,
    this.unknowns = const [],
    this.requiresReview = true,
    this.isFromLocalFallback = false,
    this.errorMessage,
  });

  bool get hasItems => lineItems.isNotEmpty;
  bool get hasUnknowns => unknowns.isNotEmpty;
}

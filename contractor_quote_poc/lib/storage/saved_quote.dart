import '../catalog/catalog.dart';
import '../models/quote.dart';

/// Day 9 — Persistent representation of a generated or drafted quotation.
///
/// Stores all metadata, line items, customer details, and original transcript
/// in a serializable format for local persistence via SharedPreferences.
class SavedQuote {
  final String id;
  final String quoteNumber;
  final DateTime createdAt;
  final Trade? trade;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final int validityDays;
  final String notes;
  final String? originalTranscript;
  final List<String> reviewWarnings;
  final bool reviewWarningsAcknowledged;
  final List<QuoteLineItem> lineItems;
  final int? gstPercent;
  final String? pdfPath;
  final String status;

  const SavedQuote({
    required this.id,
    required this.quoteNumber,
    required this.createdAt,
    this.trade,
    required this.customerName,
    this.customerPhone = '',
    this.customerAddress = '',
    this.validityDays = 15,
    this.notes = '',
    this.originalTranscript,
    this.reviewWarnings = const [],
    this.reviewWarningsAcknowledged = false,
    required this.lineItems,
    this.gstPercent,
    this.pdfPath,
    this.status = 'needsReview',
  });

  /// Converts this saved record back into an immutable domain [Quote].
  Quote toQuote() => Quote(
    customer: Customer(
      name: customerName,
      phone: customerPhone,
      address: customerAddress,
    ),
    lineItems: lineItems,
    gstPercent: gstPercent,
    originalTranscript: originalTranscript,
    reviewWarnings: reviewWarnings,
    reviewWarningsAcknowledged: reviewWarningsAcknowledged,
  );

  /// Computes totals on demand.
  QuoteTotals get totals => calculateTotals(toQuote());

  int get grandTotalPaise => totals.grandTotalPaise;
  int get grandTotalRupees => grandTotalPaise ~/ 100;

  SavedQuote copyWith({
    String? id,
    String? quoteNumber,
    DateTime? createdAt,
    Trade? trade,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    int? validityDays,
    String? notes,
    String? originalTranscript,
    List<String>? reviewWarnings,
    bool? reviewWarningsAcknowledged,
    List<QuoteLineItem>? lineItems,
    int? gstPercent,
    String? pdfPath,
    String? status,
  }) {
    return SavedQuote(
      id: id ?? this.id,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      createdAt: createdAt ?? this.createdAt,
      trade: trade ?? this.trade,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      validityDays: validityDays ?? this.validityDays,
      notes: notes ?? this.notes,
      originalTranscript: originalTranscript ?? this.originalTranscript,
      reviewWarnings: reviewWarnings ?? this.reviewWarnings,
      reviewWarningsAcknowledged:
          reviewWarningsAcknowledged ?? this.reviewWarningsAcknowledged,
      lineItems: lineItems ?? this.lineItems,
      gstPercent: gstPercent ?? this.gstPercent,
      pdfPath: pdfPath ?? this.pdfPath,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'quoteNumber': quoteNumber,
    'createdAt': createdAt.toIso8601String(),
    'trade': trade?.name,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerAddress': customerAddress,
    'validityDays': validityDays,
    'notes': notes,
    'originalTranscript': originalTranscript,
    'reviewWarnings': reviewWarnings,
    'reviewWarningsAcknowledged': reviewWarningsAcknowledged,
    'status': status,
    'lineItems': lineItems
        .map(
          (item) => {
            'description': item.description,
            'quantity': item.quantity,
            'unit': item.unit,
            'unitRatePaise': item.unitRatePaise,
            'confidence': item.confidence,
            'uncertaintyNote': item.uncertaintyNote,
            'sourceSpan': item.sourceSpan,
            'isUnknown': item.isUnknown,
            'requiresReview': item.requiresReview,
            'acknowledged': item.acknowledged,
          },
        )
        .toList(),
    'gstPercent': gstPercent,
    'pdfPath': pdfPath,
  };

  factory SavedQuote.fromJson(Map<String, dynamic> json) {
    Trade? parsedTrade;
    if (json['trade'] != null) {
      final tStr = json['trade'] as String;
      parsedTrade = Trade.values.cast<Trade?>().firstWhere(
        (t) => t?.name == tStr,
        orElse: () => null,
      );
    }

    final rawItems = (json['lineItems'] as List<dynamic>? ?? const []);
    final items = rawItems.map((raw) {
      final m = raw as Map<String, dynamic>;
      final rawQuantity = m['quantity'];
      final rawRate = m['unitRatePaise'];
      return QuoteLineItem(
        description: m['description'] as String? ?? 'Item',
        quantity: rawQuantity is num
            ? rawQuantity.toInt()
            : int.tryParse(rawQuantity as String? ?? '') ?? 1,
        unit: m['unit'] as String? ?? 'unit',
        unitRatePaise: rawRate is num
            ? rawRate.toInt()
            : int.tryParse(rawRate as String? ?? '') ?? 0,
        confidence: (m['confidence'] as num?)?.toDouble(),
        uncertaintyNote: m['uncertaintyNote'] as String?,
        sourceSpan: m['sourceSpan'] as String?,
        isUnknown: m['isUnknown'] as bool? ?? false,
        requiresReview: m['requiresReview'] as bool? ?? false,
        acknowledged: m['acknowledged'] as bool? ?? false,
      );
    }).toList();

    final rawWarnings = json['reviewWarnings'] as List<dynamic>? ?? const [];
    final reviewWarnings = rawWarnings.whereType<String>().toList(
      growable: false,
    );

    return SavedQuote(
      id:
          json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      quoteNumber: json['quoteNumber'] as String? ?? 'Q-2026-001',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      trade: parsedTrade,
      customerName: json['customerName'] as String? ?? 'Client',
      customerPhone: json['customerPhone'] as String? ?? '',
      customerAddress: json['customerAddress'] as String? ?? '',
      validityDays: json['validityDays'] as int? ?? 15,
      notes: json['notes'] as String? ?? '',
      originalTranscript: json['originalTranscript'] as String?,
      reviewWarnings: reviewWarnings,
      reviewWarningsAcknowledged:
          json['reviewWarningsAcknowledged'] as bool? ?? false,
      lineItems: items,
      gstPercent: json['gstPercent'] as int?,
      pdfPath: json['pdfPath'] as String?,
      status: json['status'] as String? ?? 'needsReview',
    );
  }
}

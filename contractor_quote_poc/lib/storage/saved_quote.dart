import '../templates/template_data.dart';
import '../models/quote.dart';

/// Day 9 — Persistent representation of a generated or drafted quotation.
///
/// Stores all metadata, line items, customer details, and original transcript
/// in a serializable format for local persistence via SharedPreferences.
class SavedQuote {
  /// Immutable local ID (UUID v4) — the idempotency anchor. Never changes.
  final String id;

  /// Local human-readable label (e.g. Q-2026-A3F9). Not gap-free.
  final String quoteNumber;

  /// Day 15: assigned by the backend on first successful sync. Null while
  /// offline. UI/PDF prefer this when present, else [quoteNumber].
  final String? serverDisplayNumber;

  /// Idempotency key sent with every write; defaults to [id].
  final String idempotencyKey;

  final DateTime createdAt;

  /// Day 15 commercial date (defaults to [createdAt] when null).
  final DateTime? quoteDate;
  final BusinessType? businessType;

  /// Free-text business name snapshot (only set when [businessType] is
  /// [BusinessType.other]). Printed on the PDF and history badge so custom
  /// trades appear in the user's own words. Empty for template types.
  final String businessTypeLabel;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final int validityDays;

  /// Day 15: optional advance, e.g. 50 → "50% advance".
  final int? advancePercent;
  final String advanceText;
  final String notes;

  /// Day 15: custom terms (empty → PDF uses [kDefaultQuoteTerms]).
  final List<String> terms;

  final String? originalTranscript;
  final List<String> reviewWarnings;
  final bool reviewWarningsAcknowledged;
  final List<QuoteLineItem> lineItems;
  final int? gstPercent;
  final String? pdfPath;
  final String status;

  /// Day 16: Record version for optimistic concurrency and conflict detection.
  final int version;

  const SavedQuote({
    required this.id,
    required this.quoteNumber,
    required this.createdAt,
    this.serverDisplayNumber,
    String? idempotencyKey,
    this.quoteDate,
    this.businessType,
    this.businessTypeLabel = '',
    required this.customerName,
    this.customerPhone = '',
    this.customerAddress = '',
    this.validityDays = 15,
    this.advancePercent,
    this.advanceText = '',
    this.notes = '',
    this.terms = const [],
    this.originalTranscript,
    this.reviewWarnings = const [],
    this.reviewWarningsAcknowledged = false,
    required this.lineItems,
    this.gstPercent,
    this.pdfPath,
    this.status = 'needsReview',
    this.version = 1,
  }) : idempotencyKey = idempotencyKey ?? id;

  /// Number shown on screen/PDF: backend value wins when synced.
  String get displayNumber => serverDisplayNumber ?? quoteNumber;

  /// Effective quote date for PDF/validity math.
  DateTime get effectiveDate => quoteDate ?? createdAt;

  /// Converts this saved record back into an immutable domain [Quote].
  Quote toQuote() => Quote(
    id: id,
    quoteNumber: quoteNumber,
    serverDisplayNumber: serverDisplayNumber,
    customer: Customer(
      name: customerName,
      phone: customerPhone,
      address: customerAddress,
    ),
    lineItems: lineItems,
    gstPercent: gstPercent,
    quoteDate: effectiveDate,
    validityDays: validityDays,
    advancePercent: advancePercent,
    advanceText: advanceText,
    notes: notes,
    terms: terms,
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
    String? serverDisplayNumber,
    String? idempotencyKey,
    DateTime? createdAt,
    DateTime? quoteDate,
    BusinessType? businessType,
    String? businessTypeLabel,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    int? validityDays,
    int? advancePercent,
    String? advanceText,
    String? notes,
    List<String>? terms,
    String? originalTranscript,
    List<String>? reviewWarnings,
    bool? reviewWarningsAcknowledged,
    List<QuoteLineItem>? lineItems,
    int? gstPercent,
    String? pdfPath,
    String? status,
    int? version,
  }) {
    return SavedQuote(
      id: id ?? this.id,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      serverDisplayNumber: serverDisplayNumber ?? this.serverDisplayNumber,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      createdAt: createdAt ?? this.createdAt,
      quoteDate: quoteDate ?? this.quoteDate,
      businessType: businessType ?? this.businessType,
      businessTypeLabel: businessTypeLabel ?? this.businessTypeLabel,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      validityDays: validityDays ?? this.validityDays,
      advancePercent: advancePercent ?? this.advancePercent,
      advanceText: advanceText ?? this.advanceText,
      notes: notes ?? this.notes,
      terms: terms ?? this.terms,
      originalTranscript: originalTranscript ?? this.originalTranscript,
      reviewWarnings: reviewWarnings ?? this.reviewWarnings,
      reviewWarningsAcknowledged:
          reviewWarningsAcknowledged ?? this.reviewWarningsAcknowledged,
      lineItems: lineItems ?? this.lineItems,
      gstPercent: gstPercent ?? this.gstPercent,
      pdfPath: pdfPath ?? this.pdfPath,
      status: status ?? this.status,
      version: version ?? this.version,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'quoteNumber': quoteNumber,
    'serverDisplayNumber': serverDisplayNumber,
    'idempotencyKey': idempotencyKey,
    // Wire contract: the API parses timestamps as Instant, which requires
    // an explicit zone. Local ISO without zone ("...T19:23:02.101410") is
    // rejected with 400 and sync silently never completes — always UTC.
    'createdAt': createdAt.toUtc().toIso8601String(),
    'quoteDate': quoteDate?.toIso8601String(),
    'business_type': businessType?.name,
    'business_type_label': businessTypeLabel,
    // Local names are kept for on-device storage; server-named aliases
    // follow so the API (clientName, displayNumber, …) binds correctly.
    // displayNumber carries ONLY the backend value (null on first sync so
    // the server assigns one); the local label stays in quoteNumber.
    'customerName': customerName,
    'clientName': customerName,
    'customerPhone': customerPhone,
    'clientPhone': customerPhone,
    'customerAddress': customerAddress,
    'siteAddress': customerAddress,
    'displayNumber': serverDisplayNumber,
    'validityDays': validityDays,
    'advancePercent': advancePercent,
    'advanceText': advanceText,
    'notes': notes,
    'terms': terms,
    'originalTranscript': originalTranscript,
    'reviewWarnings': reviewWarnings,
    'reviewWarningsAcknowledged': reviewWarningsAcknowledged,
    'status': status,
    'version': version,
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
            'serviceItemId': item.serviceItemId,
          },
        )
        .toList(),
    'gstPercent': gstPercent,
    // Server keeps its own copy of the money (defaults to 0 when absent).
    // Always recomputed here by the Day-5 engine — never model-supplied.
    'subtotalPaise': totals.subtotalPaise,
    'gstPaise': totals.gstPaise,
    'grandTotalPaise': totals.grandTotalPaise,
    'pdfPath': pdfPath,
  };

  factory SavedQuote.fromJson(Map<String, dynamic> json) {
    BusinessType? parsedTrade;
    if (json['business_type'] != null) {
      final tStr = json['business_type'] as String;
      parsedTrade = BusinessType.values.cast<BusinessType?>().firstWhere(
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
        serviceItemId: m['serviceItemId'] as String?,
      );
    }).toList();

    final rawWarnings = json['reviewWarnings'] as List<dynamic>? ?? const [];
    final reviewWarnings = rawWarnings.whereType<String>().toList(
      growable: false,
    );

    final rawTerms = json['terms'] as List<dynamic>? ?? const [];
    return SavedQuote(
      id:
          json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      quoteNumber: json['quoteNumber'] as String? ?? 'Q-2026-001',
      serverDisplayNumber: json['serverDisplayNumber'] as String?,
      idempotencyKey: json['idempotencyKey'] as String? ?? json['id'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      quoteDate: json['quoteDate'] != null
          ? DateTime.tryParse(json['quoteDate'] as String)
          : null,
      businessType: parsedTrade,
      businessTypeLabel: json['business_type_label'] as String? ?? '',
      customerName: json['customerName'] as String? ?? 'Client',
      customerPhone: json['customerPhone'] as String? ?? '',
      customerAddress: json['customerAddress'] as String? ?? '',
      validityDays: json['validityDays'] as int? ?? 15,
      advancePercent: json['advancePercent'] as int?,
      advanceText: json['advanceText'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      terms: rawTerms.whereType<String>().toList(growable: false),
      originalTranscript: json['originalTranscript'] as String?,
      reviewWarnings: reviewWarnings,
      reviewWarningsAcknowledged:
          json['reviewWarningsAcknowledged'] as bool? ?? false,
      lineItems: items,
      gstPercent: json['gstPercent'] as int?,
      pdfPath: json['pdfPath'] as String?,
      status: json['status'] as String? ?? 'needsReview',
      version: json['version'] as int? ?? 1,
    );
  }
}

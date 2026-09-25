class Customer {
  final String name;
  final String phone;
  final String address;

  const Customer({required this.name, this.phone = '', this.address = ''});
}

class QuoteLineItem {
  final String description;
  final int quantity;
  final String unit;
  final int unitRatePaise;
  final double? confidence;
  final String? uncertaintyNote;
  final String? sourceSpan;
  final bool isUnknown;
  final bool requiresReview;
  final bool acknowledged;

  const QuoteLineItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitRatePaise,
    this.confidence,
    this.uncertaintyNote,
    this.sourceSpan,
    this.isUnknown = false,
    this.requiresReview = false,
    this.acknowledged = false,
  }) : assert(quantity >= 0),
       assert(unitRatePaise >= 0);
}

/// Day 15 default commercial terms (used when a quote has no custom terms).
/// Kept small on purpose: validity line is generated from [Quote.validityDays].
const List<String> kDefaultQuoteTerms = [
  'Water and electricity to be provided by client at site.',
  'Rates are for standard execution as per industry norms.',
  'Extra work or material changes will be billed on actuals.',
];

class Quote {
  /// Day 15 identity: immutable local ID (idempotency anchor) + human labels.
  final String? id;
  final String? quoteNumber;
  final String? serverDisplayNumber;

  final Customer customer;
  final List<QuoteLineItem> lineItems;
  final int? gstPercent;

  /// Day 15 commercial fields — all optional so a quote works with only
  /// client name + line items. They render in the PDF only when supplied.
  final DateTime? quoteDate;
  final int validityDays;
  final int? advancePercent;
  final String advanceText;
  final String notes;
  final List<String> terms;

  final String? originalTranscript;
  final List<String> reviewWarnings;
  final bool reviewWarningsAcknowledged;

  Quote({
    this.id,
    this.quoteNumber,
    this.serverDisplayNumber,
    required this.customer,
    required List<QuoteLineItem> lineItems,
    this.gstPercent,
    this.quoteDate,
    this.validityDays = 15,
    this.advancePercent,
    this.advanceText = '',
    this.notes = '',
    List<String> terms = const [],
    this.originalTranscript,
    List<String> reviewWarnings = const [],
    this.reviewWarningsAcknowledged = false,
  }) : assert(gstPercent == null || (gstPercent >= 0 && gstPercent <= 100)),
        assert(validityDays > 0),
        assert(advancePercent == null ||
            (advancePercent >= 0 && advancePercent <= 100)),
        lineItems = List.unmodifiable(lineItems),
        terms = List.unmodifiable(terms),
        reviewWarnings = List.unmodifiable(reviewWarnings);

  /// Number shown on screen/PDF: backend value wins when synced, else local quoteNumber.
  String get displayNumber => serverDisplayNumber ?? quoteNumber ?? 'Q-2026-0001';

  /// Effective advance description.
  String get effectiveAdvanceText {
    if (advanceText.trim().isNotEmpty) return advanceText.trim();
    if (advancePercent != null && advancePercent! > 0) {
      return '$advancePercent% advance payment';
    }
    return '';
  }

  /// Effective terms for the PDF: custom terms when supplied, else defaults.
  List<String> get effectiveTerms => terms.isEmpty ? kDefaultQuoteTerms : terms;
}

class QuoteTotals {
  final List<int> lineAmountsPaise;
  final int subtotalPaise;
  final int gstPaise;
  final int grandTotalPaise;

  const QuoteTotals({
    required this.lineAmountsPaise,
    required this.subtotalPaise,
    required this.gstPaise,
    required this.grandTotalPaise,
  });
}

int calculateAmount(QuoteLineItem item) => item.quantity * item.unitRatePaise;

QuoteTotals calculateTotals(Quote quote) {
  final lineAmountsPaise = [
    for (final item in quote.lineItems) calculateAmount(item),
  ];
  final subtotalPaise = lineAmountsPaise.fold<int>(
    0,
    (total, amount) => total + amount,
  );
  final gstPaise = quote.gstPercent == null
      ? 0
      // GST is rounded half up to the nearest whole paise.
      : (subtotalPaise * quote.gstPercent! + 50) ~/ 100;

  return QuoteTotals(
    lineAmountsPaise: List.unmodifiable(lineAmountsPaise),
    subtotalPaise: subtotalPaise,
    gstPaise: gstPaise,
    grandTotalPaise: subtotalPaise + gstPaise,
  );
}

String? quotePdfBlockingReason(Quote quote) {
  if (quote.lineItems.isEmpty) {
    return 'Add at least one line item before creating the PDF.';
  }

  for (var index = 0; index < quote.lineItems.length; index++) {
    final item = quote.lineItems[index];
    final label = item.description.trim().isEmpty
        ? 'item ${index + 1}'
        : item.description.trim();

    if (item.description.trim().isEmpty) {
      return 'Enter an item name for item ${index + 1} before creating the PDF.';
    }
    if (item.quantity <= 0) {
      return 'Enter a quantity greater than 0 for "$label" before creating the PDF.';
    }
    if (item.unit.trim().isEmpty) {
      return 'Enter a unit for "$label" before creating the PDF.';
    }
    if (item.unitRatePaise <= 0) {
      return 'Enter a rate greater than 0 for "$label" before creating the PDF.';
    }
    if (item.requiresReview && !item.acknowledged) {
      return 'Please check "$label" or mark it as checked before creating the PDF.';
    }
  }

  if (quote.reviewWarnings.isNotEmpty && !quote.reviewWarningsAcknowledged) {
    return 'Acknowledge the review message before creating the PDF.';
  }

  return null;
}

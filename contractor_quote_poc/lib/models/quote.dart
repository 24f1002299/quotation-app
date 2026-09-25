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

class Quote {
  final Customer customer;
  final List<QuoteLineItem> lineItems;
  final int? gstPercent;
  final String? originalTranscript;
  final List<String> reviewWarnings;
  final bool reviewWarningsAcknowledged;

  Quote({
    required this.customer,
    required List<QuoteLineItem> lineItems,
    this.gstPercent,
    this.originalTranscript,
    List<String> reviewWarnings = const [],
    this.reviewWarningsAcknowledged = false,
  }) : assert(gstPercent == null || (gstPercent >= 0 && gstPercent <= 100)),
       lineItems = List.unmodifiable(lineItems),
       reviewWarnings = List.unmodifiable(reviewWarnings);
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

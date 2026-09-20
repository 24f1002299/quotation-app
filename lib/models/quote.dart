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

  const QuoteLineItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitRatePaise,
  }) : assert(quantity >= 0),
       assert(unitRatePaise >= 0);
}

class Quote {
  final Customer customer;
  final List<QuoteLineItem> lineItems;
  final int? gstPercent;
  final String? originalTranscript;

  Quote({
    required this.customer,
    required List<QuoteLineItem> lineItems,
    this.gstPercent,
    this.originalTranscript,
  }) : assert(gstPercent == null || (gstPercent >= 0 && gstPercent <= 100)),
       lineItems = List.unmodifiable(lineItems);
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

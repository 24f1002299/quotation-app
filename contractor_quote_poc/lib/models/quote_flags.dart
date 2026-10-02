import 'quote.dart';

/// Day 20 — Explicit uncertainty / error flags.
///
/// Goal: a bad quote must never look confident. Every doubtful value gets
/// an explicit flag with a plain-language message and a concrete next action.
/// Only [isBlocking] flags stop PDF generation; the rest warn but allow it.
enum QuoteFlagType {
  unknownItem,
  uncertainQuantity,
  missingRate,
  unusualRate,
  missingCustomer,
  failedSync,
  staleServiceList,
}

/// One explainable problem on a quote.
class QuoteFlag {
  final QuoteFlagType type;
  final int? itemIndex;
  final String itemLabel;
  final String message;
  final String actionLabel;
  final bool isBlocking;

  const QuoteFlag({
    required this.type,
    this.itemIndex,
    this.itemLabel = '',
    required this.message,
    required this.actionLabel,
    required this.isBlocking,
  });

  @override
  String toString() => 'QuoteFlag($type, item=$itemLabel, blocking=$isBlocking)';
}

/// Expected (saved/seed) rate per rupee for unusual-rate detection.
/// Mirrors the seed rates in ServiceItemRepository so the check is pure and
/// unit-testable without SharedPreferences.
int expectedRateRupeesForDescription(String description) {
  final d = description.toLowerCase();
  if (d.contains('skirting') || d.contains('स्कर्टिंग')) return 60;
  if (d.contains('waterproof') || d.contains('वॉटरप्रूफ')) return 25;
  if (d.contains('putty') || d.contains('पुट्टी') || d.contains('पट्टी')) {
    return 18;
  }
  if (d.contains('primer') || d.contains('प्राइमर')) return 8;
  if (d.contains('paint') || d.contains('पेंट') || d.contains('रंगाई')) {
    return 12;
  }
  if (d.contains('tile') ||
      d.contains('टाइल') ||
      d.contains('टाईल') ||
      d.contains('floor')) {
    return 45;
  }
  return 0; // no baseline → never flag as unusual
}

/// Pure unusual-rate check: true when [rateRupees] is more than 2x or less
/// than half of [expectedRupees]. Zero/unknown baselines never flag.
bool isUnusualRate(int rateRupees, int expectedRupees) {
  if (expectedRupees <= 0 || rateRupees <= 0) return false;
  return rateRupees > expectedRupees * 2 || rateRupees * 2 < expectedRupees;
}

/// Placeholder names that mean "customer not entered yet".
bool isMissingCustomerName(String name) {
  final t = name.trim().toLowerCase();
  return t.isEmpty || t == 'client' || t == 'valued client';
}

/// Line-item level flags (unknown, quantity, rates).
///
/// [expectedRateFor] lets callers inject saved-rate lookups; defaults to the
/// seed baseline above so tests stay pure.
List<QuoteFlag> analyzeLineItems(
  Quote quote, {
  int Function(String description)? expectedRateFor,
}) {
  final flags = <QuoteFlag>[];
  final rateFor = expectedRateFor ?? expectedRateRupeesForDescription;

  for (var i = 0; i < quote.lineItems.length; i++) {
    final item = quote.lineItems[i];
    final label = item.description.trim().isEmpty
        ? 'item ${i + 1}'
        : item.description.trim();
    final acknowledged = item.acknowledged;

    // 1. Unknown item — blocking until resolved or explicitly checked.
    if (item.isUnknown && !acknowledged) {
      final note = item.uncertaintyNote?.trim();
      flags.add(QuoteFlag(
        type: QuoteFlagType.unknownItem,
        itemIndex: i,
        itemLabel: label,
        message: note == null || note.isEmpty
            ? 'Unknown item: "$label" is not in the catalog. Check the work and fix its details.'
            : 'Unknown item: "$label" — $note',
        actionLabel: 'Fix now',
        isBlocking: true,
      ));
    }

    // 2. Uncertain quantity — qty<=0 always blocking; low-confidence or
    // quantity-note blocks until checked.
    final qtyNote = (item.uncertaintyNote ?? '').toLowerCase();
    final qtyMentioned =
        qtyNote.contains('quant') || qtyNote.contains('मात्रा');
    final lowConfidence =
        item.confidence != null && item.confidence! < 0.8;
    if (item.quantity <= 0) {
      flags.add(QuoteFlag(
        type: QuoteFlagType.uncertainQuantity,
        itemIndex: i,
        itemLabel: label,
        message:
            'Enter a quantity greater than 0 for "$label" before creating the PDF.',
        actionLabel: 'Add quantity',
        isBlocking: true,
      ));
    } else if (!acknowledged &&
        (qtyMentioned || (lowConfidence && item.requiresReview))) {
      flags.add(QuoteFlag(
        type: QuoteFlagType.uncertainQuantity,
        itemIndex: i,
        itemLabel: label,
        // Keep the 'Please check "<label>"' prefix so the Day 14 gate
        // message stays recognizable; detail follows after the dash.
        message: 'Please check "$label" — quantity needs checking.',
        actionLabel: 'Review item',
        isBlocking: true,
      ));
    }

    // 3. Missing rate — blocking.
    if (item.unitRatePaise <= 0) {
      flags.add(QuoteFlag(
        type: QuoteFlagType.missingRate,
        itemIndex: i,
        itemLabel: label,
        message: 'Add a rate for "$label" before creating the PDF.',
        actionLabel: 'Add rate',
        isBlocking: true,
      ));
    } else {
      // 4. Unusual rate — warn only, never blocks.
      final rateRupees = item.unitRatePaise ~/ 100;
      final expected = rateFor(item.description);
      if (isUnusualRate(rateRupees, expected)) {
        flags.add(QuoteFlag(
          type: QuoteFlagType.unusualRate,
          itemIndex: i,
          itemLabel: label,
          message:
              'Rate ₹$rateRupees for "$label" looks unusual (usual ~₹$expected). Please confirm.',
          actionLabel: 'Confirm rate',
          isBlocking: false,
        ));
      }
    }

    // Generic requiresReview that wasn't covered above (e.g. suggested rate
    // with good confidence) — blocking until checked.
    final alreadyFlaggedBlocking = flags.any(
      (f) => f.itemIndex == i && f.isBlocking,
    );
    if (item.requiresReview && !acknowledged && !alreadyFlaggedBlocking) {
      flags.add(QuoteFlag(
        type: QuoteFlagType.uncertainQuantity,
        itemIndex: i,
        itemLabel: label,
        message: 'Please check "$label" or mark it as checked before creating the PDF.',
        actionLabel: 'Review item',
        isBlocking: true,
      ));
    }
  }
  return flags;
}

/// Quote-level flags: missing customer (warn), failed sync (warn + retry),
/// stale catalog (warn + refresh). Never blocking — work is preserved and
/// the PDF stays available.
List<QuoteFlag> analyzeQuoteLevel(
  Quote quote, {
  bool hasSyncFailure = false,
  String syncDetail = '',
  bool isServiceListStale = false,
  String serviceListDetail = '',
}) {
  final flags = <QuoteFlag>[];

  // 5. Missing customer.
  if (isMissingCustomerName(quote.customer.name)) {
    flags.add(const QuoteFlag(
      type: QuoteFlagType.missingCustomer,
      message:
          'Add the customer name so the PDF does not go out as "Valued Client".',
      actionLabel: 'Add customer',
      isBlocking: false,
    ));
  }

  // 6. Failed sync — work stays on the phone, retry offered.
  if (hasSyncFailure) {
    flags.add(QuoteFlag(
      type: QuoteFlagType.failedSync,
      message: syncDetail.trim().isNotEmpty
          ? 'Couldn\u2019t sync changes. They remain saved on this phone. ($syncDetail)'
          : 'Couldn\u2019t sync changes. They remain saved on this phone.',
      actionLabel: 'Retry',
      isBlocking: false,
    ));
  }

  // 7. Stale catalog — rates/items may be outdated.
  if (isServiceListStale) {
    flags.add(QuoteFlag(
      type: QuoteFlagType.staleServiceList,
      message: serviceListDetail.trim().isNotEmpty
          ? 'Rate list may be outdated. $serviceListDetail'
          : 'Rate list may be outdated. Refresh when online to get latest items.',
      actionLabel: 'Refresh',
      isBlocking: false,
    ));
  }

  return flags;
}

/// All flags for a quote (line-item + quote-level).
List<QuoteFlag> analyzeQuote(
  Quote quote, {
  int Function(String description)? expectedRateFor,
  bool hasSyncFailure = false,
  String syncDetail = '',
  bool isServiceListStale = false,
  String serviceListDetail = '',
}) {
  return [
    ...analyzeLineItems(quote, expectedRateFor: expectedRateFor),
    ...analyzeQuoteLevel(
      quote,
      hasSyncFailure: hasSyncFailure,
      syncDetail: syncDetail,
      isServiceListStale: isServiceListStale,
      serviceListDetail: serviceListDetail,
    ),
  ];
}

/// Blocking flags only — these stop PDF generation.
List<QuoteFlag> blockingFlags(List<QuoteFlag> flags) =>
    flags.where((f) => f.isBlocking).toList(growable: false);

/// Warning flags only — shown but do not stop the PDF.
List<QuoteFlag> warningFlags(List<QuoteFlag> flags) =>
    flags.where((f) => !f.isBlocking).toList(growable: false);

/// First blocking message for the PDF gate, or null when ready.
String? pdfBlockingReasonFromFlags(List<QuoteFlag> flags) {
  final blocking = blockingFlags(flags);
  if (blocking.isEmpty) return null;
  return blocking.first.message;
}

/// Deterministic, rule-based transcript parser.
///
/// Input:  a raw transcript string (voice or typed) plus the user's own
///         [ServiceItem] list — the services they sell are what the parser
///         recognises. There is no bundled catalog any more.
/// Output: [ParseResult] — a list of [ParsedLineItem]s and human-readable
///         [warnings] for anything the parser cannot confidently identify.
///
/// The parser NEVER fabricates an amount.  When it cannot extract a quantity
/// or rate for a recognised service it emits a warning and returns 0 for the
/// missing field so the user can fill it in on the review screen.
///
/// Pure Dart — no Flutter import — so it can be tested without a widget tree.
library;

import '../models/quote.dart';
import '../models/service_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public output types
// ─────────────────────────────────────────────────────────────────────────────

/// A single line item produced by the parser.
class ParsedLineItem {
  final String description; // the user's service name
  final int quantity;
  final String unit;
  final int unitRatePaise; // rate × 100 (no floating point)

  /// Id of the matched [ServiceItem]; null when nothing matched.
  final String? serviceItemId;

  const ParsedLineItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitRatePaise,
    this.serviceItemId,
  });

  /// Convert to the immutable model used by the calculation layer.
  QuoteLineItem toQuoteLineItem() => QuoteLineItem(
        description: description,
        quantity: quantity,
        unit: unit,
        unitRatePaise: unitRatePaise,
        serviceItemId: serviceItemId,
      );
}

/// The complete result of one [TranscriptParser.parse] call.
class ParseResult {
  final List<ParsedLineItem> items;
  final List<String> warnings;

  const ParseResult({required this.items, required this.warnings});

  bool get hasWarnings => warnings.isNotEmpty;
  bool get isEmpty => items.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal: position of a matched service term inside normalized text
// ─────────────────────────────────────────────────────────────────────────────
class _ServiceMatch {
  final ServiceItem service;
  final int start; // inclusive char index in normalized text
  final int end; // exclusive char index

  const _ServiceMatch({
    required this.service,
    required this.start,
    required this.end,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Parser
// ─────────────────────────────────────────────────────────────────────────────

/// Stateless, deterministic transcript parser.  `const`-constructible so
/// tests can share a single instance across all cases.
class TranscriptParser {
  const TranscriptParser();

  /// Parse [transcript] into line items, matching against the user's
  /// [services] (name, localized names, and keywords).
  ///
  /// If [savedRates] (serviceItemId -> unitRatePaise) is provided and a rate is
  /// omitted from the transcript, the user's saved rate is applied.
  ParseResult parse(
    String transcript, {
    List<ServiceItem> services = const [],
    Map<String, int>? savedRates,
  }) {
    final text = _normalize(transcript);
    final matches = _findServiceMatches(text, services);

    // ── No service matched at all ──────────────────────────────────────────
    if (matches.isEmpty) {
      if (RegExp(r'\d').hasMatch(text)) {
        // Numbers present but nothing recognised → unrecognised item
        return const ParseResult(
          items: [],
          warnings: [
            'No services in your list match this. '
                'Please add line items manually.',
          ],
        );
      }
      // No numbers either — probably just preamble / empty transcript
      return const ParseResult(items: [], warnings: []);
    }

    // ── Extract one ParsedLineItem per matched service ──────────────────────
    final items = <ParsedLineItem>[];
    final warnings = <String>[];

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];

      // lookback: text before this match (from end of previous match)
      final prevEnd = i == 0 ? 0 : matches[i - 1].end;
      final lookback = text.substring(prevEnd, match.start);

      // lookahead: text after this match (up to start of next match)
      final nextStart =
          i + 1 < matches.length ? matches[i + 1].start : text.length;
      final lookahead = text.substring(match.end, nextStart);

      // Rate is almost always stated AFTER the item ("45 rupaye per foot").
      // Fall back to lookback only if lookahead has none.
      final rate = _findRate(lookahead) ?? _findRate(lookback);

      // Qty can be before ("850 sq ft tiles") or after ("skirting 120").
      // Prefer lookback; fall back to lookahead.
      final qty = _findQty(lookback, lookahead);

      final unit =
          _findUnit('$lookback $lookahead') ?? match.service.unit;

      // Saved rate provenance: if the rate was omitted in speech, use the
      // user's own saved rate for this service.
      int ratePaise = (rate != null) ? rate * 100 : 0;
      final savedRatePaise = savedRates?[match.service.id];
      final hasRateFromSaved =
          rate == null && savedRatePaise != null && savedRatePaise > 0;
      if (hasRateFromSaved) {
        ratePaise = savedRatePaise;
      }

      final hasRate = rate != null || hasRateFromSaved;
      if (qty == null || !hasRate) {
        final missingField = qty == null && !hasRate
            ? 'quantity and rate'
            : (qty == null ? 'quantity' : 'rate');
        warnings.add(
          'Could not fully extract details for "${match.service.name}" — '
          'please fill in the $missingField manually.',
        );
      }

      items.add(ParsedLineItem(
        description: match.service.name,
        quantity: qty ?? 0,
        unit: unit,
        unitRatePaise: ratePaise,
        serviceItemId: match.service.id,
      ));
    }

    return ParseResult(items: items, warnings: warnings);
  }

  // ── Text normalization ──────────────────────────────────────────────────

  String _normalize(String text) {
    return text
        .toLowerCase()
        // Devanagari digits (०-९) → ASCII digits (0-9)
        .replaceAllMapped(
          RegExp(r'[०-९]'),
          (m) => String.fromCharCode(
            m.group(0)!.codeUnitAt(0) - 0x0966 + 0x30,
          ),
        )
        // Strip punctuation; keep ASCII letters/digits, ₹, Devanagari letters
        .replaceAll(RegExp(r'[^\w\s₹\u0900-\u097F]'), ' ')
        // Collapse runs of whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Service matching ────────────────────────────────────────────────────

  /// Matches the transcript against each service's [ServiceItem.matchTerms].
  ///
  /// Terms are tried longest-first ("tile fixing labour" before "tile") and
  /// each service can be claimed at most once. Word boundaries are strict for
  /// BOTH Latin and Devanagari letters, so 'रंग' never matches inside
  /// 'औरंगाबाद'.
  List<_ServiceMatch> _findServiceMatches(String text, List<ServiceItem> services) {
    final matches = <_ServiceMatch>[];
    // Map char_position → service_id to prevent overlapping matches.
    final claimed = <int, String>{};

    final entries = <(String, ServiceItem)>[
      for (final service in services)
        for (final term in service.matchTerms) (term, service),
    ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

    for (final (term, service) in entries) {
      if (term.isEmpty) continue;
      // Each service appears at most once.
      if (matches.any((m) => m.service.id == service.id)) continue;

      int searchFrom = 0;
      while (searchFrom < text.length) {
        final pos = text.indexOf(term, searchFrom);
        if (pos == -1) break;
        final end = pos + term.length;

        final beforeOk = pos == 0 || !_isWordChar(text[pos - 1]);
        final afterOk = end >= text.length || !_isWordChar(text[end]);
        final overlaps =
            Iterable<int>.generate(term.length, (k) => pos + k).any(claimed.containsKey);

        if (beforeOk && afterOk && !overlaps) {
          matches.add(_ServiceMatch(service: service, start: pos, end: end));
          for (int k = pos; k < end; k++) {
            claimed[k] = service.id;
          }
          break;
        }
        searchFrom = pos + 1;
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  /// Latin word characters AND Devanagari letters/marks (U+0900–U+097F) both
  /// count as "inside a word".
  static bool _isWordChar(String ch) => RegExp(r'[\w\u0900-\u097F]').hasMatch(ch);

  // ── Rate extraction ─────────────────────────────────────────────────────

  // “45 rupaye” / “18 rupee” / “12 rupees” / “50 रुपये” / “भाव 55”
  static final _rateAfterNumber = RegExp(
    r'(\d+)\s*(?:rupaye|rupee|rupees|rupe|rate|bhav|\u0930\u0941\u092a\u092f\u0947|\u0930\u0941\u092a\u090f|\u092d\u093e\u0935)(?:\s|\b|$)',
  );
  // “₹45”
  static final _ratePrefixRupee = RegExp(r'₹\s*(\d+)');
  static final _ratePrefixWord = RegExp(
    r'(?:\b|(?<=[^\w]))(?:rate|bhav|\u092d\u093e\u0935)\s*[:=]?\s*(\d+)(?:\s|\b|$)',
  );

  int? _findRate(String text) {
    final m1 = _rateAfterNumber.firstMatch(text);
    if (m1 != null) return int.tryParse(m1.group(1)!);
    final m2 = _ratePrefixRupee.firstMatch(text);
    if (m2 != null) return int.tryParse(m2.group(1)!);
    final m3 = _ratePrefixWord.firstMatch(text);
    if (m3 != null) return int.tryParse(m3.group(1)!);
    return null;
  }

  // ── Quantity extraction ─────────────────────────────────────────────────

  int? _findQty(String lookback, String lookahead) {
    // Prefer lookback: "850 square foot tiles" → 850 is before item
    final fromLookback = _firstNonRateNumber(lookback);
    if (fromLookback != null) return fromLookback;
    // Fall back to lookahead: "skirting 120 running foot" → 120 is after item
    return _firstNonRateNumber(lookahead);
  }

  /// Returns the first integer in [text] that is NOT the leading digit group
  /// of a rate pattern (e.g. "45 rupaye").
  int? _firstNonRateNumber(String text) {
    // Collect start-positions of rate patterns so we can skip them.
    final rateStarts = _rateAfterNumber
        .allMatches(text)
        .map((m) => m.start)
        .toSet();

    for (final m in RegExp(r'\d+').allMatches(text)) {
      if (rateStarts.contains(m.start)) continue;
      final val = int.tryParse(m.group(0)!);
      if (val != null && val > 0) return val;
    }
    return null;
  }

  // ── Unit extraction ─────────────────────────────────────────────────────

  String? _findUnit(String text) {
    // Latin keywords (Hinglish) —————————————————————————————
    if (text.contains('running foot') ||
        text.contains('running ft') ||
        RegExp(r'\brft\b').hasMatch(text)) {
      return 'rft';
    }
    if (text.contains('square foot') ||
        text.contains('square ft') ||
        RegExp(r'\bsq\s*ft\b').hasMatch(text) ||
        RegExp(r'\bsqft\b').hasMatch(text)) {
      return 'sq ft';
    }
    if (text.contains('square meter') ||
        text.contains('sq meter') ||
        RegExp(r'\bsqm\b').hasMatch(text)) {
      return 'sq m';
    }
    // Devanagari keywords (when the transcript returns Hindi script) ————————
    // रनिंग फुट / रनिंग फीट
    if (text.contains('\u0930\u0928\u093f\u0902\u0917 \u092b\u0941\u091f') ||
        text.contains('\u0930\u0928\u093f\u0902\u0917 \u092b\u0940\u091f')) {
      return 'rft';
    }
    // वर्ग फुट / वर्ग फीट
    if (text.contains('\u0935\u0930\u094d\u0917 \u092b\u0941\u091f') ||
        text.contains('\u0935\u0930\u094d\u0917 \u092b\u0940\u091f')) {
      return 'sq ft';
    }
    return null;
  }
}

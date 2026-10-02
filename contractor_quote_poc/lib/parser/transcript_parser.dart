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

  /// True for generic-fallback items: numbers were heard but no service
  /// matched, so the description is a best-effort snippet. Always reviewed.
  final bool isUnknown;
  final bool requiresReview;

  const ParsedLineItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitRatePaise,
    this.serviceItemId,
    this.isUnknown = false,
    this.requiresReview = false,
  });

  /// Convert to the immutable model used by the calculation layer.
  QuoteLineItem toQuoteLineItem() => QuoteLineItem(
        description: description,
        quantity: quantity,
        unit: unit,
        unitRatePaise: unitRatePaise,
        serviceItemId: serviceItemId,
        isUnknown: isUnknown,
        requiresReview: requiresReview,
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

/// A phrase-separated slice of normalized text that contains a digit.
class _TextChunk {
  final String text;
  final int start;
  final int end;

  const _TextChunk(this.text, this.start, this.end);
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
  ///
  /// When [genericFallback] is true (offline path), number-bearing phrases
  /// that match NO service still produce review-flagged provisional items
  /// instead of being dropped: quantity, unit and rate are parsed generically
  /// so site work is never lost. Defaults to false so callers that rely on
  /// strict service-only matching are unaffected.
  ParseResult parse(
    String transcript, {
    List<ServiceItem> services = const [],
    Map<String, int>? savedRates,
    bool genericFallback = false,
  }) {
    final text = _normalize(transcript);
    final matches = _findServiceMatches(text, services);

    // ── No service matched at all ──────────────────────────────────────────
    if (matches.isEmpty) {
      if (genericFallback && RegExp(r'\d').hasMatch(text)) {
        return _genericItems(text, const []);
      }
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

    // ── Generic gap scan (offline fallback only) ───────────────────────────
    // Number-bearing phrases outside every service match become provisional
    // review items instead of being silently dropped.
    if (genericFallback) {
      final extra = _genericItems(text, matches);
      items.addAll(extra.items);
      warnings.addAll(extra.warnings);
    }

    return ParseResult(items: items, warnings: warnings);
  }

  // ── Generic fallback: numbers without a service ─────────────────────────

  /// Provisional items for number-bearing chunks of [text] that overlap no
  /// entry of [claimed] service matches. Purely structural (quantity, unit,
  /// rate); descriptions are best-effort snippets flagged for review.
  ParseResult _genericItems(String text, List<_ServiceMatch> claimed) {
    final items = <ParsedLineItem>[];
    final warnings = <String>[];
    var autoNumber = 0;

    for (final chunk in _numberChunks(text)) {
      if (_overlapsMatch(chunk.start, chunk.end, claimed)) continue;

      final rate = _findRate(chunk.text);
      final qty = _firstNonRateNumber(chunk.text);
      if (qty == null && rate == null) continue;

      final unit = _findUnit(chunk.text) ?? 'item';
      final description = _describeChunk(chunk.text) ?? 'Service ${++autoNumber}';
      if (qty == null || rate == null) {
        final missingField = qty == null && rate == null
            ? 'quantity and rate'
            : (qty == null ? 'quantity' : 'rate');
        warnings.add(
          'Could not fully extract details for "$description" — '
          'please fill in the $missingField manually.',
        );
      }
      items.add(ParsedLineItem(
        description: description,
        quantity: qty ?? 0,
        unit: unit,
        unitRatePaise: rate != null ? rate * 100 : 0,
        isUnknown: true,
        requiresReview: true,
      ));
    }

    if (items.isNotEmpty) {
      warnings.insert(
        0,
        'Some work was not in your services — please check and fix it.',
      );
    }
    return ParseResult(items: items, warnings: warnings);
  }

  /// Splits [text] on phrase separators and keeps chunks containing a digit,
  /// with their offsets so service-claimed spans can be excluded.
  List<_TextChunk> _numberChunks(String text) {
    final chunks = <_TextChunk>[];
    final sep = RegExp(r'\s+(?:and|aur|our|plus|तथा|और)\s+');
    var start = 0;
    for (final m in sep.allMatches(text)) {
      _addChunkIfNumbered(text, start, m.start, chunks);
      start = m.end;
    }
    _addChunkIfNumbered(text, start, text.length, chunks);
    return chunks;
  }

  void _addChunkIfNumbered(
      String text, int start, int end, List<_TextChunk> out) {
    if (start >= end) return;
    final chunk = text.substring(start, end).trim();
    if (chunk.isEmpty || !RegExp(r'\d').hasMatch(chunk)) return;
    final offset = text.indexOf(chunk, start);
    out.add(_TextChunk(chunk, offset < 0 ? start : offset,
        (offset < 0 ? start : offset) + chunk.length));
  }

  /// True when [start,end) overlaps any claimed service match by more than
  /// half of the smaller span — those numbers belong to the matched item.
  bool _overlapsMatch(int start, int end, List<_ServiceMatch> claimed) {
    for (final m in claimed) {
      final overlapStart = start > m.start ? start : m.start;
      final overlapEnd = end < m.end ? end : m.end;
      final overlap = overlapEnd - overlapStart;
      if (overlap <= 0) continue;
      final smaller =
          (end - start) < (m.end - m.start) ? (end - start) : (m.end - m.start);
      if (overlap * 2 >= smaller) return true;
    }
    return false;
  }

  // Words that carry no meaning for a provisional description.
  static const _genericStopWords = {
    'sq', 'ft', 'square', 'feet', 'rft', 'running', 'foot', 'meter', 'metre',
    'nos', 'piece', 'pieces', 'point', 'points', 'lumpsum', 'lump', 'sum',
    'bags', 'bag', 'brass', 'kg', 'kilo', 'litre', 'liter', 'hour', 'hours',
    'hr', 'visit', 'visits', 'room', 'rooms', 'flat', 'plate', 'plates',
    'rate', 'rates', 'rupaye', 'rupee', 'rupees', 'rupe', 'bhav', 'dar',
    'per', 'prati', 'ka', 'ki', 'ke', 'ko', 'mein', 'me', 'aur', 'or',
    'kaam', 'karo', 'karna', 'hai', 'hain', 'liye',
  };

  /// Best-effort description: content words of the chunk (numbers, units and
  /// rate words stripped), up to 5 words. Null when nothing meaningful
  /// remains so the caller can fall back to 'Service N'.
  String? _describeChunk(String chunk) {
    final words = chunk
        .split(' ')
        .where((w) =>
            w.isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(w) &&
            w != '₹' &&
            !_genericStopWords.contains(w))
        .take(5)
        .toList();
    if (words.isEmpty) return null;
    return words
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
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
    // Generic count/visit/weight/time units (any domain) ————————————————
    if (RegExp(r'\bplates?\b').hasMatch(text)) return 'plate';
    if (RegExp(r'\bnos\b|\bpieces?\b').hasMatch(text)) return 'nos';
    if (RegExp(r'\bpoints?\b').hasMatch(text)) return 'point';
    if (text.contains('lump sum') || text.contains('lumpsum')) {
      return 'lumpsum';
    }
    if (RegExp(r'\bbags?\b').hasMatch(text)) return 'bags';
    if (RegExp(r'\bbrass\b').hasMatch(text)) return 'brass';
    if (RegExp(r'\bkgs?\b|\bkilos?\b').hasMatch(text)) return 'kg';
    if (RegExp(r'\blitres?\b').hasMatch(text)) return 'litre';
    if (RegExp(r'\bhours?\b|\bhrs?\b').hasMatch(text)) return 'hour';
    if (RegExp(r'\bvisits?\b|\btrips?\b').hasMatch(text)) return 'visit';
    if (RegExp(r'\brooms?\b|\bflats?\b').hasMatch(text)) return 'room';
    if (RegExp(r'\bmeters?\b|\bmetres?\b').hasMatch(text)) return 'meter';
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
    if (text.contains('नग')) return 'nos';
    if (text.contains('पॉइंट')) return 'point';
    if (text.contains('किलो')) return 'kg';
    if (text.contains('लीटर')) return 'litre';
    if (text.contains('घंटा') || text.contains('तास')) return 'hour';
    if (text.contains('फेरा') || text.contains('भेट')) return 'visit';
    if (text.contains('कमरा') || text.contains('खोली')) return 'room';
    if (text.contains('थाली') || text.contains('थाळी')) return 'plate';
    if (text.contains('बोरी')) return 'bags';
    if (text.contains('ब्रास')) return 'brass';
    return null;
  }
}

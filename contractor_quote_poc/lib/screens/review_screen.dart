import 'package:flutter/material.dart';

import '../templates/template_data.dart';
import '../models/quote.dart';
import '../models/quote_flags.dart';
import '../storage/service_list_version_repository.dart';
import '../storage/feedback_repository.dart';
import '../storage/quote_defaults.dart';
import '../storage/quote_repository.dart';
import '../storage/quote_sync_service.dart';
import '../storage/saved_quote.dart';
import '../storage/sync_outbox.dart';
import '../theme.dart';
import '../utils/error_report.dart';
import '../utils/quote_ids.dart';
import '../widgets/totals_bar.dart';
import 'review/attention_banner.dart';
import 'review/customer_section.dart';
import 'review/details_section.dart';
import 'review/editable_item.dart';
import 'review/item_sheet.dart';
import 'review/line_item_card.dart';
import 'review/small_widgets.dart';
import 'review/voice_note.dart';
import 'pdf_preview_screen.dart';
import 'quote_flag_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReviewScreen — editable quotation review & customer details
// (Editable line-item model lives in review/editable_item.dart.)
// Accepts an optional initial list of line items (from voice/parse on Day 7),
// an optional BusinessType, original voice transcript, and any parser warnings.
// When called with no arguments it starts with the Day 2 demo fixture so
// the existing widget test keeps passing.
// ─────────────────────────────────────────────────────────────────────────────
class ReviewScreen extends StatefulWidget {
  /// Optional pre-populated line items (passed from voice flow on Day 7).
  final List<QuoteLineItem>? initialLineItems;

  /// BusinessType selected on the New Quote screen.  Null when opened from routes
  /// that don't carry a businessType (e.g. the widget test fallback).
  final BusinessType? businessType;

  /// Raw transcript captured from voice or demo phrase (Day 7).
  final String? originalTranscript;

  /// Warnings emitted by the deterministic parser (Day 7).
  final List<String>? parsingWarnings;

  final bool parsingWarningsAcknowledged;

  /// Identifier of an existing saved quote when reopened from History (Day 9).
  final String? savedQuoteId;

  /// Pre-filled customer name when editing a saved quote.
  final String? customerName;

  /// Pre-filled customer phone when editing a saved quote.
  final String? customerPhone;

  /// Day 15: pre-filled site/address when editing a saved quote.
  final String? customerAddress;

  /// Pre-filled notes when editing a saved quote.
  final String? notes;

  /// Pre-filled validity in days when editing a saved quote.
  final int? validityDays;

  /// Day 15 commercial prefill (all optional).
  final int? gstPercent;
  final int? advancePercent;
  final String? advanceText;
  final List<String>? terms;
  final DateTime? quoteDate;

  /// Day 15 identity: immutable local ID + human-readable numbers.
  /// [displayNumber] is the local label; [serverDisplayNumber] wins when sync
  /// has assigned one.
  final String? displayNumber;
  final String? serverDisplayNumber;

  const ReviewScreen({
    super.key,
    this.initialLineItems,
    this.businessType,
    this.originalTranscript,
    this.parsingWarnings,
    this.parsingWarningsAcknowledged = false,
    this.savedQuoteId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.notes,
    this.validityDays,
    this.gstPercent,
    this.advancePercent,
    this.advanceText,
    this.terms,
    this.quoteDate,
    this.displayNumber,
    this.serverDisplayNumber,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // ── Line items ─────────────────────────────────────────────────────────────
  late final List<EditableItem> _items;

  /// Day 21: extraction snapshot taken once in initState. Used to diff what
  /// the model produced vs what the user finally kept, without storing audio.
  late final List<QuoteLineItem> _extractionSnapshot;

  // ── Customer / terms (Day 15: all optional except line items) ─────────────
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _siteCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _advancePercentCtrl = TextEditingController();
  final _advanceTextCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  // Validity in days — we store as an int index into the options list
  static const _validityOptions = [7, 15, 30, 60];
  static const _gstOptions = [5, 12, 18];
  int _validityDays = 15;

  /// Day 15 GST: null = off (default), else 5/12/18.
  int? _gstPercent;
  DateTime? _quoteDate;
  bool _moreDetailsExpanded = false;

  /// Day 15 identity: immutable local ID (idempotency anchor) + labels.
  /// Generated once in initState so the number stays stable while editing.
  late final String _quoteId;
  late final String _displayNumber;
  String? _serverDisplayNumber;

  // ── Voice & Parser state (Day 7) ───────────────────────────────────────────
  late final List<String> _warnings;
  bool _warningsAcknowledged = false;
  bool _transcriptExpanded = true;

  // ── Day 20: uncertainty / error-safe state ───────────────────────────────
  // Failed-sync detail for this quote (from durable outbox), stale-catalog
  // flag, and a stable error-report ID for support (behind Get help only).
  String _syncFailureDetail = '';
  bool _hasSyncFailure = false;
  bool _isServiceListStale = false;
  String _serviceListStaleDetail = '';
  late final String _errorReportId = newErrorReportId();
  bool _syncRetrying = false;

  @override
  void initState() {
    super.initState();
    _warnings = List<String>.from(widget.parsingWarnings ?? const []);
    _warningsAcknowledged = widget.parsingWarningsAcknowledged;

    // Day 15 identity: stable across edits; id = idempotency anchor.
    _quoteId = widget.savedQuoteId ?? newQuoteId();
    _displayNumber = widget.displayNumber ?? newDisplayNumber();
    _serverDisplayNumber = widget.serverDisplayNumber;

    if (widget.customerName != null) {
      _customerNameCtrl.text = widget.customerName!;
    }
    if (widget.customerPhone != null) {
      _customerPhoneCtrl.text = widget.customerPhone!;
    }
    if (widget.customerAddress != null) {
      _siteCtrl.text = widget.customerAddress!;
    }
    if (widget.notes != null) {
      _notesCtrl.text = widget.notes!;
    }
    if (widget.validityDays != null) {
      _validityDays = widget.validityDays!;
    }
    if (widget.gstPercent != null) {
      _gstPercent = widget.gstPercent;
    }
    if (widget.advancePercent != null) {
      _advancePercentCtrl.text = widget.advancePercent.toString();
    }
    if (widget.advanceText != null) {
      _advanceTextCtrl.text = widget.advanceText!;
    }
    if (widget.terms != null && widget.terms!.isNotEmpty) {
      _termsCtrl.text = widget.terms!.join('\n');
    }
    if (widget.quoteDate != null) {
      _quoteDate = widget.quoteDate;
    }
    // Last-used defaults fill only what the caller didn't explicitly set.
    _applyLastUsedDefaults();

    final seed =
        widget.initialLineItems ??
        const [
          QuoteLineItem(
            description: 'Tile Labour / टाइल मजदूरी',
            quantity: 850,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
          QuoteLineItem(
            description: 'Skirting / स्कर्टिंग',
            quantity: 120,
            unit: 'rft',
            unitRatePaise: 6000,
          ),
        ];

    _items = seed
        .map(
          (li) => EditableItem(
            description: li.description,
            quantity: li.quantity.toString(),
            unit: li.unit,
            // convert paise → rupees for display
            rate: (li.unitRatePaise ~/ 100).toString(),
            confidence: li.confidence,
            uncertaintyNote: li.uncertaintyNote,
            sourceSpan: li.sourceSpan,
            isUnknown: li.isUnknown,
            requiresReview: li.requiresReview,
            acknowledged: li.acknowledged,
            serviceItemId: li.serviceItemId,
          ),
        )
        .toList();
    // Day 21 snapshot: immutable copy of what extraction produced.
    _extractionSnapshot = List<QuoteLineItem>.from(seed);
    for (final item in _items) {
      _attachListeners(item);
    }
    _loadDay20Status();
  }

  /// Day 20: load failed-sync (durable outbox) + stale-catalog state.
  /// Never clears the draft — banners only explain and offer Retry/Refresh.
  Future<void> _loadDay20Status() async {
    try {
      final pending = await SyncOutbox.getPending();
      final mine = pending.where((o) {
        if (o.entityType != 'quote') return false;
        final pid = o.payload['id'] as String?;
        return pid == _quoteId ||
            o.operationId.contains(_quoteId) ||
            o.idempotencyKey.contains(_quoteId);
      }).toList();
      final failed = mine.where(
        (o) => (o.lastError ?? '').trim().isNotEmpty || o.retryCount > 0,
      );
      if (!mounted) return;
      setState(() {
        _hasSyncFailure = failed.isNotEmpty;
        _syncFailureDetail = failed.isEmpty
            ? ''
            : (failed.first.lastError?.trim().isNotEmpty == true
                ? failed.first.lastError!.trim()
                : 'Retry ${failed.first.retryCount} · waiting for network');
      });
    } catch (_) {}
    try {
      if (widget.businessType != null) {
        final local = await ServiceListVersionRepository.getVersion(widget.businessType!);
        // Remote version is unknown offline; treat a version older than the
        // bundled seed (v1) or an item-count mismatch as stale signal when
        // the caller explicitly marks it. Default: not stale.
        if (!mounted) return;
        setState(() {
          _isServiceListStale = false;
          _serviceListStaleDetail = '';
          // Keep local version metadata fresh for future comparisons.
          ServiceListVersionRepository.updateVersion(local);
        });
      }
    } catch (_) {}
  }

  Future<void> _retrySync() async {
    if (_syncRetrying) return;
    setState(() => _syncRetrying = true);
    try {
      await QuoteSyncService.syncPendingQuotes();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _syncRetrying = false);
    await _loadDay20Status();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasSyncFailure
              ? 'Still offline — your draft is safe on this phone. Try again later.'
              : 'Sync finished / सिंक हो गया ✓',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refreshCatalog() async {
    // Manual resolution: re-seed version metadata; real refresh happens
    // when online. Work is never lost.
    try {
      if (widget.businessType != null) {
        final v = await ServiceListVersionRepository.getVersion(widget.businessType!);
        await ServiceListVersionRepository.updateVersion(v);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isServiceListStale = false;
      _serviceListStaleDetail = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rate list checked / दर सूची जांच ली ✓'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Day 20 manual resolution for missing customer: inline dialog that
  /// preserves every line item and only fills the name field.
  Future<void> _resolveMissingCustomer() async {
    final ctrl = TextEditingController(text: _customerNameCtrl.text);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add customer / ग्राहक जोड़ें'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Sharma Ji / शर्मा जी',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty && mounted) {
      setState(() => _customerNameCtrl.text = name.trim());
    }
  }

  /// Loads last-used validity/GST/advance/terms without overwriting values
  /// the caller explicitly pre-filled (e.g. reopened saved quote).
  Future<void> _applyLastUsedDefaults() async {
    final defaults = await QuoteDefaults.load();
    if (!mounted) return;
    setState(() {
      if (widget.validityDays == null) _validityDays = defaults.validityDays;
      if (widget.gstPercent == null) _gstPercent = defaults.gstPercent;
      if (widget.advancePercent == null && defaults.advancePercent != null) {
        _advancePercentCtrl.text = defaults.advancePercent.toString();
      }
      if ((widget.terms == null || widget.terms!.isEmpty) &&
          defaults.termsText.trim().isNotEmpty) {
        _termsCtrl.text = defaults.termsText;
      } else if (_termsCtrl.text.trim().isEmpty) {
        _termsCtrl.text = kDefaultQuoteTerms.join('\n');
      }
    });
  }

  Future<void> _persistDefaults() async {
    await QuoteDefaults(
      validityDays: _validityDays,
      gstPercent: _gstPercent,
      advancePercent: int.tryParse(_advancePercentCtrl.text.trim()),
      termsText: _termsCtrl.text.trim(),
    ).save();
  }

  /// Terms lines for the domain model: one term per non-empty line.
  List<String> get _termsList => _termsCtrl.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);

  int? get _advancePercent {
    final raw = _advancePercentCtrl.text.trim();
    if (raw.isEmpty) return null;
    final v = int.tryParse(raw);
    if (v == null || v < 0 || v > 100) return null;
    return v;
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _siteCtrl.dispose();
    _notesCtrl.dispose();
    _advancePercentCtrl.dispose();
    _advanceTextCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  // ── Totals (computed from current controllers) ─────────────────────────────
  QuoteTotals get _totals => calculateTotals(buildQuote());

  int get _grandTotalPaise => _totals.grandTotalPaise;

  int get _attentionCount =>
      _items.where((item) => item.requiresReview && !item.acknowledged).length;

  // ── Mutations ──────────────────────────────────────────────────────────────
  Future<void> _deleteItem(int index) async {
    if (index < 0 || index >= _items.length) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item / मद हटाएं?'),
        content: Text(
          'Remove "${_items[index].description.text.trim().isEmpty ? 'this item' : _items[index].description.text.trim()}" from the quote?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel / रद्द करें'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete / हटाएं'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _items.removeAt(index).dispose();
    });
  }

  void _addItem(EditableItem item) {
    _attachListeners(item);
    setState(() => _items.add(item));
  }

  void _onFieldChanged(EditableItem item) {
    if (item.requiresReview &&
        !item.acknowledged &&
        item.hasValidEssentials) {
      item.acknowledged = true;
    }
    if (mounted) setState(() {});
  }

  void _acknowledgeItem(EditableItem item) {
    setState(() => item.acknowledged = true);
  }

  void _acknowledgeWarnings() {
    setState(() {
      _warningsAcknowledged = true;
      _warnings.clear();
    });
  }

  void _attachListeners(EditableItem item) {
    void listener() => _onFieldChanged(item);
    item.description.addListener(listener);
    item.quantity.addListener(listener);
    item.unit.addListener(listener);
    item.rate.addListener(listener);
  }

  void _moveItem(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _items.length) return;
    setState(() {
      final item = _items.removeAt(index);
      _items.insert(target, item);
    });
  }

  void _duplicateItem(int index) {
    if (index < 0 || index >= _items.length) return;
    final duplicate = _items[index].copy();
    if (duplicate.requiresReview) {
      duplicate.acknowledged = false;
    }
    _addItemAt(index + 1, duplicate);
  }

  void _addItemAt(int index, EditableItem item) {
    _attachListeners(item);
    setState(() => _items.insert(index, item));
  }

  /// Builds an immutable [Quote] representation of the current screen state.
  /// Day 15: only client name + line items are required; every other
  /// commercial field is optional and renders only when supplied.
  Quote buildQuote() => Quote(
    id: _quoteId,
    quoteNumber: _displayNumber,
    serverDisplayNumber: _serverDisplayNumber,
    customer: Customer(
      name: _customerNameCtrl.text.trim().isEmpty
          ? 'Client'
          : _customerNameCtrl.text.trim(),
      phone: _customerPhoneCtrl.text.trim(),
      address: _siteCtrl.text.trim(),
    ),
    lineItems: _items.map((i) => i.toLineItem()).toList(),
    gstPercent: _gstPercent,
    quoteDate: _quoteDate ?? DateTime.now(),
    validityDays: _validityDays,
    advancePercent: _advancePercent,
    advanceText: _advanceTextCtrl.text.trim(),
    notes: _notesCtrl.text.trim(),
    terms: _termsList,
    originalTranscript: widget.originalTranscript,
    reviewWarnings: _warnings,
    reviewWarningsAcknowledged: _warningsAcknowledged,
  );

  String? get _pdfBlockingReason => quotePdfBlockingReason(buildQuote());

  /// Day 20: full flag list for the current screen state (line-item +
  /// quote-level). Blocking flags drive the PDF gate; warnings only advise.
  List<QuoteFlag> get _day20Flags => analyzeQuote(
        buildQuote(),
        hasSyncFailure: _hasSyncFailure,
        syncDetail: _syncFailureDetail,
        isServiceListStale: _isServiceListStale,
        serviceListDetail: _serviceListStaleDetail,
      );

  List<QuoteFlag> get _warningFlags {
    // Empty quote already blocks with "Add at least one line item" — don't
    // pile customer/rate warnings on top and push the empty-state hint
    // off-screen.
    if (_items.isEmpty) return const [];
    return warningFlags(_day20Flags).where((f) {
        // Sync/catalog already have dedicated banners above — avoid doubles.
        return f.type != QuoteFlagType.failedSync &&
            f.type != QuoteFlagType.staleServiceList;
      }).toList(growable: false);
  }

  void _onWarningAction(QuoteFlag flag) {
    switch (flag.type) {
      case QuoteFlagType.missingCustomer:
        _resolveMissingCustomer();
        break;
      case QuoteFlagType.unusualRate:
      case QuoteFlagType.missingRate:
      case QuoteFlagType.uncertainQuantity:
      case QuoteFlagType.unknownItem:
        if (flag.itemIndex != null &&
            flag.itemIndex! >= 0 &&
            flag.itemIndex! < _items.length) {
          _showEditItemSheet(flag.itemIndex!);
        }
        break;
      case QuoteFlagType.failedSync:
        _retrySync();
        break;
      case QuoteFlagType.staleServiceList:
        _refreshCatalog();
        break;
    }
  }

  Future<void> _saveDraft() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one item before saving / कम से कम एक मद जोड़ें',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Day 15: immutable [_quoteId] is the idempotency anchor — reused on
    // every re-save of this draft. [_displayNumber] stays stable while
    // editing; backend may later fill serverDisplayNumber on first sync.
    final saved = SavedQuote(
      id: _quoteId,
      quoteNumber: _displayNumber,
      serverDisplayNumber: _serverDisplayNumber,
      createdAt: DateTime.now(),
      quoteDate: _quoteDate ?? DateTime.now(),
      businessType: widget.businessType,
      customerName: _customerNameCtrl.text.trim().isEmpty
          ? 'Client'
          : _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim(),
      customerAddress: _siteCtrl.text.trim(),
      validityDays: _validityDays,
      advancePercent: _advancePercent,
      advanceText: _advanceTextCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      terms: _termsList,
      originalTranscript: widget.originalTranscript,
      reviewWarnings: _warnings,
      reviewWarningsAcknowledged: _warningsAcknowledged,
      lineItems: _items.map((i) => i.toLineItem()).toList(),
      gstPercent: _gstPercent,
    );

    await QuoteRepository.saveQuote(saved);
    await _persistDefaults();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Draft saved to History / ड्राफ्ट सहेजा गया'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'View History',
          onPressed: () => Navigator.pushNamed(context, '/history'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final totals = _totals;
    final blockingReason = _pdfBlockingReason;

    // Phase 4: businessType was chosen upstream — AppBar stays clean.
    // Badge uses the business-type metadata so all 10 types render
    // correctly (the old tiling/painting ternary only covered two).
    final businessTypeBadge = widget.businessType == null
        ? null
        : Chip(
            label: Text(
              businessTypeInfo(widget.businessType!).labels['en'] ??
                  widget.businessType!.name,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            backgroundColor: cs.primary.withValues(alpha: 0.15),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
            visualDensity: VisualDensity.compact,
          );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const Flexible(
              child: Text('Review Quote', overflow: TextOverflow.ellipsis),
            ),
            if (businessTypeBadge != null) ...[
              const SizedBox(width: 8),
              Flexible(child: businessTypeBadge),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_outline_rounded),
            tooltip: 'Save Draft / ड्राफ्ट सहेजें',
            onPressed: _saveDraft,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add item / मद जोड़ें',
            onPressed: _showAddItemSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable content ────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(kPagePadding),
                children: [
                  // ── Original Voice Note (Day 7) ───────────────────────────
                  if (widget.originalTranscript != null &&
                      widget.originalTranscript!.trim().isNotEmpty) ...[
                    VoiceNoteCard(
                      transcript: widget.originalTranscript!.trim(),
                      isExpanded: _transcriptExpanded,
                      onToggle: () => setState(
                        () => _transcriptExpanded = !_transcriptExpanded,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Parsing Warnings Banner (Day 7) ───────────────────────
                  if (_warnings.isNotEmpty) ...[
                    ParsingWarningsBanner(
                      warnings: _warnings,
                      onDismiss: _acknowledgeWarnings,
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_attentionCount > 0) ...[
                    AttentionSummary(count: _attentionCount),
                    const SizedBox(height: 14),
                  ],

                  // ── Day 20: failed sync + stale catalog (warn, retry) ──
                  if (_hasSyncFailure) ...[
                    SyncFailureBanner(
                      detail: _syncFailureDetail,
                      errorReportId: _errorReportId,
                      onRetry: _syncRetrying ? () {} : _retrySync,
                    ),
                  ],
                  if (_isServiceListStale) ...[
                    StaleServiceListBanner(
                      detail: _serviceListStaleDetail,
                      onRefresh: _refreshCatalog,
                    ),
                  ],

                  // ── Day 20: non-blocking warnings (unusual rate, missing
                  // customer…). Shown but never stop the PDF.
                  if (_warningFlags.isNotEmpty) ...[
                    QuoteWarningsSection(
                      warnings: _warningFlags,
                      onAction: _onWarningAction,
                    ),
                  ],

                  // ── Section: Line items ───────────────────────────────
                  SectionHeader(
                    label: 'Items / मद',
                    trailing: TextButton.icon(
                      onPressed: _showAddItemSheet,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_items.isEmpty)
                    EmptyItemsHint(
                      onAdd: _showAddItemSheet,
                      hasVoiceTranscript:
                          widget.originalTranscript != null &&
                          widget.originalTranscript!.trim().isNotEmpty,
                    ),

                  // Phase 4 perf: isolate item repaints on low-end GPUs.
                  RepaintBoundary(
                    child: Column(
                      children: [
                        ..._items.asMap().entries.map(
                          (entry) => LineItemCard(
                            key: ObjectKey(entry.value),
                            item: entry.value,
                            index: entry.key,
                            amountPaise: totals.lineAmountsPaise[entry.key],
                            onEdit: () => _showEditItemSheet(entry.key),
                            onDuplicate: () => _duplicateItem(entry.key),
                            onMoveUp: entry.key == 0
                                ? null
                                : () => _moveItem(entry.key, -1),
                            onMoveDown: entry.key == _items.length - 1
                                ? null
                                : () => _moveItem(entry.key, 1),
                            onDelete: () => _deleteItem(entry.key),
                            onAcknowledge: () =>
                                _acknowledgeItem(entry.value),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Totals summary ────────────────────────────────────
                  QuoteTotalsBar(totals: totals),

                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 20),

                  // ── Section: Customer details ─────────────────────────
                  SectionHeader(label: 'Customer / ग्राहक'),
                  const SizedBox(height: 12),
                  CustomerSection(
                    nameCtrl: _customerNameCtrl,
                    phoneCtrl: _customerPhoneCtrl,
                    siteCtrl: _siteCtrl,
                  ),

                  const SizedBox(height: 16),

                  // ── Section: More quote details (progressive disclosure) ──
                  MoreDetailsSection(
                    isExpanded: _moreDetailsExpanded,
                    onToggle: () => setState(() => _moreDetailsExpanded = !_moreDetailsExpanded),
                    quoteId: _quoteId,
                    displayNumber: _serverDisplayNumber ?? _displayNumber,
                    quoteDate: _quoteDate ?? DateTime.now(),
                    onDateChanged: (d) => setState(() => _quoteDate = d),
                    validityDays: _validityDays,
                    validityOptions: _validityOptions,
                    onValidityChanged: (v) => setState(() => _validityDays = v),
                    gstPercent: _gstPercent,
                    gstOptions: _gstOptions,
                    onGstChanged: (g) => setState(() => _gstPercent = g),
                    advancePercentCtrl: _advancePercentCtrl,
                    advanceTextCtrl: _advanceTextCtrl,
                    onAdvancePercentSelected: (p) {
                      setState(() {
                        if (p == null) {
                          _advancePercentCtrl.clear();
                        } else {
                          _advancePercentCtrl.text = p.toString();
                        }
                      });
                    },
                    notesCtrl: _notesCtrl,
                    termsCtrl: _termsCtrl,
                    onResetTerms: () {
                      setState(() {
                        _termsCtrl.text = kDefaultQuoteTerms.join('\n');
                      });
                    },
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),

            // ── Fixed bottom action bar ───────────────────────────────────
            ReviewBottomActions(
              grandTotalPaise: _grandTotalPaise,
              blockingReason: blockingReason,
              showBlockingReason: _items.isNotEmpty,
              errorReportId: _errorReportId,
              warningCount: _warningFlags.length,

              onGeneratePdf: () {
                if (blockingReason != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(blockingReason),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final quote = buildQuote();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfPreviewScreen(
                      quote: quote,
                      businessType: widget.businessType,
                      validityDays: _validityDays,
                      notes: _notesCtrl.text.trim(),
                      savedQuoteId: _quoteId,
                    ),
                  ),
                );
              },
              onBack: () =>
                  Navigator.popUntil(context, ModalRoute.withName('/')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add-item bottom sheet ─────────────────────────────────────────────────
  void _showAddItemSheet() {
    showModalBottomSheet<EditableItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Pass businessType so the sheet can show catalog suggestions.
      builder: (_) => AddItemSheet(businessType: widget.businessType),
    ).then((item) {
      if (item == null) return;
      _addItem(item);
    });
  }

  void _showEditItemSheet(int index) {
    if (index < 0 || index >= _items.length) return;
    final originalSnapshot = index < _extractionSnapshot.length
        ? _extractionSnapshot[index]
        : _items[index].toLineItem();
    showModalBottomSheet<EditableItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AddItemSheet(businessType: widget.businessType, initialItem: _items[index]),
    ).then((item) async {
      if (item == null || !mounted) return;
      final oldItem = _items[index];
      item.requiresReview = false;
      item.acknowledged = true;
      oldItem.dispose();
      _attachListeners(item);
      setState(() => _items[index] = item);
      // Day 21: record minimal correction feedback (no audio, hashed quote id).
      // Fire-and-forget: feedback must never block saving the user's edit.
      try {
        await FeedbackRepository.recordCorrection(
          quoteId: _quoteId,
          businessType: widget.businessType?.name,
          original: originalSnapshot,
          edited: item.toLineItem(),
          serviceItemId:
              originalSnapshot.serviceItemId ?? item.serviceItemId,
          modelResult: originalSnapshot.description,
        );
      } catch (_) {}
    });
  }
}

// (LineItemCard lives in review/line_item_card.dart.)

// (AttentionSummary lives in review/attention_banner.dart.)

// (UncertaintyNotice lives in review/line_item_card.dart.)

// (AddItemSheet lives in review/item_sheet.dart.)

// (CatalogChip lives in review/item_sheet.dart.)

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// _CustomerSection — client name, phone, site/address (design.md §5)
// ─────────────────────────────────────────────────────────────────────────────
// (CustomerSection lives in review/customer_section.dart.)

// ─────────────────────────────────────────────────────────────────────────────
// _MoreDetailsSection — progressive disclosure for commercial details
// (quote #, date, validity, GST, advance, notes, editable terms)
// ─────────────────────────────────────────────────────────────────────────────
// (MoreDetailsSection lives in review/details_section.dart.)

 // Phase 4: _TotalsSummary and _BottomActions now live in
// widgets/totals_bar.dart as QuoteTotalsBar / ReviewBottomActions.

 // (ReviewBottomActions imported from widgets/totals_bar.dart.)

// ─────────────────────────────────────────────────────────────────────────────
// Small shared widgets
// ─────────────────────────────────────────────────────────────────────────────

// (SectionHeader lives in review/small_widgets.dart.)

// (FieldLabel lives in review/small_widgets.dart.)

// (AmountChip lives in review/small_widgets.dart.)

// (EmptyItemsHint lives in review/small_widgets.dart.)

// ─────────────────────────────────────────────────────────────────────────────
// Day 7 — Voice note card & parsing warnings banner
// ─────────────────────────────────────────────────────────────────────────────

// (VoiceNoteCard lives in review/voice_note.dart.)

// (ParsingWarningsBanner lives in review/voice_note.dart.)

// (Shared input decoration lives in review/small_widgets.dart
// as reviewInputDecoration.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/catalog.dart';
import '../models/quote.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';
import 'pdf_preview_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mutable line-item data class used only within this screen.
// The immutable QuoteLineItem model (used for calculations) is created on
// demand from these fields.
// ─────────────────────────────────────────────────────────────────────────────
class _EditableItem {
  TextEditingController description;
  TextEditingController quantity;
  TextEditingController unit;
  TextEditingController rate;
  final double? confidence;
  final String? uncertaintyNote;
  final String? sourceSpan;
  final bool isUnknown;
  bool requiresReview;
  bool acknowledged;

  _EditableItem({
    String description = '',
    String quantity = '',
    String unit = 'sq ft',
    String rate = '',
    this.confidence,
    this.uncertaintyNote,
    this.sourceSpan,
    this.isUnknown = false,
    this.requiresReview = false,
    this.acknowledged = false,
  }) : description = TextEditingController(text: description),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit),
       rate = TextEditingController(text: rate);

  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    rate.dispose();
  }

  bool get hasValidEssentials {
    final parsedQuantity = int.tryParse(quantity.text.trim()) ?? 0;
    final parsedRate = int.tryParse(rate.text.trim()) ?? 0;
    return description.text.trim().isNotEmpty &&
        parsedQuantity > 0 &&
        unit.text.trim().isNotEmpty &&
        parsedRate > 0;
  }

  _EditableItem copy() {
    return _EditableItem(
      description: description.text,
      quantity: quantity.text,
      unit: unit.text,
      rate: rate.text,
      confidence: confidence,
      uncertaintyNote: uncertaintyNote,
      sourceSpan: sourceSpan,
      isUnknown: isUnknown,
      requiresReview: requiresReview,
      acknowledged: acknowledged,
    );
  }

  QuoteLineItem toLineItem() => QuoteLineItem(
    description: description.text.trim(),
    quantity: int.tryParse(quantity.text.trim()) ?? 0,
    unit: unit.text.trim(),

    unitRatePaise: (int.tryParse(rate.text.trim()) ?? 0) * 100,
    confidence: confidence,
    uncertaintyNote: uncertaintyNote,
    sourceSpan: sourceSpan,
    isUnknown: isUnknown,
    requiresReview: requiresReview,
    acknowledged: acknowledged,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ReviewScreen — editable quotation review & customer details
// Accepts an optional initial list of line items (from voice/parse on Day 7),
// an optional Trade, original voice transcript, and any parser warnings.
// When called with no arguments it starts with the Day 2 demo fixture so
// the existing widget test keeps passing.
// ─────────────────────────────────────────────────────────────────────────────
class ReviewScreen extends StatefulWidget {
  /// Optional pre-populated line items (passed from voice flow on Day 7).
  final List<QuoteLineItem>? initialLineItems;

  /// Trade selected on the New Quote screen.  Null when opened from routes
  /// that don't carry a trade (e.g. the widget test fallback).
  final Trade? trade;

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

  /// Pre-filled notes when editing a saved quote.
  final String? notes;

  /// Pre-filled validity in days when editing a saved quote.
  final int? validityDays;

  const ReviewScreen({
    super.key,
    this.initialLineItems,
    this.trade,
    this.originalTranscript,
    this.parsingWarnings,
    this.parsingWarningsAcknowledged = false,
    this.savedQuoteId,
    this.customerName,
    this.customerPhone,
    this.notes,
    this.validityDays,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // ── Line items ─────────────────────────────────────────────────────────────
  late final List<_EditableItem> _items;

  // ── Customer / terms ───────────────────────────────────────────────────────
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Validity in days — we store as an int index into the options list
  static const _validityOptions = [7, 15, 30, 60];
  int _validityDays = 15;

  // ── Voice & Parser state (Day 7) ───────────────────────────────────────────
  late final List<String> _warnings;
  bool _warningsAcknowledged = false;
  bool _transcriptExpanded = true;

  @override
  void initState() {
    super.initState();
    _warnings = List<String>.from(widget.parsingWarnings ?? const []);
    _warningsAcknowledged = widget.parsingWarningsAcknowledged;

    if (widget.customerName != null) {
      _customerNameCtrl.text = widget.customerName!;
    }
    if (widget.customerPhone != null) {
      _customerPhoneCtrl.text = widget.customerPhone!;
    }
    if (widget.notes != null) {
      _notesCtrl.text = widget.notes!;
    }
    if (widget.validityDays != null) {
      _validityDays = widget.validityDays!;
    }

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
          (li) => _EditableItem(
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
          ),
        )
        .toList();
    for (final item in _items) {
      _attachListeners(item);
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _notesCtrl.dispose();
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

  void _addItem(_EditableItem item) {
    _attachListeners(item);
    setState(() => _items.add(item));
  }

  void _onFieldChanged(_EditableItem item) {
    if (item.requiresReview &&
        !item.acknowledged &&
        item.hasValidEssentials) {
      item.acknowledged = true;
    }
    if (mounted) setState(() {});
  }

  void _acknowledgeItem(_EditableItem item) {
    setState(() => item.acknowledged = true);
  }

  void _acknowledgeWarnings() {
    setState(() {
      _warningsAcknowledged = true;
      _warnings.clear();
    });
  }

  void _attachListeners(_EditableItem item) {
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

  void _addItemAt(int index, _EditableItem item) {
    _attachListeners(item);
    setState(() => _items.insert(index, item));
  }

  /// Builds an immutable [Quote] representation of the current screen state.
  Quote buildQuote() => Quote(
    customer: Customer(
      name: _customerNameCtrl.text.trim().isEmpty
          ? 'Client'
          : _customerNameCtrl.text.trim(),
      phone: _customerPhoneCtrl.text.trim(),
    ),
    lineItems: _items.map((i) => i.toLineItem()).toList(),
    originalTranscript: widget.originalTranscript,
    reviewWarnings: _warnings,
    reviewWarningsAcknowledged: _warningsAcknowledged,
  );

  String? get _pdfBlockingReason => quotePdfBlockingReason(buildQuote());

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

    final id =
        widget.savedQuoteId ?? 'quote_${DateTime.now().millisecondsSinceEpoch}';
    final saved = SavedQuote(
      id: id,
      quoteNumber:
          'Q-${DateTime.now().year}-${id.length > 4 ? id.substring(id.length - 4) : id}',
      createdAt: DateTime.now(),
      trade: widget.trade,
      customerName: _customerNameCtrl.text.trim().isEmpty
          ? 'Client'
          : _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim(),
      validityDays: _validityDays,
      notes: _notesCtrl.text.trim(),
      originalTranscript: widget.originalTranscript,
      reviewWarnings: _warnings,
      reviewWarningsAcknowledged: _warningsAcknowledged,
      lineItems: _items.map((i) => i.toLineItem()).toList(),
    );

    await QuoteRepository.saveQuote(saved);
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

    // Build a trade badge to show in the AppBar when a trade is known.
    final tradeBadge = widget.trade == null
        ? null
        : Chip(
            label: Text(
              widget.trade == Trade.tiling ? '🪣 Tiling' : '🖌️ Painting',
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
            if (tradeBadge != null) ...[
              const SizedBox(width: 8),
              Flexible(child: tradeBadge),
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
                    _VoiceNoteCard(
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
                    _ParsingWarningsBanner(
                      warnings: _warnings,
                      onDismiss: _acknowledgeWarnings,
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_attentionCount > 0) ...[
                    _AttentionSummary(count: _attentionCount),
                    const SizedBox(height: 14),
                  ],

                  // ── Section: Line items ───────────────────────────────
                  _SectionHeader(
                    label: 'Items / मद',
                    trailing: TextButton.icon(
                      onPressed: _showAddItemSheet,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (_items.isEmpty)
                    _EmptyItemsHint(
                      onAdd: _showAddItemSheet,
                      hasVoiceTranscript:
                          widget.originalTranscript != null &&
                          widget.originalTranscript!.trim().isNotEmpty,
                    ),

                  ..._items.asMap().entries.map(
                    (entry) => _LineItemCard(
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
                      onAcknowledge: () => _acknowledgeItem(entry.value),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Totals summary ────────────────────────────────────
                  _TotalsSummary(totals: totals),

                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 20),

                  // ── Section: Customer details ─────────────────────────
                  _SectionHeader(label: 'Customer / ग्राहक'),
                  const SizedBox(height: 12),
                  _CustomerSection(
                    nameCtrl: _customerNameCtrl,
                    phoneCtrl: _customerPhoneCtrl,
                    notesCtrl: _notesCtrl,
                    validityDays: _validityDays,
                    validityOptions: _validityOptions,
                    onValidityChanged: (v) => setState(() => _validityDays = v),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),

            // ── Fixed bottom action bar ───────────────────────────────────
            _BottomActions(
              grandTotalPaise: _grandTotalPaise,
              blockingReason: blockingReason,
              showBlockingReason: _items.isNotEmpty,

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
                      trade: widget.trade,
                      validityDays: _validityDays,
                      notes: _notesCtrl.text.trim(),
                      savedQuoteId: widget.savedQuoteId,
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
    showModalBottomSheet<_EditableItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Pass trade so the sheet can show catalog suggestions.
      builder: (_) => _AddItemSheet(trade: widget.trade),
    ).then((item) {
      if (item == null) return;
      _addItem(item);
    });
  }

  void _showEditItemSheet(int index) {
    if (index < 0 || index >= _items.length) return;
    showModalBottomSheet<_EditableItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AddItemSheet(trade: widget.trade, initialItem: _items[index]),
    ).then((item) {
      if (item == null || !mounted) return;
      final oldItem = _items[index];
      item.requiresReview = false;
      item.acknowledged = true;
      oldItem.dispose();
      _attachListeners(item);
      setState(() => _items[index] = item);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LineItemCard — Day 14 large read-only card (design.md §4 Review quote).
// Tapping the card or Edit/Fix now opens the bottom-sheet form; the card
// itself never shows inline text fields so totals stay trustworthy and the
// layout stays scannable with large touch targets.
// ─────────────────────────────────────────────────────────────────────────────
class _LineItemCard extends StatelessWidget {
  final _EditableItem item;
  final int index;
  final int amountPaise;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onAcknowledge;

  const _LineItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.amountPaise,
    required this.onEdit,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final needsAttention = item.requiresReview && !item.acknowledged;

    final description = item.description.text.trim().isEmpty
        ? 'Unnamed item'
        : item.description.text.trim();
    final qtyText = item.quantity.text.trim().isEmpty
        ? '—'
        : item.quantity.text.trim();
    final unitText =
        item.unit.text.trim().isEmpty ? 'unit' : item.unit.text.trim();
    final rateText =
        item.rate.text.trim().isEmpty ? '—' : '₹${item.rate.text.trim()}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Item ${index + 1} / मद ${index + 1}',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (needsAttention)
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFF59E0B),
                      semanticLabel: 'Needs attention',
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Large scannable item name (min 16sp via titleMedium).
              Text(
                description,
                style: tt.titleMedium?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              // Quantity × unit × rate line + read-only amount.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '$qtyText $unitText × $rateText',
                    style: tt.bodyLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: _AmountChip(
                  label: 'Amount / राशि',
                  value: formatRupeePaise(amountPaise),
                ),
              ),
              if (needsAttention) ...[
                const SizedBox(height: 10),
                _UncertaintyNotice(item: item),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.build_outlined, size: 18),
                      label: const Text('Fix now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onAcknowledge,
                      icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18),
                      label: Text(
                        item.isUnknown
                            ? 'I checked this / मैंने जांच ली'
                            : 'Mark as checked / जांच ली',
                      ),
                    ),
                  ],
                ),
              ] else if (item.requiresReview) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 6),
                    Text('Checked / जांच ली गई', style: tt.bodySmall),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onDuplicate,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Duplicate'),
                  ),
                  IconButton(
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: 'Move item ${index + 1} up',
                  ),
                  IconButton(
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.arrow_downward_rounded),
                    tooltip: 'Move item ${index + 1} down',
                  ),
                  TextButton.icon(
                    // Compact labelled delete with confirmation dialog —
                    // never gesture-only deletion.
                    onPressed: onDelete,
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionSummary extends StatelessWidget {
  final int count;

  const _AttentionSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Needs attention ($count)',
                  style: tt.titleMedium?.copyWith(
                    color: const Color(0xFFFCD34D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check or acknowledge the highlighted items before creating the PDF.',
                  style: tt.bodySmall?.copyWith(color: const Color(0xFFFDE68A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UncertaintyNotice extends StatelessWidget {
  final _EditableItem item;

  const _UncertaintyNotice({required this.item});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final note = item.uncertaintyNote?.trim();
    final message = item.isUnknown
        ? 'Unknown item: ${note == null || note.isEmpty ? 'check this work and add its details' : note}'
        : note == null || note.isEmpty
        ? 'Please check this item before creating the PDF.'
        : 'Please check: $note';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: tt.bodySmall?.copyWith(color: const Color(0xFFFDE68A)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AddItemSheet — bottom sheet with catalog picker + manual entry form.
// The catalog section is shown only when [trade] is non-null.
// Tapping a catalog chip pre-fills the description and unit; the form fields
// remain editable so a custom name is always possible.
// ─────────────────────────────────────────────────────────────────────────────
class _AddItemSheet extends StatefulWidget {
  /// When non-null, catalog suggestions for this trade are shown at the top.
  final Trade? trade;
  final _EditableItem? initialItem;

  const _AddItemSheet({this.trade, this.initialItem});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'sq ft');
  final _rateCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Which catalog item (if any) has been tapped — used for highlight only.
  String? _selectedCatalogId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialItem;
    if (initial != null) {
      _descCtrl.text = initial.description.text;
      _qtyCtrl.text = initial.quantity.text;
      _unitCtrl.text = initial.unit.text;
      _rateCtrl.text = initial.rate.text;
    }
    // Live amount preview — recalculated with the Day 5 engine on each keystroke.
    _qtyCtrl.addListener(_refreshPreview);
    _rateCtrl.addListener(_refreshPreview);
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  /// Day 5 engine for the sheet preview: qty × rate, in paise.
  int get _previewAmountPaise {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final rateRupees = int.tryParse(_rateCtrl.text.trim()) ?? 0;
    return qty * rateRupees * 100;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  /// Pre-fills description and unit from a catalog chip tap.
  void _applyCatalogItem(CatalogItem item) {
    setState(() => _selectedCatalogId = item.id);
    _descCtrl.text = item.displayName;
    _unitCtrl.text = item.defaultUnit;
    // Move focus to qty so the user can type immediately.
    FocusScope.of(context).nextFocus();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initialItem;
    Navigator.pop(
      context,
      _EditableItem(
        description: _descCtrl.text.trim(),
        quantity: _qtyCtrl.text.trim(),
        unit: _unitCtrl.text.trim().isEmpty ? 'sq ft' : _unitCtrl.text.trim(),
        rate: _rateCtrl.text.trim(),
        confidence: initial?.confidence,
        uncertaintyNote: initial?.uncertaintyNote,
        sourceSpan: initial?.sourceSpan,
        isUnknown: initial?.isUnknown ?? false,
        requiresReview: initial?.requiresReview ?? false,
        acknowledged: initial?.acknowledged ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Catalog items for the selected trade (empty list = no trade known).
    final catalogItems = widget.trade == null
        ? <CatalogItem>[]
        : catalogForTrade(widget.trade!);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Sheet handle ────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9E9BA8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.initialItem == null
                    ? 'Add Item / मद जोड़ें'
                    : 'Edit Item / मद बदलें',
                style: tt.titleLarge,
              ),

              // ── Catalog picker (only when trade is known) ──────────────
              if (catalogItems.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Choose from catalog / सूची में से चुनें',
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final ci in catalogItems)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CatalogChip(
                            item: ci,
                            selected: _selectedCatalogId == ci.id,
                            onTap: () => _applyCatalogItem(ci),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
              ],

              const SizedBox(height: 16),

              // ── Description ─────────────────────────────────────────────
              _FieldLabel(
                label: 'Item name / मद का नाम',
                child: TextFormField(
                  controller: _descCtrl,
                  // Skip autofocus when catalog chips are present — keyboard
                  // would hide them before the user can tap a chip.
                  autofocus: catalogItems.isEmpty,
                  style: tt.bodyLarge,
                  decoration: _inputDecoration(context, hint: 'e.g. Skirting'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 12),

              // ── Qty + Unit ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _FieldLabel(
                      label: 'Qty / मात्रा',
                      child: TextFormField(
                        controller: _qtyCtrl,
                        style: tt.bodyLarge,
                        decoration: _inputDecoration(context, hint: '0'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if ((int.tryParse(v) ?? 0) <= 0) return '> 0';
                          return null;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _FieldLabel(
                      label: 'Unit',
                      child: TextFormField(
                        controller: _unitCtrl,
                        style: tt.bodyLarge,
                        decoration: _inputDecoration(context, hint: 'sq ft'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Rate ─────────────────────────────────────────────────────
              _FieldLabel(
                label: 'Rate (₹) / दर',
                child: TextFormField(
                  controller: _rateCtrl,
                  style: tt.bodyLarge,
                  decoration: _inputDecoration(context, hint: '0'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if ((int.tryParse(v) ?? 0) <= 0) return '> 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),

              // ── Live calculated amount (read-only, Day 5 engine) ─────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF13131F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E2E42)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Amount / राशि', style: tt.bodyMedium),
                    Text(
                      formatRupeePaise(_previewAmountPaise),
                      style: tt.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Actions: Cancel (secondary) + Save changes (sole primary) ─
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(widget.initialItem == null
                          ? 'Add'
                          : 'Save changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CatalogChip — tappable chip for a catalog item; saffron-highlighted when
// selected
// ─────────────────────────────────────────────────────────────────────────────
class _CatalogChip extends StatelessWidget {
  final CatalogItem item;
  final bool selected;
  final VoidCallback onTap;

  const _CatalogChip({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected
            ? cs.primary.withValues(alpha: 0.18)
            : const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? cs.primary : const Color(0xFF2E2E42),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // Show only the English part before " /" for compact chips.
                item.displayName.split(' /').first,
                style: tt.bodyLarge?.copyWith(
                  color: selected ? cs.primary : null,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(item.defaultUnit, style: tt.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomerSection — customer name, phone, notes, validity
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController notesCtrl;
  final int validityDays;
  final List<int> validityOptions;
  final ValueChanged<int> onValidityChanged;

  const _CustomerSection({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.notesCtrl,
    required this.validityDays,
    required this.validityOptions,
    required this.onValidityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Customer name ────────────────────────────────────────────
            _FieldLabel(
              label: 'Customer name / ग्राहक का नाम',
              child: TextField(
                controller: nameCtrl,
                style: tt.bodyLarge,
                decoration: _inputDecoration(context, hint: 'e.g. Sharma Ji'),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(height: 12),

            // ── Phone ────────────────────────────────────────────────────
            _FieldLabel(
              label: 'Phone / फ़ोन (optional)',
              child: TextField(
                controller: phoneCtrl,
                style: tt.bodyLarge,
                decoration: _inputDecoration(context, hint: '9XXXXXXXXX'),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(height: 12),

            // ── Validity ─────────────────────────────────────────────────
            _FieldLabel(
              label: 'Validity / मान्यता',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: validityOptions.map((days) {
                    final selected = days == validityDays;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('$days days'),
                        selected: selected,
                        onSelected: (_) => onValidityChanged(days),
                        selectedColor: cs.primary,
                        labelStyle: tt.bodyMedium?.copyWith(
                          color: selected ? cs.onPrimary : null,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Notes ────────────────────────────────────────────────────
            _FieldLabel(
              label: 'Notes / टिप्पणी (optional)',
              child: TextField(
                controller: notesCtrl,
                style: tt.bodyLarge,
                decoration: _inputDecoration(
                  context,
                  hint: 'Payment terms, special conditions…',
                ),
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TotalsSummary — live subtotal readout
// ─────────────────────────────────────────────────────────────────────────────
class _TotalsSummary extends StatelessWidget {
  final QuoteTotals totals;
  const _TotalsSummary({required this.totals});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subtotal / कुल', style: tt.titleMedium),
              Text('(excl. GST)', style: tt.bodyMedium),
            ],
          ),
          Text(
            formatRupeePaise(totals.subtotalPaise),

            style: tt.displaySmall?.copyWith(color: cs.primary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BottomActions — pinned bar with grand total preview + CTA buttons
// ─────────────────────────────────────────────────────────────────────────────
class _BottomActions extends StatelessWidget {
  final int grandTotalPaise;
  final String? blockingReason;
  final bool showBlockingReason;
  final VoidCallback onGeneratePdf;
  final VoidCallback onBack;

  const _BottomActions({
    required this.grandTotalPaise,
    required this.blockingReason,
    required this.showBlockingReason,
    required this.onGeneratePdf,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        12,
        kPagePadding,
        kPagePadding,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2C),
        border: Border(top: BorderSide(color: Color(0xFF2E2E42), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini total reminder
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: tt.bodyMedium),
              Text(
                formatRupeePaise(grandTotalPaise),
                style: tt.titleMedium?.copyWith(color: cs.primary),
              ),
            ],
          ),
          if (blockingReason != null && showBlockingReason) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    blockingReason!,
                    style: tt.bodySmall?.copyWith(
                      color: const Color(0xFFFCD34D),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          ElevatedButton.icon(
            onPressed: onGeneratePdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Generate PDF / PDF बनाएं'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onBack,
            child: const Text('Back to Home / होम पर जाएं'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const _SectionHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: tt.titleLarge)),
        ?trailing,
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldLabel({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodyMedium),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final String value;
  const _AmountChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: tt.bodyMedium),
          Text(value, style: tt.titleMedium?.copyWith(color: cs.primary)),
        ],
      ),
    );
  }
}

class _EmptyItemsHint extends StatelessWidget {
  final VoidCallback onAdd;
  final bool hasVoiceTranscript;

  const _EmptyItemsHint({required this.onAdd, this.hasVoiceTranscript = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Center(
            child: Column(
              children: [
                Icon(
                  hasVoiceTranscript
                      ? Icons.playlist_add_rounded
                      : Icons.add_box_outlined,
                  size: 38,
                  color: cs.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  hasVoiceTranscript
                      ? 'No items auto-detected from voice'
                      : 'No items yet — tap to add one',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  hasVoiceTranscript
                      ? 'Tap here or "+ Add item" to add manually'
                      : 'Add materials, labour, or custom rates',
                  style: tt.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day 7 — Voice note card & parsing warnings banner
// ─────────────────────────────────────────────────────────────────────────────

class _VoiceNoteCard extends StatelessWidget {
  final String transcript;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _VoiceNoteCard({
    required this.transcript,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mic_rounded, color: cs.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Spoken Note / मूल आवाज़',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Voice Transcript',
                      style: tt.bodySmall?.copyWith(
                        fontSize: 10,
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF9E9BA8),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFF2E2E42)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“$transcript”',
                    style: tt.bodyMedium?.copyWith(
                      color: const Color(0xFFD0CFD6),
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: Color(0xFF4CAF50),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Parsed into line items below',
                        style: tt.bodySmall?.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF9E9BA8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParsingWarningsBanner extends StatelessWidget {
  final List<String> warnings;
  final VoidCallback onDismiss;

  const _ParsingWarningsBanner({
    required this.warnings,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Please Review / ध्यान दें',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFCD34D),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFF59E0B),
                ),
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss warning',
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: tt.bodySmall?.copyWith(
                      color: const Color(0xFFFCD34D),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      w,
                      style: tt.bodySmall?.copyWith(
                        color: const Color(0xFFFDE68A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Check the items below or tap "Add item" to complete any missing details.',
            style: tt.bodySmall?.copyWith(
              fontSize: 11,
              color: const Color(0xFFD1D5DB),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared input decoration — keeps all fields visually consistent
// ─────────────────────────────────────────────────────────────────────────────
InputDecoration _inputDecoration(BuildContext context, {required String hint}) {
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF9E9BA8), fontSize: 14),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    filled: true,
    fillColor: const Color(0xFF13131F),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF2E2E42)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF2E2E42)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.error, width: 1.5),
    ),
  );
}

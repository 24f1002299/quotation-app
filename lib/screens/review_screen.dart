import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/quote.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mutable line-item data class used only within this screen.
// The immutable QuoteLineItem model (used for calculations) is created on
// demand from these fields.
// ─────────────────────────────────────────────────────────────────────────────
class _EditableItem {
  TextEditingController description;
  TextEditingController quantity;
  TextEditingController unit;
  TextEditingController rate; // in whole rupees (not paise) for UX clarity

  _EditableItem({
    String description = '',
    String quantity = '',
    String unit = 'sq ft',
    String rate = '',
  })  : description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        rate = TextEditingController(text: rate);

  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    rate.dispose();
  }

  /// Returns whole-rupee amount, or 0 if either field is empty/invalid.
  int get amountRupees {
    final q = int.tryParse(quantity.text.trim()) ?? 0;
    final r = int.tryParse(rate.text.trim()) ?? 0;
    return q * r;
  }

  /// Returns paise amount (amount × 100).
  int get amountPaise => amountRupees * 100;

  QuoteLineItem toLineItem() => QuoteLineItem(
        description: description.text.trim().isEmpty
            ? 'Unnamed item'
            : description.text.trim(),
        quantity: int.tryParse(quantity.text.trim()) ?? 0,
        unit: unit.text.trim().isEmpty ? 'unit' : unit.text.trim(),
        // rate field is in rupees, model stores paise
        unitRatePaise: (int.tryParse(rate.text.trim()) ?? 0) * 100,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ReviewScreen — editable quotation review & customer details
// Accepts an optional initial list of line items (from voice/parse on Day 7).
// When called with no arguments it starts with the Day 2 demo fixture so
// the existing widget test keeps passing.
// ─────────────────────────────────────────────────────────────────────────────
class ReviewScreen extends StatefulWidget {
  /// Optional pre-populated line items (passed from voice flow on Day 7).
  final List<QuoteLineItem>? initialLineItems;

  const ReviewScreen({super.key, this.initialLineItems});

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

  @override
  void initState() {
    super.initState();
    final seed = widget.initialLineItems ??
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
          ),
        )
        .toList();
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
  int get _subtotalPaise =>
      _items.fold(0, (sum, item) => sum + item.amountPaise);

  // ── Mutations ──────────────────────────────────────────────────────────────
  void _deleteItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  void _addItem(_EditableItem item) {
    setState(() => _items.add(item));
  }

  /// Called from each controller's listener to refresh totals.
  void _onFieldChanged() => setState(() {});

  void _attachListeners(_EditableItem item) {
    item.quantity.addListener(_onFieldChanged);
    item.rate.addListener(_onFieldChanged);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Quote / जाँचें'),
        actions: [
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
                    _EmptyItemsHint(onAdd: _showAddItemSheet),

                  ..._items.asMap().entries.map(
                        (entry) => _LineItemCard(
                          key: ObjectKey(entry.value),
                          item: entry.value,
                          index: entry.key,
                          onDelete: () => _deleteItem(entry.key),
                          onChanged: _onFieldChanged,
                        ),
                      ),

                  const SizedBox(height: 20),

                  // ── Totals summary ────────────────────────────────────
                  _TotalsSummary(subtotalPaise: _subtotalPaise),

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
                    onValidityChanged: (v) =>
                        setState(() => _validityDays = v),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),

            // ── Fixed bottom action bar ───────────────────────────────────
            _BottomActions(
              subtotalPaise: _subtotalPaise,
              onGeneratePdf: () {
                // Day 8 will wire this up.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PDF generation coming on Day 8'),
                    behavior: SnackBarBehavior.floating,
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
      builder: (_) => const _AddItemSheet(),
    ).then((item) {
      if (item == null) return;
      _attachListeners(item);
      _addItem(item);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LineItemCard — the main editable card for a single line item
// ─────────────────────────────────────────────────────────────────────────────
class _LineItemCard extends StatelessWidget {
  final _EditableItem item;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _LineItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Description + delete button ────────────────────────
            Row(
              children: [
                Expanded(
                  child: _FieldLabel(
                    label: 'Item / मद',
                    child: TextField(
                      controller: item.description,
                      onChanged: (_) => onChanged(),
                      style: tt.titleMedium,
                      decoration: _inputDecoration(
                        context,
                        hint: 'e.g. Tile Labour',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: cs.error, size: 22),
                  tooltip: 'Delete item / मद हटाएं',
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Row 2: Qty | Unit | Rate ───────────────────────────────────
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _FieldLabel(
                    label: 'Qty / मात्रा',
                    child: TextField(
                      controller: item.quantity,
                      onChanged: (_) => onChanged(),
                      style: tt.bodyLarge,
                      decoration: _inputDecoration(context, hint: '0'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _FieldLabel(
                    label: 'Unit',
                    child: TextField(
                      controller: item.unit,
                      onChanged: (_) => onChanged(),
                      style: tt.bodyLarge,
                      decoration: _inputDecoration(context, hint: 'sq ft'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _FieldLabel(
                    label: 'Rate ₹ / दर',
                    child: TextField(
                      controller: item.rate,
                      onChanged: (_) => onChanged(),
                      style: tt.bodyLarge,
                      decoration: _inputDecoration(context, hint: '0'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Row 3: Amount (computed, read-only) ───────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: _AmountChip(
                label: 'Amount / राशि',
                value: formatRupee(item.amountRupees),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AddItemSheet — bottom sheet with fields to add a new line item
// ─────────────────────────────────────────────────────────────────────────────
class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet();

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'sq ft');
  final _rateCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // Return a fresh _EditableItem with current values
    Navigator.pop(
      context,
      _EditableItem(
        description: _descCtrl.text.trim(),
        quantity: _qtyCtrl.text.trim(),
        unit: _unitCtrl.text.trim().isEmpty ? 'sq ft' : _unitCtrl.text.trim(),
        rate: _rateCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // Shift sheet up when keyboard appears
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sheet handle ──────────────────────────────────────────────
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

            Text('Add Item / मद जोड़ें', style: tt.titleLarge),
            const SizedBox(height: 20),

            // ── Description ───────────────────────────────────────────────
            _FieldLabel(
              label: 'Item name / मद का नाम',
              child: TextFormField(
                controller: _descCtrl,
                autofocus: true,
                style: tt.bodyLarge,
                decoration: _inputDecoration(context, hint: 'e.g. Skirting'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(height: 12),

            // ── Qty + Unit ────────────────────────────────────────────────
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
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Rate ──────────────────────────────────────────────────────
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
            const SizedBox(height: 24),

            // ── Actions ───────────────────────────────────────────────────
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
                    label: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
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
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.normal,
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
  final int subtotalPaise;
  const _TotalsSummary({required this.subtotalPaise});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
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
            formatRupeePaise(subtotalPaise),
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
  final int subtotalPaise;
  final VoidCallback onGeneratePdf;
  final VoidCallback onBack;

  const _BottomActions({
    required this.subtotalPaise,
    required this.onGeneratePdf,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          kPagePadding, 12, kPagePadding, kPagePadding),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        border: Border(
          top: BorderSide(color: const Color(0xFF2E2E42), width: 1),
        ),
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
                formatRupeePaise(subtotalPaise),
                style: tt.titleMedium?.copyWith(color: cs.primary),
              ),
            ],
          ),
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
        if (trailing != null) trailing!,
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
        color: cs.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: tt.bodyMedium),
          Text(
            value,
            style: tt.titleMedium?.copyWith(color: cs.primary),
          ),
        ],
      ),
    );
  }
}

class _EmptyItemsHint extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyItemsHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.add_box_outlined,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text('No items yet — tap to add one', style: tt.bodyMedium),
              ],
            ),
          ),
        ),
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
    hintStyle: TextStyle(color: const Color(0xFF9E9BA8), fontSize: 14),
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

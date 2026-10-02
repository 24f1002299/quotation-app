import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/service_item.dart';
import '../../storage/service_item_repository.dart';
import '../../templates/template_data.dart';
import '../../utils/rupee_format.dart';
import 'editable_item.dart';
import 'small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AddItemSheet — bottom sheet with the user's services + manual entry form.
// Used for both adding and editing (via [initialItem]).
// The service list is shown only when [businessType] is non-null.
// Tapping a service chip pre-fills description, unit and rate; the form fields
// remain editable so a custom name is always possible.
// Field order is contractual: description, quantity, unit, rate.
// ─────────────────────────────────────────────────────────────────────────────
class AddItemSheet extends StatefulWidget {
  /// When non-null, the user's services for this business type are offered.
  final BusinessType? businessType;
  final EditableItem? initialItem;

  const AddItemSheet({super.key, this.businessType, this.initialItem});

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'sq ft');
  final _rateCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Which of the user's services (if any) has been tapped.
  String? _selectedServiceId;

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

  /// Pre-fills description and unit from a service chip tap.
  void _applyServiceItem(ServiceItem item) {
    setState(() => _selectedServiceId = item.id);
    _descCtrl.text = item.name;
    _unitCtrl.text = item.unit;
    if (item.ratePaise > 0) _rateCtrl.text = '';
    // Move focus to qty so the user can type immediately.
    FocusScope.of(context).nextFocus();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initialItem;
    Navigator.pop(
      context,
      EditableItem(
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
        // Keep the matched service (or the chip the user tapped).
        serviceItemId: _selectedServiceId ?? initial?.serviceItemId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;


    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: theme.dividerColor,
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

              // ── The user's own service list (only when type is known) ─────
              if (widget.businessType != null) ...[
                const SizedBox(height: 14),
                Text('My services / मेरी सेवाएं', style: tt.bodyMedium),
                const SizedBox(height: 8),
                FutureBuilder<List<ServiceItem>>(
                  future: ServiceItemRepository
                      .getActiveForBusinessType(widget.businessType!),
                  builder: (context, snap) {
                    final services = snap.data ?? const <ServiceItem>[];
                    if (services.isEmpty) {
                      return Text(
                        'No services yet — type the item below.',
                        style: tt.bodyMedium,
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final service in services)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ServiceChip(
                                service: service,
                                selected: _selectedServiceId == service.id,
                                onTap: () => _applyServiceItem(service),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
              ],

              const SizedBox(height: 16),

              // ── Description ─────────────────────────────────────────────
              FieldLabel(
                label: 'Item name / मद का नाम',
                child: TextFormField(
                  controller: _descCtrl,
                  // Skip autofocus when catalog chips are present — keyboard
                  // would hide them before the user can tap a chip.
                  autofocus: widget.businessType == null,
                  style: tt.bodyLarge,
                  decoration:
                      reviewInputDecoration(context, hint: 'e.g. Skirting'),
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
                    child: FieldLabel(
                      label: 'Qty / मात्रा',
                      child: TextFormField(
                        controller: _qtyCtrl,
                        style: tt.bodyLarge,
                        decoration:
                            reviewInputDecoration(context, hint: '0'),
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
                    child: FieldLabel(
                      label: 'Unit',
                      child: TextFormField(
                        controller: _unitCtrl,
                        style: tt.bodyLarge,
                        decoration: reviewInputDecoration(context,
                            hint: 'sq ft'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Rate ─────────────────────────────────────────────────────
              FieldLabel(
                label: 'Rate (₹) / दर',
                child: TextFormField(
                  controller: _rateCtrl,
                  style: tt.bodyLarge,
                  decoration: reviewInputDecoration(context, hint: '0'),
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
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Amount / राशि', style: tt.bodyMedium),
                    Text(
                      formatRupeePaise(_previewAmountPaise),
                      style: tt.titleMedium?.copyWith(
                        color: cs.primary,
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
// ServiceChip — tappable chip for one of the user's services
// ─────────────────────────────────────────────────────────────────────────────
class ServiceChip extends StatelessWidget {
  final ServiceItem service;
  final bool selected;
  final VoidCallback onTap;

  const ServiceChip({
    super.key,
    required this.service,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected
            ? cs.primary.withValues(alpha: 0.18)
            : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? cs.primary : theme.dividerColor,
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
                service.name,
                style: tt.bodyLarge?.copyWith(
                  color: selected ? cs.primary : null,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(service.unit, style: tt.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

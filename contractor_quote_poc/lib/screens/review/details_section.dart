import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/quote_ids.dart';
import 'small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MoreDetailsSection — progressive disclosure for commercial details
// (quote #, date, validity, GST, advance, notes, editable terms)
// ─────────────────────────────────────────────────────────────────────────────
class MoreDetailsSection extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final String quoteId;
  final String displayNumber;
  final DateTime quoteDate;
  final ValueChanged<DateTime> onDateChanged;
  final int validityDays;
  final List<int> validityOptions;
  final ValueChanged<int> onValidityChanged;
  final int? gstPercent;
  final List<int> gstOptions;
  final ValueChanged<int?> onGstChanged;
  final TextEditingController advancePercentCtrl;
  final TextEditingController advanceTextCtrl;
  final ValueChanged<int?> onAdvancePercentSelected;
  final TextEditingController notesCtrl;
  final TextEditingController termsCtrl;
  final VoidCallback onResetTerms;

  const MoreDetailsSection({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.quoteId,
    required this.displayNumber,
    required this.quoteDate,
    required this.onDateChanged,
    required this.validityDays,
    required this.validityOptions,
    required this.onValidityChanged,
    required this.gstPercent,
    required this.gstOptions,
    required this.onGstChanged,
    required this.advancePercentCtrl,
    required this.advanceTextCtrl,
    required this.onAdvancePercentSelected,
    required this.notesCtrl,
    required this.termsCtrl,
    required this.onResetTerms,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('dd MMM yyyy');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header tile with expand/collapse trigger
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'More quote details / अतिरिक्त विवरण',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$displayNumber • ${validityDays}d validity • '
                          '${gstPercent == null ? "No GST" : "GST $gstPercent%"}',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                    ),
                    label: Text(isExpanded ? 'Hide' : 'Expand'),
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Quote Number & Offline ID ──────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Quote Number / कोटेशन संख्या',
                                style: tt.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              displayNumber,
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Offline ID / पहचान', style: tt.labelSmall),
                            Text(
                              shortId(quoteId),
                              style: tt.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 2. Quotation Date ─────────────────────────────────────
                  FieldLabel(
                    label: 'Quote Date / दिनांक',
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: quoteDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) onDateChanged(picked);
                      },
                      icon:
                          const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(dateFormat.format(quoteDate)),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 3. Validity ───────────────────────────────────────────
                  FieldLabel(
                    label: 'Validity / मान्यता (दिन)',
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
                  const SizedBox(height: 16),

                  // ── 4. GST Toggle / Rate ───────────────────────────────────
                  FieldLabel(
                    label: 'GST / जीएसटी कर',
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: const Text('No GST (0%)'),
                              selected: gstPercent == null,
                              onSelected: (_) => onGstChanged(null),
                              selectedColor: cs.primary,
                              labelStyle: tt.bodyMedium?.copyWith(
                                color:
                                    gstPercent == null ? cs.onPrimary : null,
                                fontWeight: gstPercent == null
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          ...gstOptions.map((rate) {
                            final selected = gstPercent == rate;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('$rate% GST'),
                                selected: selected,
                                onSelected: (_) => onGstChanged(rate),
                                selectedColor: cs.primary,
                                labelStyle: tt.bodyMedium?.copyWith(
                                  color: selected ? cs.onPrimary : null,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 5. Advance percentage & text ──────────────────────────
                  FieldLabel(
                    label: 'Advance / अग्रिम भुगतान (optional)',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('None'),
                                selected:
                                    advancePercentCtrl.text.trim().isEmpty,
                                onSelected: (_) =>
                                    onAdvancePercentSelected(null),
                              ),
                              const SizedBox(width: 8),
                              for (final p in [10, 20, 30, 50]) ...[
                                ChoiceChip(
                                  label: Text('$p%'),
                                  selected:
                                      advancePercentCtrl.text.trim() == '$p',
                                  onSelected: (_) =>
                                      onAdvancePercentSelected(p),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: advanceTextCtrl,
                          style: tt.bodyLarge,
                          decoration: reviewInputDecoration(
                            context,
                            hint:
                                'e.g. 50% advance before tile delivery / ५०% अग्रिम',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 6. Notes ──────────────────────────────────────────────
                  FieldLabel(
                    label: 'Notes / टिप्पणी (optional)',
                    child: TextField(
                      controller: notesCtrl,
                      style: tt.bodyLarge,
                      decoration: reviewInputDecoration(
                        context,
                        hint: 'Payment terms, special conditions…',
                      ),
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 7. Editable Terms & Conditions ────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Terms & Conditions / नियम व शर्तें',
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: onResetTerms,
                        child: const Text('Reset defaults / डिफ़ॉल्ट'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: termsCtrl,
                    style: tt.bodyMedium,
                    decoration: reviewInputDecoration(
                      context,
                      hint: 'Enter terms (one condition per line)',
                    ),
                    maxLines: 4,
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

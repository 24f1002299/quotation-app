import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../utils/rupee_format.dart';
import 'editable_item.dart';
import 'small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LineItemCard — clean scan card (design.md §4 Review quote).
// Tapping the card or Edit/Fix now opens the bottom-sheet form; the card
// itself never shows inline text fields so totals stay trustworthy.
// Attention items carry a full amber border (no reordering — order carries
// meaning for move up/down).
// ─────────────────────────────────────────────────────────────────────────────
class LineItemCard extends StatelessWidget {
  final EditableItem item;
  final int index;
  final int amountPaise;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onAcknowledge;

  /// One-tap save to the user's service list. Null hides the action; the
  /// screen passes it only for unlisted items worth keeping.
  final VoidCallback? onAddToList;

  const LineItemCard({
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
    this.onAddToList,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final needsAttention = item.requiresReview && !item.acknowledged;

    final description = item.description.text.trim().isEmpty
        ? AppStrings.of(context, 'unnamed_item')
        : item.description.text.trim();
    final qtyText = item.quantity.text.trim().isEmpty
        ? '—'
        : item.quantity.text.trim();
    final unitText = item.unit.text.trim().isEmpty
        ? AppStrings.of(context, 'unit')
        : item.unit.text.trim();
    final rateText =
        item.rate.text.trim().isEmpty ? '—' : '₹${item.rate.text.trim()}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: needsAttention
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFF59E0B), width: 2),
            )
          : null,
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
                      AppStrings.of(context, 'item_number')
                          .replaceAll('{n}', '${index + 1}'),
                      style: tt.bodyMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (needsAttention)
                    Icon(
                      Icons.warning_amber_rounded,
                      color: const Color(0xFFB45309),
                      semanticLabel:
                          AppStrings.of(context, 'needs_attention'),
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
                child: AmountChip(
                  label: AppStrings.of(context, 'amount'),
                  value: formatRupeePaise(amountPaise),
                ),
              ),
              if (needsAttention) ...[
                const SizedBox(height: 10),
                UncertaintyNotice(item: item),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.build_outlined, size: 18),
                      label: Text(AppStrings.of(context, 'fix_now')),
                    ),
                    if (onAddToList != null)
                      OutlinedButton.icon(
                        onPressed: onAddToList,
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label:
                            Text(AppStrings.of(context, 'add_to_my_list')),
                      ),
                    OutlinedButton.icon(
                      onPressed: onAcknowledge,
                      icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18),
                      label: Text(
                        item.isUnknown
                            ? AppStrings.of(context, 'i_checked_this')
                            : AppStrings.of(context, 'mark_as_checked'),
                      ),
                    ),
                  ],
                ),
              ] else if (item.requiresReview) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(AppStrings.of(context, 'checked'),
                        style: tt.bodySmall),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              // Compact text actions — tap anywhere on the card to edit.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(AppStrings.of(context, 'edit')),
                  ),
                  TextButton.icon(
                    onPressed: onDuplicate,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: Text(AppStrings.of(context, 'duplicate')),
                  ),
                  IconButton(
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    tooltip: AppStrings.of(context, 'move_up')
                        .replaceAll('{n}', '${index + 1}'),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                    tooltip: AppStrings.of(context, 'move_down')
                        .replaceAll('{n}', '${index + 1}'),
                    visualDensity: VisualDensity.compact,
                  ),
                  TextButton.icon(
                    // Compact labelled delete with confirmation dialog —
                    // never gesture-only deletion.
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: Text(AppStrings.of(context, 'delete_item')),
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

/// Inline explanation of why an item needs attention.
/// Light amber surface — never the only signal (paired with icon + text).
class UncertaintyNotice extends StatelessWidget {
  final EditableItem item;

  const UncertaintyNotice({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final note = item.uncertaintyNote?.trim();
    final message = item.isUnknown
        ? AppStrings.of(context, 'unknown_item').replaceAll('{note}',
            note == null || note.isEmpty
                ? AppStrings.of(context, 'check_work_details')
                : note)
        : note == null || note.isEmpty
        ? AppStrings.of(context, 'check_before_pdf')
        : AppStrings.of(context, 'please_check')
            .replaceAll('{note}', note);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: tt.bodySmall),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../utils/rupee_format.dart';
import 'editable_item.dart';
import 'small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LineItemCard — clean scan card (design.md §4 Review quote).
// Tapping the card or Fix now opens the bottom-sheet form; the card itself
// never shows inline text fields so totals stay trustworthy.
//
// One primary action per card (Fix now, only when attention is needed).
// Edit / Duplicate / Delete live behind the ⋮ overflow menu; move up/down
// stay as compact arrows since order carries meaning. Warnings use amber
// fills, never border boxes.
// ─────────────────────────────────────────────────────────────────────────────
class LineItemCard extends StatefulWidget {
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
  State<LineItemCard> createState() => _LineItemCardState();
}

class _LineItemCardState extends State<LineItemCard> {
  bool _issueExpanded = false;

  String _issueMessage(BuildContext context) {
    final note = widget.item.uncertaintyNote?.trim();
    if (widget.item.isUnknown) {
      return AppStrings.of(context, 'unknown_item').replaceAll(
        '{note}',
        note == null || note.isEmpty
            ? AppStrings.of(context, 'check_work_details')
            : note,
      );
    }
    if (note == null || note.isEmpty) {
      return AppStrings.of(context, 'check_before_pdf');
    }
    return AppStrings.of(context, 'please_check').replaceAll('{note}', note);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final index = widget.index;
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
    final rateText = item.rate.text.trim().isEmpty
        ? '—'
        : '₹${item.rate.text.trim()}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: widget.onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.of(
                        context,
                        'item_number',
                      ).replaceAll('{n}', '${index + 1}'),
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (needsAttention)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB45309),
                        size: 22,
                      ),
                    ),
                  IconButton(
                    onPressed: widget.onMoveUp,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    tooltip: AppStrings.of(
                      context,
                      'move_up',
                    ).replaceAll('{n}', '${index + 1}'),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: widget.onMoveDown,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                    tooltip: AppStrings.of(
                      context,
                      'move_down',
                    ).replaceAll('{n}', '${index + 1}'),
                    visualDensity: VisualDensity.compact,
                  ),
                  PopupMenuButton<String>(
                    tooltip: AppStrings.of(context, 'more_actions'),
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          widget.onEdit();
                        case 'duplicate':
                          widget.onDuplicate();
                        case 'delete':
                          widget.onDelete();
                      }
                    },
                    itemBuilder: (menuContext) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit_outlined, size: 20),
                            const SizedBox(width: 12),
                            Text(AppStrings.of(menuContext, 'edit')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Row(
                          children: [
                            const Icon(Icons.copy_outlined, size: 20),
                            const SizedBox(width: 12),
                            Text(AppStrings.of(menuContext, 'duplicate')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: cs.error,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppStrings.of(menuContext, 'delete_item'),
                              style: TextStyle(color: cs.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  description,
                  style: tt.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Quantity × rate line + read-only amount pill.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '$qtyText $unitText × $rateText',
                      style: tt.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AmountChip(
                    label: AppStrings.of(context, 'amount'),
                    value: formatRupeePaise(widget.amountPaise),
                    attention: needsAttention,
                  ),
                ],
              ),
              if (needsAttention) ...[
                const SizedBox(height: 10),
                _IssueRow(
                  message: _issueMessage(context),
                  expanded: _issueExpanded,
                  onToggle: () =>
                      setState(() => _issueExpanded = !_issueExpanded),
                ),
                const SizedBox(height: 10),
                // Single primary action, full width.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onEdit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    icon: const Icon(Icons.build_outlined, size: 18),
                    label: Text(AppStrings.of(context, 'fix_now')),
                  ),
                ),
                const SizedBox(height: 4),
                // Secondary ghost actions.
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: widget.onAcknowledge,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          item.isUnknown
                              ? AppStrings.of(context, 'i_checked_this')
                              : AppStrings.of(context, 'mark_as_checked'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (widget.onAddToList != null)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: widget.onAddToList,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 18,
                          ),
                          label: Text(
                            AppStrings.of(context, 'add_to_my_list'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                    Text(
                      AppStrings.of(context, 'checked'),
                      style: tt.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-line amber-fill issue row. Truncates with "more"; the whole row
/// is tappable to expand (no tiny touch targets).
class _IssueRow extends StatelessWidget {
  final String message;
  final bool expanded;
  final VoidCallback onToggle;

  const _IssueRow({
    required this.message,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Color(0xFFB45309),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: Text(
                  message,
                  style: tt.bodySmall?.copyWith(color: const Color(0xFF92400E)),
                  maxLines: expanded ? null : 1,
                  overflow: expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.of(context, expanded ? 'hide' : 'expand'),
              style: tt.bodySmall?.copyWith(
                color: const Color(0xFF92400E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

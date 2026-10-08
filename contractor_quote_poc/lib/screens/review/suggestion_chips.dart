import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/quote_flags.dart';
import '../quote_flag_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SuggestionChips — inline, dismissable quick-confirm nudges.
// Replaces the old "Please confirm (N)" card: a horizontally scrollable chip
// row where each chip opens a bottom sheet for action, keeping the main
// scroll clean. Chips dismiss with a slide-out (vertical Dismissible so the
// horizontal scroll never fights the gesture).
// ─────────────────────────────────────────────────────────────────────────────

/// Stable per-flag key so the screen can remember dismissed nudges.
String suggestionChipKey(QuoteFlag flag) =>
    '${flag.type.name}_${flag.itemIndex ?? -1}';

String _chipLabel(BuildContext context, QuoteFlag flag) {
  switch (flag.type) {
    case QuoteFlagType.unusualRate:
      return AppStrings.of(context, 'chip_rate_high');
    case QuoteFlagType.missingRate:
      return AppStrings.of(context, 'chip_rate_missing');
    case QuoteFlagType.uncertainQuantity:
      return AppStrings.of(context, 'chip_qty_check');
    case QuoteFlagType.unknownItem:
      return AppStrings.of(context, 'chip_unknown_item');
    case QuoteFlagType.missingCustomer:
      return AppStrings.of(context, 'add_customer');
    case QuoteFlagType.failedSync:
    case QuoteFlagType.staleServiceList:
      return flag.actionLabel;
  }
}

class SuggestionChips extends StatelessWidget {
  final List<QuoteFlag> warnings;
  final Set<String> dismissedKeys;
  final void Function(QuoteFlag flag) onDismiss;
  final void Function(QuoteFlag flag) onAction;

  const SuggestionChips({
    super.key,
    required this.warnings,
    required this.dismissedKeys,
    required this.onDismiss,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final visible = warnings
        .where((w) => !dismissedKeys.contains(suggestionChipKey(w)))
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Dismissible(
              key: ValueKey(suggestionChipKey(visible[i])),
              direction: DismissDirection.up,
              dismissThresholds: const {DismissDirection.up: 0.4},
              onDismissed: (_) => onDismiss(visible[i]),
              child: ActionChip(
                avatar: Icon(
                  iconForFlag(visible[i].type),
                  size: 18,
                  color: const Color(0xFF92400E),
                ),
                label: Text(_chipLabel(context, visible[i])),
                labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF92400E),
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: const Color(0xFFFEF3C7),
                side: BorderSide.none,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onPressed: () => _openSuggestionSheet(context, visible[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openSuggestionSheet(BuildContext context, QuoteFlag flag) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconForFlag(flag.type),
                      color: const Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _chipLabel(sheetContext, flag),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(flag.message, style: tt.bodyMedium),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onAction(flag);
                  },
                  child: Text(flag.actionLabel),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: cs.onSurfaceVariant,
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onDismiss(flag);
                  },
                  child: Text(AppStrings.of(sheetContext, 'later')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

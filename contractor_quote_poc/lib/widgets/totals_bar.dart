import 'package:flutter/material.dart';

import '../models/quote.dart';
import '../screens/quote_flag_widgets.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';

/// Phase 4 extraction — live subtotal/GST readout (was `_TotalsSummary`).
class QuoteTotalsBar extends StatelessWidget {
  final QuoteTotals totals;
  const QuoteTotalsBar({super.key, required this.totals});

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
      child: totals.gstPaise == 0
          ? Row(
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
            )
          : Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal / उप-योग', style: tt.bodyMedium),
                    Text(
                      formatRupeePaise(totals.subtotalPaise),
                      style:
                          tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('GST / कर', style: tt.bodyMedium),
                    Text(
                      formatRupeePaise(totals.gstPaise),
                      style:
                          tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total / कुल राशि', style: tt.titleMedium),
                    Text(
                      formatRupeePaise(totals.grandTotalPaise),
                      style: tt.displaySmall?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Phase 4 extraction — sticky bottom bar with total + CTAs
/// (was `_BottomActions`). Theme-aware: adapts to the light palette
/// instead of the old hardcoded dark container.
class ReviewBottomActions extends StatelessWidget {
  final int grandTotalPaise;
  final String? blockingReason;
  final bool showBlockingReason;
  final String errorReportId;
  final int warningCount;
  final VoidCallback onGeneratePdf;
  final VoidCallback onBack;

  const ReviewBottomActions({
    super.key,
    required this.grandTotalPaise,
    required this.blockingReason,
    required this.showBlockingReason,
    this.errorReportId = '',
    this.warningCount = 0,
    required this.onGeneratePdf,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        kPagePadding,
        12,
        kPagePadding,
        kPagePadding,
      ),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
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
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: cs.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    blockingReason!,
                    style: tt.bodySmall,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: errorReportId.isEmpty
                    ? null
                    : () => showErrorHelpDialog(
                          context,
                          area: 'Review quote',
                          errorReportId: errorReportId,
                        ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: const Text('Get help'),
              ),
            ),
          ] else if (warningCount > 0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: errorReportId.isEmpty
                    ? null
                    : () => showErrorHelpDialog(
                          context,
                          area: 'Review quote',
                          errorReportId: errorReportId,
                        ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text('Get help · $warningCount to confirm'),
              ),
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

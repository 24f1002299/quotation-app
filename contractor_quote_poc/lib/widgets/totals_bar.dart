import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/quote.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';

/// Phase 4 extraction — live subtotal/GST readout (was `_TotalsSummary`).
/// Clean two-row summary: Subtotal (excl. GST) + amount, soft divider, then
/// the GST row when applicable. The grand total lives in the sticky bottom
/// bar, so it is deliberately not repeated here.
class QuoteTotalsBar extends StatelessWidget {
  final QuoteTotals totals;
  const QuoteTotalsBar({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context, 'subtotal'),
                      style: tt.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      AppStrings.of(context, 'excl_gst'),
                      style: tt.bodySmall,
                    ),
                  ],
                ),
                Text(
                  formatRupeePaise(totals.subtotalPaise),
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (totals.gstPaise != 0) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.of(context, 'gst'),
                    style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    formatRupeePaise(totals.gstPaise),
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom bar: total on the left, Generate PDF pill on the right.
/// Errors are never shown here — they live inline on their item cards (a
/// blocking reason still surfaces as a transient snackbar when PDF is
/// tapped, never as persistent bar text).
class ReviewBottomActions extends StatelessWidget {
  final int grandTotalPaise;
  final VoidCallback onGeneratePdf;

  const ReviewBottomActions({
    super.key,
    required this.grandTotalPaise,
    required this.onGeneratePdf,
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
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context, 'total'),
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    formatRupeePaise(grandTotalPaise),
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onGeneratePdf,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: Text(AppStrings.of(context, 'generate_pdf')),
            ),
          ],
        ),
      ),
    );
  }
}

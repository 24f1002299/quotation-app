import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/quote_flags.dart';
import '../utils/error_report.dart';

/// Day 20 — Shared uncertainty / error UI.
///
/// Rules (design.md):
/// - Never use colour alone: every state pairs icon + explicit sentence.
/// - Every error preserves work and offers a concrete next action
///   (Fix now / Add rate / Retry / Create manually).
/// - Technical codes stay behind a `Get help` link with an error-report ID.

IconData iconForFlag(QuoteFlagType type) {
  switch (type) {
    case QuoteFlagType.unknownItem:
      return Icons.help_outline_rounded;
    case QuoteFlagType.uncertainQuantity:
      return Icons.warning_amber_rounded;
    case QuoteFlagType.missingRate:
      return Icons.currency_rupee_rounded;
    case QuoteFlagType.unusualRate:
      return Icons.trending_up_rounded;
    case QuoteFlagType.missingCustomer:
      return Icons.person_outline_rounded;
    case QuoteFlagType.failedSync:
      return Icons.cloud_off_rounded;
    case QuoteFlagType.staleCatalog:
      return Icons.update_rounded;
  }
}

/// Single flag row: icon + sentence + action button. Never blocks layout.
class QuoteFlagRow extends StatelessWidget {
  final QuoteFlag flag;
  final VoidCallback? onAction;

  const QuoteFlagRow({super.key, required this.flag, this.onAction});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isBlocking = flag.isBlocking;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isBlocking
            ? const Color(0xFF3A2A16)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isBlocking
              ? const Color(0xFFF59E0B)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            iconForFlag(flag.type),
            size: 20,
            color: isBlocking
                ? const Color(0xFFF59E0B)
                : Theme.of(context).colorScheme.primary,
            semanticLabel: isBlocking ? 'Needs attention' : 'Please confirm',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flag.message,
                  style: tt.bodySmall?.copyWith(
                    color: isBlocking ? const Color(0xFFFDE68A) : null,
                  ),
                ),
                if (isBlocking)
                  Text(
                    'PDF is paused until this is fixed. Your work is saved.',
                    style: tt.bodySmall?.copyWith(
                      color: const Color(0xFFFDE68A).withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(flag.actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Warning-only section (unusual rate, missing customer…): sage surface,
/// never blocks the PDF. Shown above the totals.
class QuoteWarningsSection extends StatelessWidget {
  final List<QuoteFlag> warnings;
  final void Function(QuoteFlag flag)? onAction;

  const QuoteWarningsSection({
    super.key,
    required this.warnings,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF9FB8AD).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF475841).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18),
              const SizedBox(width: 6),
              Text(
                'Please confirm (${warnings.length})',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'These do not stop the PDF, but please double-check.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final w in warnings)
            QuoteFlagRow(
              flag: w,
              onAction:
                  onAction == null ? null : () => onAction!(w),
            ),
        ],
      ),
    );
  }
}

/// Failed-sync banner with consistent Retry affordance. Work is always
/// preserved (draft stays on the phone).
class SyncFailureBanner extends StatelessWidget {
  final String detail;
  final String errorReportId;
  final VoidCallback onRetry;
  final VoidCallback? onGetHelp;

  const SyncFailureBanner({
    super.key,
    this.detail = '',
    required this.errorReportId,
    required this.onRetry,
    this.onGetHelp,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: cs.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Couldn\u2019t sync changes. They remain saved on this phone.',
                  style: tt.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (detail.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail.trim(), style: tt.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton(
                onPressed: onGetHelp ??
                    () => showErrorHelpDialog(
                          context,
                          area: 'Quote sync',
                          errorReportId: errorReportId,
                        ),
                child: const Text('Get help'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stale-catalog banner with Refresh action.
class StaleCatalogBanner extends StatelessWidget {
  final String detail;
  final VoidCallback onRefresh;

  const StaleCatalogBanner({
    super.key,
    this.detail = '',
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.blue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.update_rounded, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rate list may be outdated.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (detail.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail.trim(), style: tt.bodySmall),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Get help` dialog: explains what happened, shows the error-report ID for
/// support, and lets the user copy it. Support reference only — never an
/// error code in the normal UI.
Future<void> showErrorHelpDialog(
  BuildContext context, {
  required String area,
  required String errorReportId,
}) {
  final line = supportContextLine(
    errorReportId: errorReportId,
    area: area,
  );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Get help / सहायता'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your work is safe on this phone. Share this reference with support and they can look up what happened:',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              errorReportId,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            line,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: line));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Reference copied / संदर्भ कॉपी हुआ'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: const Text('Copy reference'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

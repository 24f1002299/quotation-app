import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AttentionSummary — checklist progress card, not a warning box.
// Amber fill with a mini progress indicator ("0 of 2 resolved") while items
// are pending; transforms into a green success card once all are reviewed.
// Colour is never the only signal (icon + explicit text throughout).
// ─────────────────────────────────────────────────────────────────────────────
class AttentionSummary extends StatelessWidget {
  /// Items still needing review.
  final int count;

  /// Items that ever needed review (resolved + pending). When > 0 and
  /// [count] is 0, the card renders the green "all reviewed" success state.
  final int total;

  const AttentionSummary({super.key, required this.count, this.total = 0});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final effectiveTotal = total <= 0 ? count : total;
    final resolved = (effectiveTotal - count).clamp(0, effectiveTotal);

    if (count <= 0 && effectiveTotal > 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE7F2E9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF2F6B3C)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.of(context, 'all_reviewed'),
                style: tt.titleMedium?.copyWith(
                  color: const Color(0xFF2F6B3C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final progress = effectiveTotal <= 0 ? 0.0 : resolved / effectiveTotal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.playlist_add_check_rounded,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(
                        context,
                        'needs_attention_title',
                      ).replaceAll('{n}', '$count'),
                      style: tt.titleMedium?.copyWith(
                        color: const Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.of(context, 'review_progress')
                          .replaceAll('{done}', '$resolved')
                          .replaceAll('{total}', '$effectiveTotal'),
                      style: tt.bodySmall?.copyWith(
                        color: const Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 350),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: const Color(0xFFB45309)
                    .withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFB45309),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

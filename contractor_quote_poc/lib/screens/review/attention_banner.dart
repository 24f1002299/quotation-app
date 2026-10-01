import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AttentionSummary — "Needs attention (N)" banner.
// Light amber surface; colour is never the only signal (icon + text).
// ─────────────────────────────────────────────────────────────────────────────
class AttentionSummary extends StatelessWidget {
  final int count;

  const AttentionSummary({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Needs attention ($count)',
                  style: tt.titleMedium?.copyWith(
                    color: const Color(0xFF92400E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check or acknowledge the highlighted items before creating the PDF.',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

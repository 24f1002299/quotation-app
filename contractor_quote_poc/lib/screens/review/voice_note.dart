import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VoiceNoteCard — collapsible spoken-note card.
// ParsingWarningsBanner — parser warnings with dismiss action.
// ─────────────────────────────────────────────────────────────────────────────

class VoiceNoteCard extends StatelessWidget {
  final String transcript;
  final bool isExpanded;
  final VoidCallback onToggle;

  const VoiceNoteCard({
    super.key,
    required this.transcript,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // Footnote feel: soft gray fill, no border — never a primary element.
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mic_rounded, color: cs.primary, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.of(context, 'spoken_note'),
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isExpanded) ...[
                          const SizedBox(height: 2),
                          // Single-line preview (no quotation marks — those
                          // belong to the expanded body below).
                          Text(
                            transcript,
                            style: tt.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      AppStrings.of(context, 'voice_transcript'),
                      style: tt.bodySmall?.copyWith(
                        fontSize: 10,
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: theme.iconTheme.color?.withValues(alpha: 0.6),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“$transcript”',
                    style: tt.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.of(context, 'parsed_into_items'),
                        style: tt.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ],
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

class ParsingWarningsBanner extends StatelessWidget {
  final List<String> warnings;
  final VoidCallback onDismiss;

  const ParsingWarningsBanner({
    super.key,
    required this.warnings,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFB45309),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.of(context, 'please_review'),
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF92400E),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFB45309),
                ),
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                tooltip: AppStrings.of(context, 'dismiss'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: tt.bodySmall?.copyWith(
                      color: const Color(0xFF92400E),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(child: Text(w, style: tt.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            AppStrings.of(context, 'check_items_add_missing'),
            style: tt.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

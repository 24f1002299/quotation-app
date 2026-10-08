import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Small shared review widgets + the shared light input decoration.
// ─────────────────────────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const SectionHeader({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: tt.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String label;
  final Widget child;
  const FieldLabel({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodyMedium),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class AmountChip extends StatelessWidget {
  final String label;
  final String value;

  /// Amber tint when the item needs attention, dark fill when valid.
  final bool attention;

  const AmountChip({
    super.key,
    required this.label,
    required this.value,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final bg = attention ? const Color(0xFFFEF3C7) : cs.primary;
    final fg = attention ? const Color(0xFF92400E) : cs.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: tt.bodyMedium?.copyWith(color: fg)),
          Text(
            value,
            style: tt.titleMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyItemsHint extends StatelessWidget {
  final VoidCallback onAdd;
  final bool hasVoiceTranscript;

  const EmptyItemsHint({
    super.key,
    required this.onAdd,
    this.hasVoiceTranscript = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Center(
            child: Column(
              children: [
                Icon(
                  hasVoiceTranscript
                      ? Icons.playlist_add_rounded
                      : Icons.add_box_outlined,
                  size: 38,
                  color: cs.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  hasVoiceTranscript
                      ? AppStrings.of(context, 'no_items_from_voice')
                      : AppStrings.of(context, 'no_items_yet'),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  hasVoiceTranscript
                      ? AppStrings.of(context, 'tap_to_add_manually')
                      : AppStrings.of(context, 'add_materials_hint'),
                  style: tt.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared light input decoration — keeps all review fields consistent.
InputDecoration reviewInputDecoration(
  BuildContext context, {
  required String hint,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final hintColor = theme.textTheme.bodySmall?.color;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: hintColor, fontSize: 14),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    filled: true,
    fillColor: cs.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.dividerColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.dividerColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cs.error, width: 1.5),
    ),
  );
}

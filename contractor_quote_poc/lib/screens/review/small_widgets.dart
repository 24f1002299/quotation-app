import 'package:flutter/material.dart';

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
        Expanded(child: Text(label, style: tt.titleLarge)),
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
  const AmountChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: tt.bodyMedium),
          Text(value, style: tt.titleMedium?.copyWith(color: cs.primary)),
        ],
      ),
    );
  }
}

class EmptyItemsHint extends StatelessWidget {
  final VoidCallback onAdd;
  final bool hasVoiceTranscript;

  const EmptyItemsHint(
      {super.key, required this.onAdd, this.hasVoiceTranscript = false});

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
                      ? 'No items auto-detected from voice'
                      : 'No items yet — tap to add one',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  hasVoiceTranscript
                      ? 'Tap here or "+ Add item" to add manually'
                      : 'Add materials, labour, or custom rates',
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
InputDecoration reviewInputDecoration(BuildContext context,
    {required String hint}) {
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

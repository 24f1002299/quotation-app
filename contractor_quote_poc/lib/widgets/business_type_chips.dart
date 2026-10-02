import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../templates/template_data.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';

/// Chips for every business type the user can sell — replaces the old
/// tile/paint trade pair. Used by onboarding, Home, the new-quote sheet and
/// Profile so the choice always looks the same.
class BusinessTypeChips extends StatelessWidget {
  final BusinessType selected;
  final ValueChanged<BusinessType> onChanged;

  /// Language for the type labels; falls back to Hindi like [AppStrings].
  final String languageCode;

  const BusinessTypeChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.languageCode = 'hi',
  });

  @override
  Widget build(BuildContext context) {
    final lang =
        context.dependOnInheritedWidgetOfExactType<AppStrings>()?.languageCode ??
            languageCode;
    return Wrap(
      spacing: AppDimensions.gapSm,
      runSpacing: AppDimensions.gapSm,
      children: [
        for (final info in kBusinessTypes)
          _BusinessTypeChip(
            label: info.label(lang),
            icon: info.icon,
            selected: info.type == selected,
            onTap: () => onChanged(info.type),
          ),
      ],
    );
  }
}

class _BusinessTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BusinessTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: AppDimensions.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kSage.withValues(alpha: 0.3) : kSurfaceCard,
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
            border: Border.all(
              color: selected ? kForest : kSurfaceMuted,
              width: selected ? AppDimensions.focusBorderWidth : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: selected ? kForest : kInkMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? kForest : kInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

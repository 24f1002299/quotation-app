import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import 'small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomerSection — client name / phone / site card.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController siteCtrl;

  const CustomerSection({
    super.key,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.siteCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Client name ──────────────────────────────────────────────
            FieldLabel(
              label: '${AppStrings.of(context, 'client_name')} *',
              child: TextField(
                controller: nameCtrl,
                style: tt.bodyLarge,
                decoration: reviewInputDecoration(context,
                    hint: AppStrings.of(context, 'customer_name_hint')),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(height: 12),

            // ── Phone ────────────────────────────────────────────────────
            FieldLabel(
              label: AppStrings.of(context, 'phone'),
              child: TextField(
                controller: phoneCtrl,
                style: tt.bodyLarge,
                decoration:
                    reviewInputDecoration(context, hint: '9XXXXXXXXX'),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(height: 12),

            // ── Site / Address ───────────────────────────────────────────
            FieldLabel(
              label: AppStrings.of(context, 'site'),
              child: TextField(
                controller: siteCtrl,
                style: tt.bodyLarge,
                decoration: reviewInputDecoration(
                  context,
                  hint: AppStrings.of(context, 'site_hint'),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

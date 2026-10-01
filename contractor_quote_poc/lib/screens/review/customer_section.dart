import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
              label: 'Client name / ग्राहक का नाम *',
              child: TextField(
                controller: nameCtrl,
                style: tt.bodyLarge,
                decoration: reviewInputDecoration(context,
                    hint: 'e.g. Sharma Ji / शर्मा जी'),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(height: 12),

            // ── Phone ────────────────────────────────────────────────────
            FieldLabel(
              label: 'Phone / फ़ोन (optional)',
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
              label: 'Site / Address / कार्यस्थल (optional)',
              child: TextField(
                controller: siteCtrl,
                style: tt.bodyLarge,
                decoration: reviewInputDecoration(
                  context,
                  hint: 'e.g. Flat 302, Green Acres / फ्लैट ३०२, मुंबई',
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

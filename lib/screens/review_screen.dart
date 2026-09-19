import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';

/// Day 1 — static placeholder for the Review / Edit screen.
/// Days 3-7 will replace the hardcoded rows with real parsed data.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  // Hardcoded demo line items for Day 1 navigation test.
  static const _demoItems = [
    _LineItem('Tile Labour / टाइल मजदूरी', '850 sq ft', 45),
    _LineItem('Skirting / स्कर्टिंग', '120 rft', 60),
  ];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // Calculate demo total using integer arithmetic (no float risk).
    final int subtotal = _demoItems.fold(
        0, (s, i) => s + i.subtotal);

    return Scaffold(
      appBar: AppBar(title: const Text('Review Quote / जाँचें')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(kPagePadding),
                children: [
                  Text('Line Items / मद', style: tt.titleLarge),
                  const SizedBox(height: 12),

                  // ── Demo line item cards ───────────────────
                  ..._demoItems.map((item) => _LineItemCard(item: item)),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ── Totals ────────────────────────────────
                  _TotalRow(
                      label: 'Subtotal / कुल',
                      value: formatRupee(subtotal)),

                  const SizedBox(height: 24),

                  // ── Customer section placeholder ───────────
                  Text('Customer / ग्राहक', style: tt.titleLarge),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Customer details will be entered here.\n(Days 3-7)',
                        style: tt.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom action bar ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kPagePadding, 0, kPagePadding, kPagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Generate PDF'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.popUntil(
                        context, ModalRoute.withName('/')),
                    child: const Text('Back to Home / होम पर जाएं'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Simple immutable data holder — replaced by Quote model Day 2
// ─────────────────────────────────────────────────────────
class _LineItem {
  final String name;
  final String qty;
  final int rate; // whole rupees

  const _LineItem(this.name, this.qty, this.rate);

  // qty is a display string on Day 1; subtotal calculated from
  // rate × numeric prefix only when qty starts with a number.
  int get subtotal {
    final match = RegExp(r'(\d+)').firstMatch(qty);
    if (match == null) return 0;
    return int.parse(match.group(1)!) * rate;
  }
}

class _LineItemCard extends StatelessWidget {
  final _LineItem item;
  const _LineItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: tt.titleMedium),
                  const SizedBox(height: 2),
                  Text('${item.qty} × ${formatRupee(item.rate)}',
                      style: tt.bodyMedium),
                ],
              ),
            ),
            Text(formatRupee(item.subtotal), style: tt.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  const _TotalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: tt.titleMedium),
          Text(value,
              style: tt.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

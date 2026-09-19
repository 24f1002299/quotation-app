import 'package:flutter/material.dart';

import '../models/quote.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';

/// Day 1 — static placeholder for the Review / Edit screen.
/// Days 3-7 will replace the hardcoded rows with real parsed data.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  static final _demoQuote = Quote(
    customer: const Customer(name: 'Demo customer'),
    lineItems: const [
      QuoteLineItem(
        description: 'Tile Labour / टाइल मजदूरी',
        quantity: 850,
        unit: 'sq ft',
        unitRatePaise: 4500,
      ),
      QuoteLineItem(
        description: 'Skirting / स्कर्टिंग',
        quantity: 120,
        unit: 'rft',
        unitRatePaise: 6000,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final totals = calculateTotals(_demoQuote);

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
                  ..._demoQuote.lineItems.asMap().entries.map(
                    (entry) => _LineItemCard(
                      item: entry.value,
                      amountPaise: totals.lineAmountsPaise[entry.key],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ── Totals ────────────────────────────────
                  _TotalRow(
                    label: 'Subtotal / कुल',
                    value: formatRupeePaise(totals.subtotalPaise),
                  ),

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
                kPagePadding,
                0,
                kPagePadding,
                kPagePadding,
              ),
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
                    onPressed: () =>
                        Navigator.popUntil(context, ModalRoute.withName('/')),
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

class _LineItemCard extends StatelessWidget {
  final QuoteLineItem item;
  final int amountPaise;
  const _LineItemCard({required this.item, required this.amountPaise});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.description, style: tt.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${item.quantity} ${item.unit} × '
                    '${formatRupeePaise(item.unitRatePaise)}',
                    style: tt.bodyMedium,
                  ),
                ],
              ),
            ),
            Text(formatRupeePaise(amountPaise), style: tt.titleMedium),
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
          Text(
            value,
            style: tt.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

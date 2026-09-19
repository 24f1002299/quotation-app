import 'package:flutter/material.dart';
import '../theme.dart';

/// Day 1 — static placeholder for the "New Quote" flow.
/// Days 5-7 will add trade selection, microphone, and parser.
class NewQuoteScreen extends StatelessWidget {
  const NewQuoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New Quote / नया कोटेशन')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              // ── Trade selection placeholder ────────────────
              Text('Select Trade / काम चुनें', style: tt.titleLarge),
              const SizedBox(height: 16),
              _TradeCard(
                icon: Icons.grid_4x4_rounded,
                label: 'Tiling / टाइल्स',
                subtitle: 'Tile labour, skirting, waterproofing',
                onTap: () {},
              ),
              _TradeCard(
                icon: Icons.format_paint_rounded,
                label: 'Painting / पेंटिंग',
                subtitle: 'Wall putty, primer, painting',
                onTap: () {},
              ),

              const Spacer(),

              // ── Proceed CTA (navigates to Review placeholder) ─
              ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/review'),
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Speak Quote / बोलें'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/review'),
                child: const Text('Enter Manually / खुद भरें'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TradeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _TradeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: tt.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

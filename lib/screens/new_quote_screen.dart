import 'package:flutter/material.dart';
import '../catalog/catalog.dart';
import '../parser/demo_transcripts.dart';
import '../parser/transcript_parser.dart';
import '../screens/review_screen.dart';
import '../theme.dart';

/// Day 4 — Real trade selection.  Tapping a trade card highlights it and
/// enables the CTAs.  Both "Speak" and "Enter Manually" push ReviewScreen
/// with the selected [Trade] so the add-item sheet can offer catalog choices.
class NewQuoteScreen extends StatefulWidget {
  const NewQuoteScreen({super.key});

  @override
  State<NewQuoteScreen> createState() => _NewQuoteScreenState();
}

class _NewQuoteScreenState extends State<NewQuoteScreen> {
  Trade? _selectedTrade;

  void _selectTrade(Trade trade) => setState(() => _selectedTrade = trade);

  void _proceed({required bool voiceMode}) {
    if (_selectedTrade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a trade first / पहले काम चुनें'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(trade: _selectedTrade),
      ),
    );
  }

  /// Parse the demo transcript for [trade] and jump straight to the review
  /// screen with pre-filled line items.  Also highlights that trade card.
  void _useDemoTranscript(Trade trade) {
    setState(() => _selectedTrade = trade);
    final transcript = trade == Trade.tiling
        ? kTilingDemoTranscript
        : kPaintingDemoTranscript;
    final result = const TranscriptParser().parse(transcript);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          trade: trade,
          initialLineItems:
              result.items.map((i) => i.toQuoteLineItem()).toList(),
        ),
      ),
    );
  }

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

              Text('Select Trade / काम चुनें', style: tt.titleLarge),
              const SizedBox(height: 16),

              _TradeCard(
                icon: Icons.grid_4x4_rounded,
                label: 'Tiling / टाइल्स',
                subtitle: 'Tile labour, skirting, waterproofing',
                selected: _selectedTrade == Trade.tiling,
                onTap: () => _selectTrade(Trade.tiling),
              ),
              _TradeCard(
                icon: Icons.format_paint_rounded,
                label: 'Painting / पेंटिंग',
                subtitle: 'Wall putty, primer, painting',
                selected: _selectedTrade == Trade.painting,
                onTap: () => _selectTrade(Trade.painting),
              ),

              const SizedBox(height: 20),

              // ── Demo shortcut ──────────────────────────────────────────
              Text(
                '— or try a demo / डेमो देखें —',
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _useDemoTranscript(Trade.tiling),
                      icon: const Text('🪣', style: TextStyle(fontSize: 16)),
                      label: const Text('Tiling Demo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _useDemoTranscript(Trade.painting),
                      icon: const Text('🖌️', style: TextStyle(fontSize: 16)),
                      label: const Text('Painting Demo'),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              ElevatedButton.icon(
                // Greyed out until a trade is chosen
                onPressed: _selectedTrade == null
                    ? null
                    : () => _proceed(voiceMode: true),
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Speak Quote / बोलें'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _selectedTrade == null
                    ? null
                    : () => _proceed(voiceMode: false),
                child: const Text('Enter Manually / खुद भरें'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TradeCard — shows a saffron border + check badge when [selected] is true
// ─────────────────────────────────────────────────────────────────────────────
class _TradeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TradeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? cs.primary : const Color(0xFF2E2E42),
          width: selected ? 2 : 1,
        ),
        color: selected
            ? cs.primary.withOpacity(0.08)
            : const Color(0xFF1E1E2C),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(
                icon,
                size: 36,
                color: selected ? cs.primary : const Color(0xFF9E9BA8),
              ),
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
              // Show checkmark when selected, chevron otherwise
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selected
                    ? Icon(Icons.check_circle_rounded,
                        key: const ValueKey('check'),
                        color: cs.primary,
                        size: 24)
                    : const Icon(Icons.chevron_right_rounded,
                        key: ValueKey('chevron'),
                        size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/catalog.dart';
import '../l10n/app_strings.dart';
import '../storage/app_preferences.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import 'home_screen.dart';
import 'quote_history_screen.dart';
import 'review_screen.dart';
import 'voice_screen.dart';

/// Bottom-navigation shell: Home · New Quote (centre action) · Quotes.
/// The centre tab opens a trade sheet (Speak first, Type second) per design.md.
class AppShell extends StatefulWidget {
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;
  const AppShell({
    super.key,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openNewQuoteSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: kSurfaceCard,
      builder: (sheetCtx) => _NewQuoteSheet(
        languageCode: widget.languageCode,
        onSpeak: (trade) {
          Navigator.pop(sheetCtx);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VoiceScreen(trade: trade)),
          );
        },
        onType: (trade) {
          Navigator.pop(sheetCtx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReviewScreen(trade: trade, initialLineItems: const []),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => AppStrings.text(widget.languageCode, k);
    return Scaffold(
      body: IndexedStack(
        index: _index == 2 ? 1 : 0,
        children: [
          AppStrings(languageCode: widget.languageCode, child: const HomeScreen()),
          AppStrings(languageCode: widget.languageCode, child: const QuoteHistoryScreen()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 1) {
            _openNewQuoteSheet();
            return;
          }
          setState(() => _index = i);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: t('home'),
          ),
          NavigationDestination(
            icon: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: kForest,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
            ),
            label: t('new'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long_rounded),
            label: t('quotes'),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }
}

/// Bottom sheet content for the centre New action.
/// Speak first (primary), Type second — trade chips remember last use.
class _NewQuoteSheet extends StatefulWidget {
  final String languageCode;
  final ValueChanged<Trade> onSpeak;
  final ValueChanged<Trade> onType;
  const _NewQuoteSheet({
    required this.languageCode,
    required this.onSpeak,
    required this.onType,
  });

  @override
  State<_NewQuoteSheet> createState() => _NewQuoteSheetState();
}

class _NewQuoteSheetState extends State<_NewQuoteSheet> {
  Trade _trade = Trade.tiling;

  @override
  void initState() {
    super.initState();
    AppPreferences.getLastTrade().then((t) {
      if (mounted && t != null) setState(() => _trade = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => AppStrings.text(widget.languageCode, k);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.page,
          12,
          AppDimensions.page,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kSurfaceMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _TradeChip(
                  label: t('tiling'),
                  icon: Icons.grid_4x4_rounded,
                  selected: _trade == Trade.tiling,
                  onTap: () => setState(() => _trade = Trade.tiling),
                ),
                const SizedBox(width: 12),
                _TradeChip(
                  label: t('painting'),
                  icon: Icons.format_paint_rounded,
                  selected: _trade == Trade.painting,
                  onTap: () => setState(() => _trade = Trade.painting),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                AppPreferences.setLastTrade(_trade);
                widget.onSpeak(_trade);
              },
              icon: const Icon(Icons.mic_rounded),
              label: Text(t('new_voice_quote')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                AppPreferences.setLastTrade(_trade);
                widget.onType(_trade);
              },
              child: Text(t('type_manually')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TradeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TradeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? kSage.withValues(alpha: 0.3) : kSurface,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            border: Border.all(
              color: selected ? kForest : kSurfaceMuted,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? kForest : kInkMuted, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
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

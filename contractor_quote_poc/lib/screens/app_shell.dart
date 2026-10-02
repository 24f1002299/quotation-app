import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../templates/template_data.dart';
import '../l10n/app_strings.dart';
import '../storage/app_preferences.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import 'home_screen.dart';
import 'quote_history_screen.dart';
import 'review_screen.dart';
import '../widgets/business_type_chips.dart';
import 'voice_screen.dart';

/// Bottom-navigation shell: Home · New Quote (centre action) · Quotes.
/// The centre tab opens a businessType sheet (Speak first, Type second) per design.md.
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
        onSpeak: (businessType) {
          Navigator.pop(sheetCtx);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VoiceScreen(businessType: businessType)),
          );
        },
        onType: (businessType) {
          Navigator.pop(sheetCtx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReviewScreen(businessType: businessType, initialLineItems: const []),
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
/// Speak first (primary), Type second — businessType chips remember last use.
class _NewQuoteSheet extends StatefulWidget {
  final String languageCode;
  final ValueChanged<BusinessType> onSpeak;
  final ValueChanged<BusinessType> onType;
  const _NewQuoteSheet({
    required this.languageCode,
    required this.onSpeak,
    required this.onType,
  });

  @override
  State<_NewQuoteSheet> createState() => _NewQuoteSheetState();
}

class _NewQuoteSheetState extends State<_NewQuoteSheet> {
  BusinessType _businessType = BusinessType.tiling;
  bool _showTypes = false;

  @override
  void initState() {
    super.initState();
    AppPreferences.getLastBusinessType().then((t) {
      if (mounted && t != null) setState(() => _businessType = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => AppStrings.text(widget.languageCode, k);
    final info = businessTypeInfo(_businessType);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.page,
          12,
          AppDimensions.page,
          24,
        ),
        child: SingleChildScrollView(
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
              // Current work type; tap to change it.
              InkWell(
                onTap: () => setState(() => _showTypes = !_showTypes),
                borderRadius:
                    BorderRadius.circular(AppDimensions.buttonRadius),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: kSage.withValues(alpha: 0.3),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.buttonRadius),
                    border: Border.all(color: kForest, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(info.icon, color: kForest, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${t('business_type')}: '
                          '${info.label(widget.languageCode)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: kForest,
                          ),
                        ),
                      ),
                      Icon(
                        _showTypes
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: kForest,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showTypes) ...[
                const SizedBox(height: 12),
                BusinessTypeChips(
                  selected: _businessType,
                  languageCode: widget.languageCode,
                  onChanged: (type) => setState(() => _businessType = type),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  AppPreferences.setLastBusinessType(_businessType);
                  widget.onSpeak(_businessType);
                },
                icon: const Icon(Icons.mic_rounded),
                label: Text(t('new_voice_quote')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  AppPreferences.setLastBusinessType(_businessType);
                  widget.onType(_businessType);
                },
                child: Text(t('type_manually')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

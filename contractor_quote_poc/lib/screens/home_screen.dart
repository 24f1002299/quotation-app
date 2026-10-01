import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../catalog/catalog.dart';
import '../l10n/app_strings.dart';
import '../models/contractor_profile.dart';
import '../storage/app_preferences.dart';
import '../storage/auth_repository.dart';
import '../storage/profile_repository.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../utils/rupee_format.dart';
import '../widgets/common_widgets.dart';
import 'pdf_preview_screen.dart';
import 'review_screen.dart';
import 'voice_screen.dart';

/// Phase 2 — Voice-first dashboard.
///
/// - Mic is the hero (96dp, centre of screen, one tap starts recording
///   with the last-used trade pre-selected).
/// - Trade selection is inline chips, not a separate screen.
/// - Drafts appear only when they exist, as compact cards.
/// - No tutorial card: a one-line hint under the mic, auto-dismissed.
/// - Offline status is a slim bar; sign-in nudge is a dot on the avatar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ContractorProfile _profile = ContractorProfile.empty();
  Trade _trade = Trade.tiling;
  bool _signedIn = false;
  bool _tutorialSeen = true;
  List<SavedQuote> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      ProfileRepository.getProfile(),
      AppPreferences.getLastTrade(),
      AuthRepository.isSignedIn(),
      AppPreferences.hasSeenTutorial(),
      QuoteRepository.getQuotes(),
    ]);
    if (!mounted) return;
    final quotes = results[4] as List<SavedQuote>;
    setState(() {
      _profile = results[0] as ContractorProfile;
      _trade = (results[1] as Trade?) ?? (results[0] as ContractorProfile).trade;
      _signedIn = results[2] as bool;
      _tutorialSeen = results[3] as bool;
      _drafts = quotes
          .where((q) => q.status == 'draft' || q.status == 'needsReview')
          .take(3)
          .toList();
      _loading = false;
    });
  }

  Future<void> _dismissHint() async {
    await AppPreferences.setTutorialSeen();
    if (mounted) setState(() => _tutorialSeen = true);
  }

  void _startVoice() {
    AppPreferences.setLastTrade(_trade);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoiceScreen(trade: _trade)),
    ).then((_) => _loadAll());
  }

  void _typeManually() {
    AppPreferences.setLastTrade(_trade);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReviewScreen(trade: _trade, initialLineItems: const []),
      ),
    ).then((_) => _loadAll());
  }

  void _openDraft(SavedQuote quote) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          savedQuoteId: quote.id,
          trade: quote.trade,
          customerName: quote.customerName,
          customerPhone: quote.customerPhone,
          customerAddress: quote.customerAddress,
          validityDays: quote.validityDays,
          gstPercent: quote.gstPercent,
          advancePercent: quote.advancePercent,
          advanceText: quote.advanceText,
          terms: quote.terms,
          quoteDate: quote.effectiveDate,
          displayNumber: quote.quoteNumber,
          serverDisplayNumber: quote.serverDisplayNumber,
          notes: quote.notes,
          originalTranscript: quote.originalTranscript,
          parsingWarnings: quote.reviewWarnings,
          parsingWarningsAcknowledged: quote.reviewWarningsAcknowledged,
          initialLineItems: quote.lineItems,
        ),
      ),
    ).then((_) => _loadAll());
  }

  void _openRecent(SavedQuote quote) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          quote: quote.toQuote(),
          trade: quote.trade,
          validityDays: quote.validityDays,
          notes: quote.notes,
          savedQuoteId: quote.id,
        ),
      ),
    ).then((_) => _loadAll());
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => AppStrings.of(context, k);
    final initial =
        _profile.name.isNotEmpty ? _profile.name.characters.first : null;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          color: kForest,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimensions.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Minimal top bar ──────────────────────────────
                Row(
                  children: [
                    Text(
                      t('app_name'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: kForest,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        await Navigator.pushNamed(context, '/profile');
                        _loadAll();
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                kSage.withValues(alpha: 0.4),
                            child: Text(
                              initial ?? '👷',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kForest,
                              ),
                            ),
                          ),
                          if (!_signedIn &&
                              AuthRepository.isSupabaseConfigured)
                            Positioned(
                              right: -1,
                              top: -1,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: kAttention,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: kSurface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // ── Hero mic ─────────────────────────────────────
                Center(
                  child: MicButton(onTap: _startVoice),
                ),
                const SizedBox(height: 12),
                Text(
                  t('tap_to_speak'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
                if (!_tutorialSeen) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _dismissHint,
                    child: Text(
                      t('tap_mic_hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: kInkMuted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // ── Inline trade chips ───────────────────────────
                Row(
                  children: [
                    _HomeTradeChip(
                      label: t('tiling'),
                      icon: Icons.grid_4x4_rounded,
                      selected: _trade == Trade.tiling,
                      onTap: () {
                        setState(() => _trade = Trade.tiling);
                        AppPreferences.setLastTrade(Trade.tiling);
                      },
                    ),
                    const SizedBox(width: 12),
                    _HomeTradeChip(
                      label: t('painting'),
                      icon: Icons.format_paint_rounded,
                      selected: _trade == Trade.painting,
                      onTap: () {
                        setState(() => _trade = Trade.painting);
                        AppPreferences.setLastTrade(Trade.painting);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    onTap: _typeManually,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        t('type_manually'),
                        style: const TextStyle(
                          fontSize: 14,
                          color: kForest,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Drafts (only when they exist) ────────────────
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(color: kForest),
                    ),
                  )
                else if (_drafts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '${t('drafts')} (${_drafts.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._drafts.map(
                    (q) => QuoteCard(
                      title: q.customerName,
                      subtitle:
                          '${q.lineItems.length} items · ${DateFormat('dd MMM').format(q.effectiveDate)}',
                      amount: formatRupee(q.grandTotalRupees),
                      onTap: () => _openDraft(q),
                    ),
                  ),
                  // Most recent shared quote, compact, if easy to fetch.
                  FutureBuilder<List<SavedQuote>>(
                    future: QuoteRepository.getQuotes(),
                    builder: (ctx, snap) {
                      final shared = (snap.data ?? [])
                          .where((q) =>
                              q.status == 'ready' || q.status == 'shared')
                          .take(1)
                          .toList();
                      if (shared.isEmpty) return const SizedBox.shrink();
                      final q = shared.first;
                      return QuoteCard(
                        title: q.customerName,
                        subtitle:
                            '${q.displayNumber} · ${DateFormat('dd MMM').format(q.effectiveDate)}',
                        amount: formatRupee(q.grandTotalRupees),
                        badgeStatus: 'shared',
                        badgeLabel: t('filter_shared'),
                        onTap: () => _openRecent(q),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTradeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _HomeTradeChip({
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
            color: selected
                ? kSage.withValues(alpha: 0.3)
                : kSurfaceCard,
            borderRadius:
                BorderRadius.circular(AppDimensions.cardRadius),
            border: Border.all(
              color: selected ? kForest : kSurfaceMuted,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? kForest : kInkMuted,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
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

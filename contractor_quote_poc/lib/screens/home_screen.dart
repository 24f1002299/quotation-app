import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../templates/template_data.dart';
import '../l10n/app_strings.dart';
import '../models/business_profile.dart';
import '../storage/app_preferences.dart';
import '../storage/auth_repository.dart';
import '../storage/profile_repository.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';
import '../storage/service_item_repository.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../utils/rupee_format.dart';
import '../widgets/common_widgets.dart';
import 'pdf_preview_screen.dart';
import 'my_services_screen.dart';
import 'review_screen.dart';
import 'voice_screen.dart';

/// Phase 2 — Voice-first dashboard.
///
/// - Mic is the hero (96dp, centre of screen, one tap starts recording
///   for the user's own business).
/// - No business-type selector: the profile's business is the context.
/// - Drafts appear only when they exist, as compact cards.
/// - No tutorial card: a one-line hint under the mic, auto-dismissed.
/// - Offline status is a slim bar; sign-in nudge is a dot on the avatar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BusinessProfile _profile = BusinessProfile.empty();
  BusinessType _businessType = BusinessType.tiling;
  bool _signedIn = false;
  bool _tutorialSeen = true;
  List<SavedQuote> _drafts = [];
  bool _loading = true;
  int _servicesCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      ProfileRepository.getProfile(),
      AppPreferences.getLastBusinessType(),
      AuthRepository.isSignedIn(),
      AppPreferences.hasSeenTutorial(),
      QuoteRepository.getQuotes(),
    ]);
    if (!mounted) return;
    final quotes = results[4] as List<SavedQuote>;
    final businessType =
        (results[1] as BusinessType?) ?? (results[0] as BusinessProfile).businessType;
    setState(() {
      _profile = results[0] as BusinessProfile;
      _businessType = businessType;
      _signedIn = results[2] as bool;
      _tutorialSeen = results[3] as bool;
      _drafts = quotes
          .where((q) => q.status == 'draft' || q.status == 'needsReview')
          .take(3)
          .toList();
      _loading = false;
    });
    final services =
        await ServiceItemRepository.getActiveForBusinessType(businessType);
    if (!mounted) return;
    setState(() => _servicesCount = services.length);
  }

  Future<void> _dismissHint() async {
    await AppPreferences.setTutorialSeen();
    if (mounted) setState(() => _tutorialSeen = true);
  }

  void _startVoice() {
    AppPreferences.setLastBusinessType(_businessType);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VoiceScreen(businessType: _businessType)),
    ).then((_) => _loadAll());
  }

  void _typeManually() {
    AppPreferences.setLastBusinessType(_businessType);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReviewScreen(businessType: _businessType, initialLineItems: const []),
      ),
    ).then((_) => _loadAll());
  }

  void _openDraft(SavedQuote quote) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          savedQuoteId: quote.id,
          businessType: quote.businessType,
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
          businessType: quote.businessType,
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
        _profile.ownerName.isNotEmpty ? _profile.ownerName.characters.first : null;

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
                // ── Business identity (no selector: profile is the context) ──
                Center(
                  child: Text(
                    _profile.businessName.isNotEmpty
                        ? _profile.businessName
                        : businessTypeLabel(
                            _businessType,
                            _profile.customBusinessType,
                            'en',
                          ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kInk,
                    ),
                  ),
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
                const SizedBox(height: 8),
                // ── My services entry (count persists via repository) ──
                Card(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyServicesScreen(
                            businessType: _businessType,
                          ),
                        ),
                      ).then((_) => _loadAll());
                    },
                    borderRadius: BorderRadius.circular(
                      AppDimensions.cardRadius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.handyman_outlined,
                            color: kForest,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${t('my_services')} · $_servicesCount',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: kInk,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: kInkMuted,
                          ),
                        ],
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

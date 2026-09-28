import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contractor_profile.dart';
import '../storage/app_preferences.dart';
import '../storage/auth_repository.dart';
import '../storage/profile_repository.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';
import 'pdf_preview_screen.dart';
import 'review_screen.dart';

/// Day 19 — Home: first quote easy to discover and resume.
///
/// - Greeting + Profile shortcut (+ always-visible language control).
/// - Sign-in banner (only when Supabase configured and not signed in).
/// - Onboarding banner when profile/rates not set up.
/// - One-time in-context tutorial card (not a multi-page tour).
/// - Primary CTA "New voice quote" → recording in one tap.
/// - Recent drafts (resume after restart) + recent sent quotes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ContractorProfile _profile = ContractorProfile.empty();
  bool _hasCompletedOnboarding = true;
  bool _tutorialSeen = true;
  String _language = 'hi';
  bool _signedIn = false;

  List<SavedQuote> _drafts = [];
  List<SavedQuote> _recent = [];
  bool _loadingLists = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final profile = await ProfileRepository.getProfile();
    final completed = await ProfileRepository.hasCompletedOnboarding();
    final tutorialSeen = await AppPreferences.hasSeenTutorial();
    final language = await AppPreferences.getLanguage();
    final signedIn = await AuthRepository.isSignedIn();
    final quotes = await QuoteRepository.getQuotes();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _hasCompletedOnboarding = completed;
      _tutorialSeen = tutorialSeen;
      _language = language;
      _signedIn = signedIn;
      _drafts = quotes
          .where((q) => q.status == 'draft' || q.status == 'needsReview')
          .take(3)
          .toList();
      _recent = quotes
          .where((q) => q.status == 'ready' || q.status == 'shared')
          .take(3)
          .toList();
      _loadingLists = false;
    });
  }

  Future<void> _dismissTutorial() async {
    await AppPreferences.setTutorialSeen();
    if (!mounted) return;
    setState(() => _tutorialSeen = true);
  }

  Future<void> _changeLanguage(String code) async {
    await AppPreferences.setLanguage(code);
    if (!mounted) return;
    setState(() => _language = code);
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
    final tt = Theme.of(context).textTheme;

    final greeting = _profile.name.isNotEmpty
        ? 'नमस्ते, ${_profile.name.split(' ').first} 👷'
        : 'नमस्ते 👷';

    final subheader = _profile.businessName.isNotEmpty
        ? _profile.businessName
        : 'Contractor Quote App';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(kPagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                // ── Header with Profile shortcut + language ──────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(greeting, style: tt.displaySmall),
                          const SizedBox(height: 4),
                          Text(subheader, style: tt.bodyMedium),
                        ],
                      ),
                    ),
                    _LanguageChip(
                      selected: _language,
                      onChanged: _changeLanguage,
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.pushNamed(context, '/profile');
                        _loadAll();
                      },
                      icon: const Icon(Icons.person_outline_rounded, size: 20),
                      label: const Text('Profile'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),

                // ── Sign-in banner (only when backend configured) ────
                if (!_signedIn && AuthRepository.isSupabaseConfigured) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_outlined, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Sign in to sync quotes / सिंक के लिए साइन इन करें',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Navigator.pushNamed(context, '/sign-in');
                            _loadAll();
                          },
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Onboarding banner if not yet configured ────
                if (!_hasCompletedOnboarding) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sage.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sage),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.stars_rounded,
                            color: forest, size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Set your standard rates once to speed up future quotes!',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Navigator.pushNamed(context, '/onboarding');
                            _loadAll();
                          },
                          child: const Text('Setup'),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── One-time in-context tutorial (single card) ───────
                if (!_tutorialSeen) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sage.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: forest.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tips_and_updates_outlined,
                                color: forest, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'First quote in 60 seconds / 60 सेकंड में पहला कोटेशन',
                                style: tt.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Tap “New voice quote” → speak work + quantities.\n'
                          '2. Review items, add client name.\n'
                          '3. Generate PDF → Share on WhatsApp.\n'
                          'Drafts auto-save on this phone.',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _dismissTutorial,
                            child: const Text('Got it / समझ गया ✓'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Primary CTA: one tap to recording ────────────────
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/new-quote');
                    _loadAll();
                  },
                  icon: const Icon(Icons.mic_rounded, size: 24),
                  label: const Text('New voice quote / नया वॉइस कोटेशन'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'Drafts are safe on this phone / ड्राफ्ट इस फोन में सुरक्षित',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Drafts: resume after restart ─────────────────────
                _SectionRow(
                  title: 'Drafts / ड्राफ्ट',
                  count: _drafts.length,
                  onSeeAll: () async {
                    await Navigator.pushNamed(context, '/history');
                    _loadAll();
                  },
                ),
                const SizedBox(height: 8),
                if (_loadingLists)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ))
                else if (_drafts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.6)),
                    ),
                    child: const Text(
                      'No drafts yet. Tap “New voice quote” or type one manually — it will wait for you here even after restart.',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else
                  ..._drafts.map((q) => _QuoteRow(
                        title: q.customerName,
                        subtitle:
                            '${q.lineItems.length} items · ${DateFormat('dd MMM').format(q.effectiveDate)}',
                        trailing: formatRupee(q.grandTotalRupees),
                        onTap: () => _openDraft(q),
                      )),

                const SizedBox(height: 16),

                // ── Recent sent quotes ───────────────────────────────
                _SectionRow(
                  title: 'Recent quotes / हाल के कोटेशन',
                  count: _recent.length,
                  onSeeAll: () async {
                    await Navigator.pushNamed(context, '/history');
                    _loadAll();
                  },
                ),
                const SizedBox(height: 8),
                if (!_loadingLists && _recent.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.6)),
                    ),
                    child: const Text(
                      'Shared quotes appear here. / भेजे गए कोटेशन यहाँ दिखेंगे।',
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else
                  ..._recent.map((q) => _QuoteRow(
                        title: q.customerName,
                        subtitle:
                            '${q.displayNumber} · ${q.status == 'shared' ? 'Shared' : 'Ready'} · ${DateFormat('dd MMM').format(q.effectiveDate)}',
                        trailing: formatRupee(q.grandTotalRupees),
                        onTap: () => _openRecent(q),
                      )),

                const SizedBox(height: 20),

                // ── History shortcut ─────────────────────────────────
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/history');
                    _loadAll();
                  },
                  icon: const Icon(Icons.history_rounded, size: 24),
                  label: const Text('Quote History / पुराने कोटेशन'),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Tiling · Painting · More coming soon',
                    style: tt.bodyMedium,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onSeeAll;

  const _SectionRow({
    required this.title,
    required this.count,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            count > 0 ? '$title ($count)' : title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: onSeeAll,
          child: const Text('See all'),
        ),
      ],
    );
  }
}

class _QuoteRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  const _QuoteRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: tt.titleMedium?.copyWith(fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitle, style: tt.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(trailing,
                  style: tt.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always-visible language control (design.md: language always visible).
class _LanguageChip extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _LanguageChip({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: selected,
      onSelected: onChanged,
      tooltip: 'Language / भाषा',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 16),
            const SizedBox(width: 4),
            Text(
              AppPreferences.labelFor(selected),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'hi', child: Text('Hindi (हिंदी)')),
        PopupMenuItem(value: 'mr', child: Text('Marathi (मराठी)')),
        PopupMenuItem(value: 'auto', child: Text('Auto')),
      ],
    );
  }
}

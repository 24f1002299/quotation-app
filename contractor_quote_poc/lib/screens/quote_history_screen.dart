import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../catalog/catalog.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';
import 'pdf_preview_screen.dart';
import 'review_screen.dart';

/// Day 9 — Interactive Quote History Screen.
///
/// Loads saved quotes from [QuoteRepository], displays summary cards with
/// trade branding, and allows reopening any quote for editing or regenerating PDFs.
class QuoteHistoryScreen extends StatefulWidget {
  const QuoteHistoryScreen({super.key});

  @override
  State<QuoteHistoryScreen> createState() => _QuoteHistoryScreenState();
}

class _QuoteHistoryScreenState extends State<QuoteHistoryScreen> {
  late Future<List<SavedQuote>> _quotesFuture;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  void _loadQuotes() {
    setState(() {
      _quotesFuture = QuoteRepository.getQuotes();
    });
  }

  Future<void> _deleteQuote(SavedQuote quote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Quote / कोटेशन हटाएं?'),
        content: Text(
          'Are you sure you want to delete the quote for "${quote.customerName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel / रद्द करें'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete / हटाएं'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await QuoteRepository.deleteQuote(quote.id);
      _loadQuotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote deleted / कोटेशन हटा दिया गया'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openQuoteForEditing(SavedQuote quote) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          savedQuoteId: quote.id,
          trade: quote.trade,
          customerName: quote.customerName,
          customerPhone: quote.customerPhone,
          validityDays: quote.validityDays,
          notes: quote.notes,
          originalTranscript: quote.originalTranscript,
          initialLineItems: quote.lineItems,
        ),
      ),
    ).then((_) => _loadQuotes());
  }

  void _viewPdf(SavedQuote quote) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote History / पुराने कोटेशन'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh / ताज़ा करें',
            onPressed: _loadQuotes,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<SavedQuote>>(
          future: _quotesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final quotes = snapshot.data ?? [];

            if (quotes.isEmpty) {
              return _EmptyState(
                onNewQuote: () => Navigator.pushNamed(context, '/new-quote'),
              );
            }

            return RefreshIndicator(
              onRefresh: () async => _loadQuotes(),
              child: ListView.builder(
                padding: const EdgeInsets.all(kPagePadding),
                itemCount: quotes.length,
                itemBuilder: (ctx, i) => _SavedQuoteCard(
                  quote: quotes[i],
                  onTap: () => _openQuoteForEditing(quotes[i]),
                  onViewPdf: () => _viewPdf(quotes[i]),
                  onDelete: () => _deleteQuote(quotes[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SavedQuoteCard — Interactive history card for a saved quote
// ─────────────────────────────────────────────────────────────────────────────

class _SavedQuoteCard extends StatelessWidget {
  final SavedQuote quote;
  final VoidCallback onTap;
  final VoidCallback onViewPdf;
  final VoidCallback onDelete;

  const _SavedQuoteCard({
    required this.quote,
    required this.onTap,
    required this.onViewPdf,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('dd MMM yyyy');

    final tradeIcon = quote.trade == Trade.tiling
        ? '🪣'
        : quote.trade == Trade.painting
            ? '🖌️'
            : '📄';

    final tradeLabel = quote.trade == Trade.tiling
        ? 'Tiling'
        : quote.trade == Trade.painting
            ? 'Painting'
            : 'Quote';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Trade badge + Quote Number + Popup Menu
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tradeIcon, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          tradeLabel,
                          style: tt.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    quote.quoteNumber,
                    style: tt.bodySmall?.copyWith(
                      color: const Color(0xFF9E9BA8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (val) {
                      if (val == 'edit') onTap();
                      if (val == 'pdf') onViewPdf();
                      if (val == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit / संपादित करें'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('View PDF / पीडीएफ'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text('Delete / हटाएं',
                                style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Middle: Customer name & items count
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.customerName,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${quote.lineItems.length} items • ${dateFormat.format(quote.createdAt)}',
                          style: tt.bodySmall?.copyWith(
                            color: const Color(0xFF9E9BA8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatRupee(quote.grandTotalRupees),
                    style: tt.titleLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Bottom hint
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.touch_app_outlined,
                      size: 13, color: Color(0xFF9E9BA8)),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to edit numbers & recreate PDF',
                    style: tt.bodySmall?.copyWith(
                      fontSize: 11,
                      color: const Color(0xFF9E9BA8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNewQuote;
  const _EmptyState({required this.onNewQuote});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: cs.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text('No quotes yet / कोई कोटेशन नहीं', style: tt.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Your spoken and drafted quotes will be saved here automatically.',
              style: tt.bodyMedium?.copyWith(color: const Color(0xFF9E9BA8)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onNewQuote,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create New Quote / नया कोटेशन बनाएं'),
            ),
          ],
        ),
      ),
    );
  }
}

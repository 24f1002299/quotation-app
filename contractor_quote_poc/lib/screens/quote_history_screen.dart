import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../storage/quote_repository.dart';
import '../storage/quote_sync_service.dart';
import '../storage/saved_quote.dart';
import '../storage/sync_outbox.dart';
import '../theme.dart';
import '../utils/error_report.dart';
import 'pdf_preview_screen.dart';
import 'quote_flag_widgets.dart';
import 'history/quote_cards.dart';
import 'review_screen.dart';

/// Day 9 & Day 16 — Interactive Quote History Screen.
///
/// Features:
/// - Uncluttered chronological quotation list.
/// - Server-side search by client name, status chips (Draft, Ready, Shared), and date.
/// - Paginated loading with offline local fallback.
/// - Conflict detection and simple conflict choice dialog when edited on another device.
/// - No analytics dashboard.
class QuoteHistoryScreen extends StatefulWidget {
  const QuoteHistoryScreen({super.key});

  @override
  State<QuoteHistoryScreen> createState() => _QuoteHistoryScreenState();
}

class _QuoteHistoryScreenState extends State<QuoteHistoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounceTimer;

  String _searchQuery = '';
  String _selectedStatus = 'All'; // 'All', 'draft', 'ready', 'shared'
  DateTime? _selectedDate;

  List<SavedQuote> _quotes = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 0;
  final int _pageSize = 10;
  bool _isLastPage = true;
  bool _isOffline = false;

  List<SyncConflict> _conflicts = [];

  // Day 20: failed-sync summary (durable outbox) with Retry + error-report ID.
  int _failedSyncCount = 0;
  String _failedSyncDetail = '';
  late final String _historyErrorId = newErrorReportId();
  bool _syncRetrying = false;

  @override
  void initState() {
    super.initState();
    _fetchQuotes(page: 0);
    _checkForConflictsAndSync();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = val.trim();
        _page = 0;
      });
      _fetchQuotes(page: 0);
    });
  }

  /// Phase 5: relative-date bucket for group headers in the list.
  static String _dateGroupLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Older';
  }

  Future<void> _checkForConflictsAndSync() async {
    try {
      final detectedConflicts = await QuoteSyncService.syncPendingQuotes();
      if (mounted) {
        setState(() {
          _conflicts = detectedConflicts;
        });
      }
    } catch (_) {}
    await _refreshFailedSyncSummary();
  }

  /// Day 20: summarize durable-outbox failures without losing any draft.
  Future<void> _refreshFailedSyncSummary() async {
    try {
      final pending = await SyncOutbox.getPending();
      final failed = pending.where(
        (o) => (o.lastError ?? '').trim().isNotEmpty || o.retryCount > 0,
      ).toList();
      if (!mounted) return;
      setState(() {
        _failedSyncCount = failed.length;
        _failedSyncDetail = failed.isEmpty
            ? ''
            : (failed.first.lastError?.trim().isNotEmpty == true
                ? failed.first.lastError!.trim()
                : '${failed.length} change(s) waiting for network');
      });
    } catch (_) {}
  }

  Future<void> _retryFailedSync() async {
    if (_syncRetrying) return;
    setState(() => _syncRetrying = true);
    try {
      final conflicts = await QuoteSyncService.syncPendingQuotes();
      if (mounted) setState(() => _conflicts = conflicts);
    } catch (_) {}
    await _refreshFailedSyncSummary();
    await _fetchQuotes(page: 0);
    if (!mounted) return;
    setState(() => _syncRetrying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _failedSyncCount > 0
              ? 'Still offline — $_failedSyncCount change(s) safe on this phone.'
              : 'Sync finished / सिंक हो गया ✓',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _fetchQuotes({required int page, bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() => _isLoading = true);
    }

    final statusParam = _selectedStatus == 'All'
        ? null
        : (_selectedStatus == 'Draft' ? 'draft' : _selectedStatus.toLowerCase());

    final dateParam = _selectedDate != null
        ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
        : null;

    final result = await QuoteSyncService.searchQuoteHistory(
      page: page,
      size: _pageSize,
      client: _searchQuery.isNotEmpty ? _searchQuery : null,
      status: statusParam,
      date: dateParam,
    );

    if (!mounted) return;

    setState(() {
      if (loadMore) {
        _quotes.addAll(result.quotes);
      } else {
        _quotes = result.quotes;
      }
      _page = result.page;
      _isLastPage = result.isLast;
      _isOffline = result.isOffline;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLastPage) return;
    await _fetchQuotes(page: _page + 1, loadMore: true);
  }

  void _showConflictDialog(SyncConflict conflict) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Version Conflict / टकराव')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This quote was edited on another device while you were offline.\n\n'
              'यह कोटेशन किसी अन्य फोन पर भी बदला गया था। कौन सा संस्करण रखना चाहते हैं?',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📱 This Phone (v${conflict.localQuote.version}):',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('${conflict.localQuote.customerName} • ${conflict.localQuote.lineItems.length} items • ₹${conflict.localQuote.grandTotalRupees}'),
                  const Divider(height: 16),
                  Text(
                    '☁️ Server / Other Device (v${conflict.serverQuote.version}):',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('${conflict.serverQuote.customerName} • ${conflict.serverQuote.lineItems.length} items • ₹${conflict.serverQuote.grandTotalRupees}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await QuoteSyncService.resolveKeepServer(conflict.localQuote.id);
              _checkForConflictsAndSync();
              _fetchQuotes(page: 0);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kept server version / सर्वर संस्करण रखा गया')),
                );
              }
            },
            child: const Text('Keep Server / सर्वर का रखें'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await QuoteSyncService.resolveKeepDevice(conflict.localQuote.id);
              _checkForConflictsAndSync();
              _fetchQuotes(page: 0);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kept this phone\'s version / इस फोन का संस्करण रखा गया')),
                );
              }
            },
            child: const Text('Keep This Phone / इस फोन का रखें'),
          ),
        ],
      ),
    );
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
      _fetchQuotes(page: 0);
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
    ).then((_) => _fetchQuotes(page: 0));
  }

  void _viewPdf(SavedQuote quote) {
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
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _page = 0;
      });
      _fetchQuotes(page: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote History / पुराने कोटेशन'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh & Sync / ताज़ा करें',
            onPressed: () {
              _checkForConflictsAndSync();
              _fetchQuotes(page: 0);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Conflict Banner (if any detected) ───────────────────────────
            if (_conflicts.isNotEmpty)
              Material(
                color: Colors.amber.shade100,
                child: InkWell(
                  onTap: () => _showConflictDialog(_conflicts.first),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.brown, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_conflicts.length} conflict(s) detected with another device. Tap to resolve.',
                            style: const TextStyle(
                              color: Colors.brown,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showConflictDialog(_conflicts.first),
                          child: const Text('Resolve'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_isOffline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.grey.shade300,
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 16, color: Colors.black54),
                    SizedBox(width: 8),
                    Text(
                      'Offline — drafts are safe on this phone',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),

            // ── Day 20: failed-sync banner (consistent Retry + Get help) ──
            if (_failedSyncCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    kPagePadding, 8, kPagePadding, 0),
                child: SyncFailureBanner(
                  detail:
                      '$_failedSyncCount change(s) waiting. $_failedSyncDetail',
                  errorReportId: _historyErrorId,
                  onRetry: _syncRetrying ? () {} : _retryFailedSync,
                ),
              ),

            // ── Search & Filter Controls ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search client or quote number / खोजें...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                ),
              ),
            ),

            // ── Filter Chips (Status & Date) ────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
              child: Row(
                children: [
                  ...['All', 'Draft', 'Ready', 'Shared'].map((status) {
                    final isSelected = _selectedStatus == status;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(status),
                        onSelected: (selected) {
                          setState(() {
                            _selectedStatus = status;
                            _page = 0;
                          });
                          _fetchQuotes(page: 0);
                        },
                      ),
                    );
                  }),
                  const SizedBox(width: 4),
                  InputChip(
                    avatar: Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: _selectedDate != null ? cs.primary : null,
                    ),
                    label: Text(
                      _selectedDate != null
                          ? DateFormat('dd MMM').format(_selectedDate!)
                          : 'Date / तारीख',
                    ),
                    selected: _selectedDate != null,
                    onPressed: _pickDate,
                    onDeleted: _selectedDate != null
                        ? () {
                            setState(() {
                              _selectedDate = null;
                              _page = 0;
                            });
                            _fetchQuotes(page: 0);
                          }
                        : null,
                  ),
                ],
              ),
            ),

            // ── Quotes List / Loading / Empty State ─────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _quotes.isEmpty
                      ? HistoryEmptyState(
                          onNewQuote: () => Navigator.pushNamed(context, '/new-quote'),
                          hasFilters: _searchQuery.isNotEmpty ||
                              _selectedStatus != 'All' ||
                              _selectedDate != null,
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            await _checkForConflictsAndSync();
                            await _fetchQuotes(page: 0);
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.all(kPagePadding),
                            itemCount: _quotes.length + (_isLastPage ? 0 : 1),
                            itemBuilder: (ctx, i) {
                              if (i == _quotes.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: _isLoadingMore
                                        ? const CircularProgressIndicator()
                                        : TextButton(
                                            onPressed: _loadMore,
                                            child: const Text('Load more / और देखें'),
                                          ),
                                  ),
                                );
                              }
                              // Phase 5: relative-date group headers
                              // (Today / Yesterday / This week / Older).
                              final group =
                                  _dateGroupLabel(_quotes[i].effectiveDate);
                              final showHeader = i == 0 ||
                                  _dateGroupLabel(
                                          _quotes[i - 1].effectiveDate) !=
                                      group;
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  if (showHeader)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 8, bottom: 4),
                                      child: Text(
                                        group,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(fontSize: 14),
                                      ),
                                    ),
                                  SavedQuoteCard(
                                    quote: _quotes[i],
                                    onTap: () =>
                                        _openQuoteForEditing(_quotes[i]),
                                    onViewPdf: () => _viewPdf(_quotes[i]),
                                    onDelete: () => _deleteQuote(_quotes[i]),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SavedQuoteCard — Uncluttered chronological quote row card

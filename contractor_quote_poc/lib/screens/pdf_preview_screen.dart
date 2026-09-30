import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../catalog/catalog.dart';
import '../models/contractor_profile.dart';
import '../models/quote.dart';
import '../models/quote_flags.dart';
import '../pdf/pdf_service.dart';
import '../storage/pdf_backup_service.dart';
import '../storage/pdf_backup_settings.dart';
import '../storage/profile_repository.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';
import '../theme.dart';
import '../utils/error_report.dart';
import '../utils/rupee_format.dart';
import 'quote_flag_widgets.dart';

/// Day 18 — PDF Preview & Share Screen.
///
/// - Saves PDFs to app-scoped storage (`quotations/Quotation_<quoteId>.pdf`).
/// - "Share PDF" is the sole primary CTA; opens Android's native share sheet
///   (WhatsApp, Gmail, Drive, …).
/// - Regeneration after editing overwrites the same app-owned file.
/// - Cloud backup to Storage happens only when the user opts in.
/// - Never claims delivery: status becomes `shared` only after the user
///   confirms "Mark as shared"; otherwise shows "Share sheet opened".
class PdfPreviewScreen extends StatefulWidget {
  final Quote quote;
  final Trade? trade;
  final int validityDays;
  final String? notes;
  final String? savedQuoteId;

  const PdfPreviewScreen({
    super.key,
    required this.quote,
    this.trade,
    this.validityDays = 15,
    this.notes,
    this.savedQuoteId,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  Uint8List? _lastGeneratedBytes;
  ContractorProfile? _profile;
  SavedQuote? _existingQuote;
  String? _savedPdfPath;
  bool _hasSaved = false;
  bool _saveAnnounced = false;

  /// Day 18 share state: '' → 'sheet-opened' → 'shared'.
  String _shareState = '';
  bool _backupOptIn = false;

  /// Day 20: stable support reference for this preview (behind Get help).
  late final String _previewErrorId = newErrorReportId();

  String get _quoteId =>
      widget.quote.id ??
      widget.savedQuoteId ??
      'quote_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadExisting();
    _loadBackupOptIn();
  }

  Future<void> _loadProfile() async {
    final profile = await ProfileRepository.getProfile();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _loadExisting() async {
    final id = widget.quote.id ?? widget.savedQuoteId;
    if (id == null) return;
    final existing = await QuoteRepository.getQuoteById(id);
    if (!mounted) return;
    setState(() {
      _existingQuote = existing;
      _savedPdfPath = existing?.pdfPath;
      if (existing?.status == 'shared') _shareState = 'shared';
    });
  }

  Future<void> _loadBackupOptIn() async {
    final optedIn = await PdfBackupSettings.isOptedIn();
    if (mounted) setState(() => _backupOptIn = optedIn);
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    // Day 24: wall-time for the device test matrix (debug builds only).
    final perfTimer = Stopwatch()..start();
    final bytes = await PdfService.generateQuotationPdf(
      quote: widget.quote,
      profile: _profile,
      format: format,
      trade: widget.trade,
      validityDays: widget.quote.validityDays > 0
          ? widget.quote.validityDays
          : widget.validityDays,
      notes: widget.quote.notes.isNotEmpty ? widget.quote.notes : widget.notes,
      quoteDate: widget.quote.quoteDate,
      quoteNumber: widget.quote.displayNumber,
    );
    debugPrint(
      '[perf] pdf render wall-time=${perfTimer.elapsedMilliseconds}ms '
      'bytes=${bytes.length}',
    );

    _lastGeneratedBytes = bytes;

    // Persist once per screen instance (fire-and-forget).
    // Regeneration after editing pushes a NEW screen instance, which saves
    // to the same stable path and overwrites the previous app-owned file.
    if (!_hasSaved) {
      _hasSaved = true;
      _saveQuoteAndPdf(bytes);
    }

    return bytes;
  }

  Future<void> _saveQuoteAndPdf(Uint8List bytes) async {
    try {
      // Day 18: stable path — regeneration replaces the same app-owned file.
      final savedPath = await PdfService.savePdfReplacingPrevious(
        bytes: bytes,
        quoteId: _quoteId,
        existingPdfPath: _existingQuote?.pdfPath ?? _savedPdfPath,
      );

      final now = DateTime.now();
      final id = _quoteId;
      final existing = _existingQuote ??
          await QuoteRepository.getQuoteById(id);

      final saved = SavedQuote(
        id: id,
        quoteNumber: widget.quote.quoteNumber ??
            existing?.quoteNumber ??
            'Q-${now.year}-${id.length > 4 ? id.substring(id.length - 4) : id}',
        serverDisplayNumber:
            widget.quote.serverDisplayNumber ?? existing?.serverDisplayNumber,
        createdAt: existing?.createdAt ?? now,
        quoteDate: widget.quote.quoteDate ?? existing?.quoteDate ?? now,
        trade: widget.trade ?? existing?.trade,
        customerName: widget.quote.customer.name.trim().isEmpty
            ? (existing?.customerName ?? 'Client')
            : widget.quote.customer.name.trim(),
        customerPhone: widget.quote.customer.phone.trim().isEmpty
            ? (existing?.customerPhone ?? '')
            : widget.quote.customer.phone.trim(),
        customerAddress: widget.quote.customer.address.trim().isEmpty
            ? (existing?.customerAddress ?? '')
            : widget.quote.customer.address.trim(),
        validityDays: widget.quote.validityDays > 0
            ? widget.quote.validityDays
            : (existing?.validityDays ?? widget.validityDays),
        advancePercent:
            widget.quote.advancePercent ?? existing?.advancePercent,
        advanceText: widget.quote.advanceText.isNotEmpty
            ? widget.quote.advanceText
            : (existing?.advanceText ?? ''),
        notes: widget.quote.notes.isNotEmpty
            ? widget.quote.notes
            : (widget.notes ?? existing?.notes ?? ''),
        terms: widget.quote.terms.isEmpty
            ? (existing?.terms ?? const [])
            : widget.quote.terms,
        originalTranscript:
            widget.quote.originalTranscript ?? existing?.originalTranscript,
        reviewWarnings:
            widget.quote.reviewWarnings.isEmpty
                ? (existing?.reviewWarnings ?? const [])
                : widget.quote.reviewWarnings,
        reviewWarningsAcknowledged:
            widget.quote.reviewWarningsAcknowledged ||
                (existing?.reviewWarningsAcknowledged ?? false),
        lineItems: widget.quote.lineItems,
        gstPercent: widget.quote.gstPercent ?? existing?.gstPercent,
        pdfPath: savedPath,
        // Regeneration resets an already-shared quote to ready until the
        // user shares the new file; a never-shared quote is ready.
        status: _shareState == 'shared' && existing?.status == 'shared'
            ? 'shared'
            : 'ready',
        version: (existing?.version ?? 0) + 1,
      );

      await QuoteRepository.saveQuote(saved);
      if (!mounted) return;
      setState(() {
        _savedPdfPath = savedPath;
        _existingQuote = saved;
      });

      // Opt-in cloud backup only — never automatic.
      await PdfBackupService.backupPdfIfOptedIn(
        quoteId: id,
        pdfPath: savedPath,
      );

      if (mounted && !_saveAnnounced) {
        _saveAnnounced = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'PDF saved on this phone / पीडीएफ इस फोन में सहेजी गई',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View History',
              onPressed: () => Navigator.pushNamed(context, '/history'),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _sharePdf() async {
    final bytes = _lastGeneratedBytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF is still generating… / कृपया प्रतीक्षा करें'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          PdfService.shareFileNameForQuote(widget.quote.customer.name),
    );
    if (!mounted) return;
    // Android's share sheet gives no delivery receipt — record only that
    // the sheet was opened, and ask the user to confirm.
    setState(() => _shareState = 'sheet-opened');
    _showMarkSharedDialog();
  }

  void _showMarkSharedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share sheet opened'),
        content: const Text(
          'Android can send this PDF to WhatsApp, Gmail, Drive, or any app '
          'you choose.\n\nWe cannot confirm delivery — '
          'mark as shared only after you have sent it.\n'
          'शीट खुल गई है — भेजने के बाद "Mark as shared" दबाएं।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not yet / अभी नहीं'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markAsShared();
            },
            child: const Text('Mark as shared'),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsShared() async {
    final existing = _existingQuote ??
        await QuoteRepository.getQuoteById(_quoteId);
    final updated = (existing ??
            SavedQuote(
              id: _quoteId,
              quoteNumber: widget.quote.displayNumber,
              createdAt: DateTime.now(),
              customerName: widget.quote.customer.name,
              lineItems: widget.quote.lineItems,
              pdfPath: _savedPdfPath,
            ))
        .copyWith(status: 'shared', pdfPath: _savedPdfPath);
    await QuoteRepository.saveQuote(updated);
    if (!mounted) return;
    setState(() {
      _shareState = 'shared';
      _existingQuote = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Marked as shared / साझा किया गया ✓'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleBackup(bool value) async {
    setState(() => _backupOptIn = value);
    await PdfBackupSettings.setOptedIn(value);
    if (value && _savedPdfPath != null) {
      await PdfBackupService.backupPdfIfOptedIn(
        quoteId: _quoteId,
        pdfPath: _savedPdfPath!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud backup enabled / क्लाउड बैकअप चालू'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final tradeBadge = widget.trade == null
        ? null
        : Chip(
            label: Text(
              widget.trade == Trade.tiling ? '🪣 Tiling' : '🖌️ Painting',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            backgroundColor: cs.primary.withValues(alpha: 0.15),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
            visualDensity: VisualDensity.compact,
          );

    final blockingReason = quotePdfBlockingReason(widget.quote);
    if (blockingReason != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF Preview / पूर्वावलोकन')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 48, color: cs.error),
                  const SizedBox(height: 16),
                  Text(
                    'This quote is not ready for PDF / यह कोटेशन अभी PDF के लिए तैयार नहीं है',
                    style: tt.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    blockingReason,
                    style: tt.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your work is saved — go back, fix the highlighted item, then come back.',
                    style: tt.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back and fix / वापस जाकर ठीक करें'),
                  ),
                  TextButton(
                    onPressed: () => showErrorHelpDialog(
                      context,
                      area: 'PDF preview',
                      errorReportId: _previewErrorId,
                    ),
                    child: const Text('Get help'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final totals = calculateTotals(widget.quote);
    final dateLabel =
        DateFormat('dd MMM yyyy').format(widget.quote.quoteDate ?? DateTime.now());
    final metaLine =
        'Quote ${widget.quote.displayNumber} · ${formatRupeePaise(totals.grandTotalPaise)} · $dateLabel';

    // Day 20: non-blocking warnings ride along to the PDF screen so an
    // unusual rate or missing customer never looks silently confident.
    final pdfWarnings = warningFlags(analyzeQuote(widget.quote));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Quotation ready'),
            if (tradeBadge != null) ...[const SizedBox(width: 10), tradeBadge],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share via WhatsApp / शेयर करें',
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PdfPreview(
                build: _buildPdf,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                allowPrinting: true,
                allowSharing: true,
                pdfFileName: PdfService.shareFileNameForQuote(
                    widget.quote.customer.name),
                loadingWidget: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: cs.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Generating PDF / पीडीएफ तैयार हो रही है…',
                        style: tt.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ── Day 18 primary completion action ──────────────────────
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                  kPagePadding, 12, kPagePadding, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    metaLine,
                    style: tt.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_shareState == 'sheet-opened')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Share sheet opened — not yet marked as shared',
                        style: tt.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_shareState == 'shared')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 14, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Shared ✓',
                            style: tt.bodySmall?.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  // ── Day 20: non-blocking confirmations + Get help ───
                  if (pdfWarnings.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9FB8AD).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF475841).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final w in pdfWarnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(iconForFlag(w.type),
                                      size: 16,
                                      color: forest),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(w.message,
                                        style: tt.bodySmall),
                                  ),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => showErrorHelpDialog(
                                context,
                                area: 'PDF preview',
                                errorReportId: _previewErrorId,
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                              ),
                              child: const Text('Get help'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton.icon(
                    onPressed: _sharePdf,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: forest,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Edit quote'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saved on this phone. Editing & regenerating replaces the same file.',
                          style: tt.bodySmall,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Backup', style: TextStyle(fontSize: 12)),
                          Switch(
                            value: _backupOptIn,
                            onChanged: _toggleBackup,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ],
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

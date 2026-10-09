import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../l10n/app_strings.dart';
import '../templates/template_data.dart';
import '../models/business_profile.dart';
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
import 'review_screen.dart';

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
  final BusinessType? businessType;
  final int validityDays;
  final String? notes;
  final String? savedQuoteId;

  const PdfPreviewScreen({
    super.key,
    required this.quote,
    this.businessType,
    this.validityDays = 15,
    this.notes,
    this.savedQuoteId,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  Uint8List? _lastGeneratedBytes;
  BusinessProfile? _profile;
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
      businessType: widget.businessType,
      businessTypeCustom: _profile?.customBusinessType ?? '',
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
      // Announce only on first generation: opening from history (or
      // regenerating after an edit) already has a saved file on disk.
      final preExisting =
          _existingQuote ?? await QuoteRepository.getQuoteById(_quoteId);
      final isFirstGeneration =
          (preExisting?.pdfPath ?? _savedPdfPath) == null;

      // Day 18: stable path — regeneration replaces the same app-owned file.
      final savedPath = await PdfService.savePdfReplacingPrevious(
        bytes: bytes,
        quoteId: _quoteId,
        existingPdfPath: _existingQuote?.pdfPath ?? _savedPdfPath,
      );

      final now = DateTime.now();
      final id = _quoteId;
      final existing = preExisting;

      final saved = SavedQuote(
        id: id,
        quoteNumber: widget.quote.quoteNumber ??
            existing?.quoteNumber ??
            'Q-${now.year}-${id.length > 4 ? id.substring(id.length - 4) : id}',
        serverDisplayNumber:
            widget.quote.serverDisplayNumber ?? existing?.serverDisplayNumber,
        createdAt: existing?.createdAt ?? now,
        quoteDate: widget.quote.quoteDate ?? existing?.quoteDate ?? now,
        businessType: widget.businessType ?? existing?.businessType,
      businessTypeLabel: (_profile?.businessType == BusinessType.other)
          ? (_profile?.customBusinessType.trim() ?? '')
          : (existing?.businessTypeLabel ?? ''),
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

      if (mounted && !_saveAnnounced && isFirstGeneration) {
        _saveAnnounced = true;
        // Transient dark pill — floats above the bottom action bar (which
        // lives in Scaffold.bottomNavigationBar, above which floating
        // snackbars automatically sit), so it never covers any buttons.
        // No action inside: View history already exists on the screen.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.save_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    AppStrings.read(context, 'offline_saved'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 48),
            duration: const Duration(milliseconds: 3500),
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
        SnackBar(
          content: Text(AppStrings.read(context, 'pdf_generating')),
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
        title: Text(AppStrings.of(ctx, 'share_sheet_opened')),
        content: Text(
          AppStrings.of(ctx, 'share_sheet_info'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(ctx, 'not_yet')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markAsShared();
            },
            child: Text(AppStrings.of(ctx, 'mark_shared')),
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
      SnackBar(
        content: Text(AppStrings.read(context, 'marked_shared')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Deterministic return-to-editing (Day-24 device fix).
  ///
  /// The old blind `pop()` assumed the Review screen was underneath Preview,
  /// which is false from History → "view PDF" and proved unreliable on-device
  /// (users landed on Home). Instead, rebuild Review from the latest saved
  /// state and replace Preview, so Back from Review lands on a sensible
  /// parent on every entry path.
  Future<void> _editQuote() async {
    final saved =
        _existingQuote ?? await QuoteRepository.getQuoteById(_quoteId);
    if (!mounted) return;
    if (saved == null) {
      // Nothing persisted (shouldn't happen — a PDF implies a save).
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        // Same field mapping as history "open for editing".
        builder: (_) => ReviewScreen(
          savedQuoteId: saved.id,
          businessType: saved.businessType ?? widget.businessType,
          customerName: saved.customerName,
          customerPhone: saved.customerPhone,
          customerAddress: saved.customerAddress,
          validityDays: saved.validityDays,
          gstPercent: saved.gstPercent,
          advancePercent: saved.advancePercent,
          advanceText: saved.advanceText,
          terms: saved.terms,
          quoteDate: saved.effectiveDate,
          displayNumber: saved.quoteNumber,
          serverDisplayNumber: saved.serverDisplayNumber,
          notes: saved.notes,
          originalTranscript: saved.originalTranscript,
          parsingWarnings: saved.reviewWarnings,
          parsingWarningsAcknowledged: saved.reviewWarningsAcknowledged,
          initialLineItems: saved.lineItems,
        ),
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
        SnackBar(
          content: Text(AppStrings.read(context, 'backup_enabled')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Quick action: print the generated bytes via the system print dialog.
  Future<void> _printPdf() async {
    final bytes = _lastGeneratedBytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.read(context, 'pdf_generating')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: PdfService.shareFileNameForQuote(widget.quote.customer.name),
    );
  }

  /// Quick action: copy a short quote summary to the clipboard.
  Future<void> _copyDetails() async {
    final totals = calculateTotals(widget.quote);
    final dateLabel = DateFormat(
      'dd MMM yyyy',
    ).format(widget.quote.quoteDate ?? DateTime.now());
    await Clipboard.setData(
      ClipboardData(
        text: 'Quote ${widget.quote.displayNumber}\n'
            '${widget.quote.customer.name}\n'
            '${formatRupeePaise(totals.grandTotalPaise)} · $dateLabel',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.read(context, 'copied_to_clipboard')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Quick action: persist the bytes to the stable app-owned file again.
  Future<void> _saveNow() async {
    final bytes = _lastGeneratedBytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.read(context, 'pdf_generating')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final savedPath = await PdfService.savePdfReplacingPrevious(
        bytes: bytes,
        quoteId: _quoteId,
        existingPdfPath: _existingQuote?.pdfPath ?? _savedPdfPath,
      );
      if (!mounted) return;
      setState(() => _savedPdfPath = savedPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.read(context, 'offline_saved')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {}
  }

  /// Tap on the hero preview opens a full-screen PDF viewer.
  void _openFullScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar:
              AppBar(title: Text(AppStrings.of(context, 'pdf_preview'))),
          body: PdfPreview(
            build: _buildPdf,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            allowPrinting: true,
            allowSharing: true,
            pdfFileName: PdfService.shareFileNameForQuote(
              widget.quote.customer.name,
            ),
          ),
        ),
      ),
    );
  }

  /// Collapsed warnings disclosure: details live in a bottom sheet so the
  /// success moment stays intact.
  void _showWarningsSheet(List<QuoteFlag> warnings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(iconForFlag(w.type), size: 20, color: kForest),
                      const SizedBox(width: 10),
                      Expanded(child: Text(w.message)),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => showErrorHelpDialog(
                    ctx,
                    area: 'PDF preview',
                    errorReportId: _previewErrorId,
                  ),
                  child: Text(AppStrings.of(ctx, 'get_help')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // Generic business-type badge from metadata — all types render.
    // Free-text businesses show the profile's custom name.
    final businessTypeBadge = widget.businessType == null
        ? null
        : Chip(
            label: Text(
              quoteBusinessLabel(
                widget.businessType,
                _profile?.customBusinessType ?? '',
                'en',
              ),
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            backgroundColor: cs.primary.withValues(alpha: 0.15),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
            visualDensity: VisualDensity.compact,
          );

    final blockingReason = quotePdfBlockingReason(widget.quote);
    if (blockingReason != null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.of(context, 'pdf_preview'))),
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
                    AppStrings.of(context, 'quote_not_ready'),
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
                    AppStrings.of(context, 'fix_highlighted_item'),
                    style: tt.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppStrings.of(context, 'go_back_fix')),
                  ),
                  TextButton(
                    onPressed: () => showErrorHelpDialog(
                      context,
                      area: 'PDF preview',
                      errorReportId: _previewErrorId,
                    ),
                    child: Text(AppStrings.of(context, 'get_help')),
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
        // Flexible title: the middle slot is only ~224px once the back
        // button and chip take their space; an inflexible Row overflowed by
        // ~20px on 360dp-wide phones (Day-24 device finding).
        // No share action here — sharing lives in the bottom CTA.
        title: Row(
          children: [
            Flexible(
              child: Text(
                AppStrings.of(context, 'quotation_ready'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (businessTypeBadge != null) ...[
              const SizedBox(width: 8),
              businessTypeBadge,
            ],
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    kPagePadding, 20, kPagePadding, 16),
                child: Column(
                  children: [
                    // ── Success hero: celebration moment ──
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) => Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: Transform.scale(scale: value, child: child),
                      ),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [kForest, Colors.green.shade600],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  kForest.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 42,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.of(context, 'quote_ready_headline'),
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        metaLine,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── PDF preview: the hero element ──
                    GestureDetector(
                      onTap: _openFullScreen,
                      child: Container(
                        height: (MediaQuery.of(context).size.height * 0.5)
                            .clamp(320.0, 560.0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Transform.rotate(
                          angle: 0.015,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: PdfPreview(
                              build: _buildPdf,
                              // No internal action bar — actions live in
                              // the quick-action row and bottom CTA.
                              useActions: false,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                              canDebug: false,
                              allowPrinting: true,
                              allowSharing: true,
                              pdfFileName:
                                  PdfService.shareFileNameForQuote(
                                widget.quote.customer.name,
                              ),
                              scrollViewDecoration: const BoxDecoration(
                                color: Colors.transparent,
                              ),
                              pdfPreviewPageDecoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.18),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              loadingWidget: Center(
                                // Scrollable: PdfPreview measures this with
                                // near-zero height on first layout; a bare
                                // Column overflows and trips the RenderFlex
                                // assertion on device.
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                          color: cs.primary),
                                      const SizedBox(height: 16),
                                      Text(
                                        AppStrings.of(
                                            context, 'pdf_generating'),
                                        style: tt.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.of(context, 'tap_to_preview_full'),
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // ── Quick action row ──
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _printPdf,
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: Text(
                                AppStrings.of(context, 'action_print')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyDetails,
                            icon:
                                const Icon(Icons.content_copy_rounded, size: 18),
                            label:
                                Text(AppStrings.of(context, 'action_copy')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saveNow,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label:
                                Text(AppStrings.of(context, 'action_save')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // ── Sticky bottom bar: one cohesive sheet ──
      // Lives in bottomNavigationBar so the transient "saved offline" pill
      // snackbar floats above it and never covers these actions.
      bottomNavigationBar: SafeArea(
        child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
                border: Border(
                  top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                  kPagePadding, 8, kPagePadding, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Collapsed warnings disclosure — success stays intact.
                  if (pdfWarnings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        onTap: () => _showWarningsSheet(pdfWarnings),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Colors.amber.shade900,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  AppStrings.of(
                                          context, 'flagged_disclosure')
                                      .replaceAll(
                                          '{n}', '${pdfWarnings.length}'),
                                  style: tt.bodySmall?.copyWith(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _editQuote,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label:
                            Text(AppStrings.of(context, 'edit_quote')),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: AppStrings.of(context, 'pdf_backup'),
                        child: Switch(
                          value: _backupOptIn,
                          onChanged: _toggleBackup,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/history'),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label:
                            Text(AppStrings.of(context, 'view_history')),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  if (_shareState == 'sheet-opened')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        AppStrings.of(context, 'share_sheet_opened_note'),
                        style: tt.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_shareState == 'shared')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 14, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Text(
                            AppStrings.of(context, 'shared'),
                            style: tt.bodySmall?.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _sharePdf,
                    icon: const Icon(Icons.share_rounded),
                    label: Text(AppStrings.of(context, 'share_pdf')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kForest,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  }
}

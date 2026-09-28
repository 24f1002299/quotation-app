import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../catalog/catalog.dart';
import '../models/contractor_profile.dart';
import '../models/quote.dart';
import '../utils/quote_ids.dart';
import '../utils/rupee_format.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design palette — from design.md
// White page, ink body text, forest headings/rules, thin sage accent.
// ─────────────────────────────────────────────────────────────────────────────
final _pForest = PdfColor.fromHex('#475841'); // headings, rules, totals
final _pInk = PdfColor.fromHex('#3F403F');    // body text
final _pSage = PdfColor.fromHex('#9FB8AD');   // accent labels
final _pSageMuted = PdfColor.fromHex('#CED0CE'); // borders, dividers
const double _kPageMargin = 32;

/// Holds regular + bold variants of the Devanagari-capable font.
class PdfFontSet {
  final pw.Font regular;
  final pw.Font bold;

  const PdfFontSet({required this.regular, required this.bold});
}

/// Day 17 — On-device quotation PDF generator.
///
/// Builds a clean, branded single-page A4 quotation PDF suitable for Indian
/// contractors and clients. Supports bilingual English/Hindi text, business
/// branding, itemized billing, totals, terms, and signature space.
class PdfService {
  // ── Font loading ────────────────────────────────────────────────────────────

  /// Loads fonts with a 3-tier fallback strategy:
  /// 1. Bundled NotoSansDevanagari assets (offline, Devanagari-capable)
  /// 2. Google Fonts online cache (needs network on first use)
  /// 3. Built-in Helvetica (Latin-only safe fallback)
  static Future<PdfFontSet> loadFonts() async {
    pw.Font? regular;
    pw.Font? bold;

    // Try bundled regular
    try {
      final data = await rootBundle
          .load('assets/fonts/NotoSansDevanagari-Regular.ttf');
      regular = pw.Font.ttf(data);
    } catch (_) {
      try {
        final data =
            await rootBundle.load('assets/fonts/NotoSansDevanagari.ttf');
        regular = pw.Font.ttf(data);
      } catch (_) {}
    }

    // Try bundled bold (reuse regular when not bundled separately)
    try {
      final data =
          await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf');
      bold = pw.Font.ttf(data);
    } catch (_) {
      bold = regular; // pdf package synthesises bold weight from regular
    }

    if (regular != null && bold != null) {
      return PdfFontSet(regular: regular, bold: bold);
    }

    // Google Fonts fallback
    try {
      final r = await PdfGoogleFonts.notoSansDevanagariRegular();
      final b = await PdfGoogleFonts.notoSansDevanagariBold();
      return PdfFontSet(regular: r, bold: b);
    } catch (_) {}

    // Latin-only Helvetica last resort
    return PdfFontSet(
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );
  }

  // ── File storage ────────────────────────────────────────────────────────────

  /// Saves [bytes] into app-scoped documents/quotations directory.
  /// Returns the absolute path of the saved PDF file.
  static Future<String> savePdfToAppStorage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final quotesDir = Directory('${dir.path}/quotations');
    if (!await quotesDir.exists()) {
      await quotesDir.create(recursive: true);
    }
    final file = File('${quotesDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Day 18 — Stable app-scoped file name for a quote.
  ///
  /// Uses the immutable quote ID as the anchor so regeneration overwrites
  /// the same app-owned file instead of creating timestamp orphans.
  /// Pure (no platform calls) so it is unit-testable.
  static String stableFileNameForQuote(String quoteId) {
    final raw = quoteId.trim().isEmpty ? 'quote' : quoteId.trim();
    final sanitized = raw
        .replaceAll(RegExp(r'[^\w\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final short = sanitized.length > 48
        ? sanitized.substring(sanitized.length - 48)
        : sanitized;
    return 'Quotation_$short.pdf';
  }

  /// Day 18 — Friendly file name for the Android share sheet / WhatsApp.
  /// Only used as the share-sheet label; storage always uses [stableFileNameForQuote].
  /// Pure (no platform calls) so it is unit-testable.
  static String shareFileNameForQuote(String customerName) {
    final raw = customerName.trim().isEmpty ? 'Client' : customerName.trim();
    final sanitized = raw
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final short = sanitized.isEmpty
        ? 'Client'
        : (sanitized.length > 32 ? sanitized.substring(0, 32) : sanitized);
    return 'Quotation_$short.pdf';
  }

  /// Day 18 — Saves [bytes] to the stable app-owned path for [quoteId],
  /// overwriting the previous file when it exists.
  ///
  /// When [existingPdfPath] points to an older timestamp-named file for the
  /// same quote, the new bytes go to the stable path and the old file is
  /// deleted. Only files inside the app `quotations/` dir are ever touched.
  static Future<String> savePdfReplacingPrevious({
    required Uint8List bytes,
    required String quoteId,
    String? existingPdfPath,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final quotesDir = Directory('${dir.path}/quotations');
    if (!await quotesDir.exists()) {
      await quotesDir.create(recursive: true);
    }
    final stablePath = '${quotesDir.path}/${stableFileNameForQuote(quoteId)}';

    // Fast path: previous save already used the stable path — overwrite it.
    if (existingPdfPath != null && existingPdfPath == stablePath) {
      final file = File(stablePath);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }

    final stableFile = File(stablePath);
    await stableFile.writeAsBytes(bytes, flush: true);

    // Migrate: remove the old timestamp-named file, but only when it is
    // inside our own app-scoped quotations directory.
    try {
      if (existingPdfPath != null &&
          existingPdfPath != stablePath &&
          existingPdfPath.startsWith(quotesDir.path)) {
        final oldFile = File(existingPdfPath);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }
    } catch (_) {
      // Cleanup is best-effort; the new stable file is already written.
    }
    return stableFile.path;
  }

  // ── Logo loader ─────────────────────────────────────────────────────────────

  /// Tries to load a logo image from a local file path.
  /// Returns null when the file is absent or unreadable.
  static Future<pw.MemoryImage?> _loadLogoImage(String? logoPath) async {
    if (logoPath == null || logoPath.trim().isEmpty) return null;
    try {
      final file = File(logoPath.trim());
      if (await file.exists()) {
        return pw.MemoryImage(await file.readAsBytes());
      }
    } catch (_) {}
    return null;
  }

  // ── Main generator ──────────────────────────────────────────────────────────

  /// Generates the complete A4 PDF document bytes for [quote].
  ///
  /// Pass a [profile] to include live business details and logo.
  /// Set [showFreeTierFooter] to true to render a small attribution line.
  static Future<Uint8List> generateQuotationPdf({
    required Quote quote,
    ContractorProfile? profile,
    PdfPageFormat format = PdfPageFormat.a4,
    Trade? trade,
    // Legacy override params used when profile is null
    String contractorName = '',
    String contractorPhone = '',
    String contractorAddress = '',
    String quoteNumber = '',
    DateTime? quoteDate,
    int validityDays = 15,
    String? notes,
    PdfFontSet? fontSet,
    bool showFreeTierFooter = false,
  }) async {
    final fonts = fontSet ?? await loadFonts();

    // ── Resolve business identity ──────────────────────────────────────────
    final bizName = (profile?.businessName.trim().isNotEmpty == true
            ? profile!.businessName.trim()
            : contractorName.trim().isNotEmpty
                ? contractorName.trim()
                : 'Your Business Name')
        .trim();

    final bizPhone = profile?.phone.trim().isNotEmpty == true
        ? profile!.phone.trim()
        : contractorPhone.trim();

    final bizCity = profile?.city.trim().isNotEmpty == true
        ? profile!.city.trim()
        : contractorAddress.trim();

    final gstin = profile?.gstin?.trim();
    final effectiveTrade = trade ?? profile?.trade;

    final tradeLabel = effectiveTrade == Trade.tiling
        ? 'Tiling & Flooring Contractor'
        : effectiveTrade == Trade.painting
            ? 'Painting & Surface Finishing'
            : 'Civil & Interior Contractor';

    // ── Resolve quote metadata ─────────────────────────────────────────────
    final effectiveQuoteNumber =
        quote.serverDisplayNumber?.trim().isNotEmpty == true
            ? quote.serverDisplayNumber!.trim()
            : quote.quoteNumber?.trim().isNotEmpty == true
                ? quote.quoteNumber!.trim()
                : quoteNumber.trim().isNotEmpty
                    ? quoteNumber.trim()
                    : 'Q-2026-0001';

    final date = quote.quoteDate ?? quoteDate ?? DateTime.now();
    final effectiveValidityDays =
        quote.validityDays > 0 ? quote.validityDays : validityDays;
    final expiryDate = date.add(Duration(days: effectiveValidityDays));
    final effectiveNotes = quote.notes.trim().isNotEmpty
        ? quote.notes.trim()
        : (notes?.trim() ?? '');

    final totals = calculateTotals(quote);
    final dateFormat = DateFormat('dd MMM yyyy');

    // ── Load logo ──────────────────────────────────────────────────────────
    final logoImage = await _loadLogoImage(profile?.logoPath);
    final hasLogo = logoImage != null;
    final initials = _initials(bizName);

    // ── Build PDF ──────────────────────────────────────────────────────────
    final pdf = pw.Document(
      title: 'Quotation $effectiveQuoteNumber',
      author: bizName,
    );

    final theme = pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(_kPageMargin),
        theme: theme,
        footer: (pw.Context ctx) => _buildFooter(
          context: ctx,
          bizName: bizName,
          quoteId: quote.id,
          quoteNumber: effectiveQuoteNumber,
          showFreeTierFooter: showFreeTierFooter,
        ),
        build: (pw.Context context) => [
          // 1. Header — logo + business details + quote metadata badge
          _buildHeader(
            bizName: bizName,
            bizPhone: bizPhone,
            bizCity: bizCity,
            tradeLabel: tradeLabel,
            gstin: gstin,
            logoImage: logoImage,
            hasLogo: hasLogo,
            initials: initials,
            effectiveQuoteNumber: effectiveQuoteNumber,
            date: date,
            expiryDate: expiryDate,
            effectiveValidityDays: effectiveValidityDays,
            dateFormat: dateFormat,
          ),

          pw.SizedBox(height: 10),
          pw.Divider(color: _pForest, thickness: 1.5),
          pw.SizedBox(height: 8),

          // 2. Customer / site box
          _buildCustomerBox(
            quote: quote,
            effectiveTrade: effectiveTrade,
          ),

          pw.SizedBox(height: 12),

          // 3. Line-items table
          _buildLineItemTable(quote: quote),

          pw.SizedBox(height: 12),

          // 4. Totals + notes + terms
          _buildTotalsAndTerms(
            quote: quote,
            totals: totals,
            effectiveNotes: effectiveNotes,
            effectiveValidityDays: effectiveValidityDays,
          ),

          pw.SizedBox(height: 20),

          // 5. Signature row
          _buildSignatureRow(bizName: bizName),
        ],
      ),
    );

    return pdf.save();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section builders
  // ─────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader({
    required String bizName,
    required String bizPhone,
    required String bizCity,
    required String tradeLabel,
    required String? gstin,
    required pw.MemoryImage? logoImage,
    required bool hasLogo,
    required String initials,
    required String effectiveQuoteNumber,
    required DateTime date,
    required DateTime expiryDate,
    required int effectiveValidityDays,
    required DateFormat dateFormat,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // Left: logo + business details
        pw.Expanded(
          flex: 6,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Logo or initials monogram
              pw.Container(
                width: 52,
                height: 52,
                decoration: pw.BoxDecoration(
                  color: hasLogo
                      ? PdfColor.fromHex('#F5F7F5')
                      : _pForest,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _pSageMuted, width: 0.5),
                ),
                child: hasLogo
                    ? pw.ClipRRect(
                        horizontalRadius: 8,
                        verticalRadius: 8,
                        child: pw.Image(
                          logoImage!,
                          fit: pw.BoxFit.contain,
                          width: 52,
                          height: 52,
                        ),
                      )
                    : pw.Center(
                        child: pw.Text(
                          initials,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      bizName,
                      // Shrink font for long business names
                      style: pw.TextStyle(
                        fontSize: bizName.length > 30 ? 10 : 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _pForest,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      tradeLabel,
                      style: pw.TextStyle(fontSize: 8.5, color: _pInk),
                    ),
                    if (bizPhone.isNotEmpty || bizCity.isNotEmpty) ...
                      [
                        pw.SizedBox(height: 2),
                        pw.Text(
                          [
                            if (bizPhone.isNotEmpty) 'Ph: $bizPhone',
                            if (bizCity.isNotEmpty) bizCity,
                          ].join('  •  '),
                          style: pw.TextStyle(fontSize: 7.5, color: _pInk),
                        ),
                      ],
                    if (gstin != null && gstin.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 1),
                        child: pw.Text(
                          'GSTIN: $gstin',
                          style: pw.TextStyle(fontSize: 7, color: _pInk),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(width: 12),

        // Right: quotation metadata badge
        pw.Expanded(
          flex: 4,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F5F7F5'),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _pSageMuted, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'QUOTATION / कोटेशन',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _pForest,
                  ),
                ),
                pw.SizedBox(height: 5),
                _metaRow('Quote #', effectiveQuoteNumber),
                _metaRow('Date', dateFormat.format(date)),
                _metaRow(
                  'Valid until',
                  dateFormat.format(expiryDate),
                  valueColor: _pForest,
                  valueBold: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildCustomerBox({
    required Quote quote,
    required Trade? effectiveTrade,
  }) {
    final clientName = quote.customer.name.trim().isEmpty
        ? 'Valued Client'
        : quote.customer.name.trim();

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F5F7F5'),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _pSageMuted, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Client details
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'QUOTED FOR / ग्राहक विवरण',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: _pSage,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  clientName,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _pForest,
                  ),
                ),
                if (quote.customer.phone.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      'Phone: ${quote.customer.phone.trim()}',
                      style: pw.TextStyle(fontSize: 8.5, color: _pInk),
                    ),
                  ),
                if (quote.customer.address.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      'Site: ${quote.customer.address.trim()}',
                      style: pw.TextStyle(fontSize: 8.5, color: _pInk),
                    ),
                  ),
              ],
            ),
          ),
          // Project type
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'PROJECT / कार्य',
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: _pSage,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                effectiveTrade == Trade.tiling
                    ? 'Tiling & Flooring'
                    : effectiveTrade == Trade.painting
                        ? 'Painting & Surface Finish'
                        : 'Labour & Materials',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _pInk,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildLineItemTable({required Quote quote}) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _pSageMuted, width: 0.5),
        bottom: pw.BorderSide(color: _pForest, width: 1),
      ),
      columnWidths: const {
        0: pw.FixedColumnWidth(22), // S.No
        1: pw.FlexColumnWidth(5),   // Description
        2: pw.FixedColumnWidth(48), // Qty
        3: pw.FixedColumnWidth(44), // Unit
        4: pw.FixedColumnWidth(64), // Rate
        5: pw.FixedColumnWidth(72), // Amount
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _pForest),
          children: [
            _th('#', align: pw.TextAlign.center),
            _th('Item & Description / मद का विवरण'),
            _th('Qty / मात्रा', align: pw.TextAlign.right),
            _th('Unit', align: pw.TextAlign.center),
            _th('Rate / दर', align: pw.TextAlign.right),
            _th('Amount / कुल', align: pw.TextAlign.right),
          ],
        ),
        // Data rows
        for (var i = 0; i < quote.lineItems.length; i++)
          _buildTableRow(
            index: i + 1,
            item: quote.lineItems[i],
            isEven: i % 2 == 0,
          ),
      ],
    );
  }

  static pw.Widget _buildTotalsAndTerms({
    required Quote quote,
    required QuoteTotals totals,
    required String effectiveNotes,
    required int effectiveValidityDays,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: notes + terms
        pw.Expanded(
          flex: 6,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (effectiveNotes.isNotEmpty) ...[
                pw.Text(
                  'Special Notes / विशेष विवरण',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _pForest,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F5F7F5'),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: _pSageMuted, width: 0.5),
                  ),
                  child: pw.Text(
                    effectiveNotes,
                    style: pw.TextStyle(fontSize: 8, color: _pInk),
                  ),
                ),
                pw.SizedBox(height: 8),
              ],
              pw.Text(
                'Terms & Conditions / नियम व शर्तें',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _pInk,
                ),
              ),
              pw.SizedBox(height: 3),
              _termBullet(
                  '• Estimate valid for $effectiveValidityDays days from date of issue.'),
              if (quote.effectiveAdvanceText.isNotEmpty)
                _termBullet('• Advance: ${quote.effectiveAdvanceText}.'),
              for (final term in quote.effectiveTerms)
                _termBullet('• $term'),
            ],
          ),
        ),

        pw.SizedBox(width: 16),

        // Right: totals box
        pw.Expanded(
          flex: 4,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F5F7F5'),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _pSageMuted, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _totalRow(
                  label: 'Subtotal / उप-योग',
                  value: formatRupeePaise(totals.subtotalPaise),
                ),
                if (quote.gstPercent != null && quote.gstPercent! > 0) ...[
                  pw.SizedBox(height: 4),
                  _totalRow(
                    label: 'GST (${quote.gstPercent}%)',
                    value: formatRupeePaise(totals.gstPaise),
                    labelFontSize: 8.5,
                    valueFontSize: 8.5,
                  ),
                ],
                pw.SizedBox(height: 6),
                pw.Divider(color: _pSageMuted, thickness: 0.8),
                pw.SizedBox(height: 4),
                // Grand total banner
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 7),
                  decoration: pw.BoxDecoration(
                    color: _pForest,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL / कुल',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.Text(
                        formatRupeePaise(totals.grandTotalPaise),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSignatureRow({required String bizName}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // Thank-you note
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Thank you for your business!',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _pForest,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'आपके सहयोग के लिए धन्यवाद!',
              style: pw.TextStyle(fontSize: 8.5, color: _pInk),
            ),
          ],
        ),
        // Signature block
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'For $bizName',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _pInk,
              ),
            ),
            pw.SizedBox(height: 36),
            pw.Container(width: 140, height: 0.8, color: _pSageMuted),
            pw.SizedBox(height: 3),
            pw.Text(
              'Authorized Signatory / अधिकृत हस्ताक्षर',
              style: pw.TextStyle(fontSize: 7.5, color: _pInk),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFooter({
    required pw.Context context,
    required String bizName,
    required String? quoteId,
    required String quoteNumber,
    required bool showFreeTierFooter,
  }) {
    final accentGrey = PdfColor.fromHex('#9FB8AD');
    return pw.Column(
      children: [
        pw.Divider(color: _pSageMuted, thickness: 0.6),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (quoteId != null && quoteId.isNotEmpty)
                  pw.Text(
                    'Ref: $quoteNumber  •  ID: ${shortId(quoteId)}',
                    style: pw.TextStyle(fontSize: 6.5, color: accentGrey),
                  ),
                if (showFreeTierFooter)
                  pw.Text(
                    'Created with Contractor Voice Quotation App (Free)',
                    style: pw.TextStyle(fontSize: 6.5, color: accentGrey),
                  ),
              ],
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 6.5, color: accentGrey),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper widgets
  // ─────────────────────────────────────────────────────────────────────────

  static pw.Widget _th(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.TableRow _buildTableRow({
    required int index,
    required QuoteLineItem item,
    required bool isEven,
  }) {
    final amountPaise = calculateAmount(item);
    final rateRupees = item.unitRatePaise ~/ 100;
    // Even rows white, odd rows very light surface stripe
    final rowBg = isEven ? PdfColors.white : PdfColor.fromHex('#F5F7F5');

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: rowBg),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: pw.Text(
            '$index',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8, color: _pInk),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: pw.Text(
            item.description,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _pInk,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: pw.Text(
            '${item.quantity}',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 8.5, color: _pInk),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: pw.Text(
            item.unit,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8.5, color: _pInk),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: pw.Text(
            formatRupee(rateRupees),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 8.5, color: _pInk),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: pw.Text(
            formatRupeePaise(amountPaise),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _pForest,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _metaRow(
    String label,
    String value, {
    PdfColor? valueColor,
    bool valueBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('$label:', style: pw.TextStyle(fontSize: 7.5, color: _pInk)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight:
                  valueBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor ?? _pInk,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow({
    required String label,
    required String value,
    double labelFontSize = 9,
    double valueFontSize = 9,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: labelFontSize, color: _pInk),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: valueFontSize,
            fontWeight: pw.FontWeight.bold,
            color: _pInk,
          ),
        ),
      ],
    );
  }

  static pw.Widget _termBullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7.5, color: _pInk),
      ),
    );
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Returns up to 2 capital initials from a business name.
  /// e.g. 'Shree Ganesh Enterprises' → 'SG', 'OneWord' → 'O'.
  static String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'Q';
    if (words.length == 1) return words[0][0].toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

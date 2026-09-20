import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../catalog/catalog.dart';
import '../models/quote.dart';
import '../utils/rupee_format.dart';

/// Fonts container for PDF rendering.
class PdfFontSet {
  final pw.Font regular;
  final pw.Font bold;

  const PdfFontSet({required this.regular, required this.bold});
}

/// Day 8 — Quotation PDF generator service.
///
/// Builds a clean, branded single-page A4 quotation PDF suitable for Indian
/// contractors and clients. Supports bilingual English/Hindi text, business
/// branding, itemized billing, totals, terms, and signature space.
class PdfService {
  /// Loads fonts with a 3-tier fallback strategy:
  /// 1. Bundled local asset (fast, 100% offline)
  /// 2. Google Fonts online cache (high quality)
  /// 3. Built-in Helvetica (safe failover)
  static Future<PdfFontSet> loadFonts() async {
    // 1. Try local bundled asset
    try {
      final fontData =
          await rootBundle.load('assets/fonts/NotoSansDevanagari.ttf');
      final font = pw.Font.ttf(fontData);
      return PdfFontSet(regular: font, bold: font);
    } catch (_) {}

    // 2. Try Google Fonts
    try {
      final regular = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      return PdfFontSet(regular: regular, bold: bold);
    } catch (_) {}

    // 3. Fallback to standard Helvetica
    return PdfFontSet(
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );
  }

  /// Generates the complete A4 PDF document bytes for [quote].
  static Future<Uint8List> generateQuotationPdf({
    required Quote quote,
    PdfPageFormat format = PdfPageFormat.a4,
    Trade? trade,
    String contractorName = 'Shree Ganesh Enterprises / श्री गणेश एंटरप्राइजेज',
    String contractorPhone = '+91 98765 43210',
    String contractorAddress = 'Shop 4, Building Material Market, Pune / Mumbai',
    String quoteNumber = 'Q-2026-0042',
    DateTime? quoteDate,
    int validityDays = 15,
    String? notes,
    PdfFontSet? fontSet,
  }) async {
    final pdf = pw.Document();
    final fonts = fontSet ?? await loadFonts();
    final date = quoteDate ?? DateTime.now();
    final expiryDate = date.add(Duration(days: validityDays));
    final totals = calculateTotals(quote);

    final primaryColor = PdfColor.fromHex('#1E3A8A'); // Navy blue
    final secondaryColor = PdfColor.fromHex('#374151'); // Charcoal
    final lightBgColor = PdfColor.fromHex('#F8FAFC'); // Light slate
    final borderColor = PdfColor.fromHex('#E2E8F0'); // Light border

    final dateFormat = DateFormat('dd MMM yyyy');

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── 1. Top Header & Branding ──────────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Contractor Logo & Details
                  pw.Expanded(
                    flex: 6,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Logo Placeholder
                        pw.Container(
                          width: 48,
                          height: 48,
                          decoration: pw.BoxDecoration(
                            color: primaryColor,
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            'CQ',
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                contractorName,
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                trade == Trade.tiling
                                    ? 'Tiling Specialist & Flooring Works'
                                    : trade == Trade.painting
                                        ? 'Painting, Putty & Wall Finishes'
                                        : 'Civil Contractor & Interior Works',
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  color: secondaryColor,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Ph: $contractorPhone  •  $contractorAddress',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColor.fromHex('#6B7280'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 12),

                  // Right: Quotation Metadata Badge
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: lightBgColor,
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: borderColor),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'QUOTATION / कोटेशन',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Quote #: $quoteNumber',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Date: ${dateFormat.format(date)}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            'Valid: $validityDays Days (until ${dateFormat.format(expiryDate)})',
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: primaryColor,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 12),
              pw.Divider(color: primaryColor, thickness: 1.5),
              pw.SizedBox(height: 8),

              // ── 2. Customer & Site Info Box ───────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'QUOTED FOR / ग्राहक विवरण:',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: secondaryColor,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            quote.customer.name.trim().isEmpty
                                ? 'Valued Client'
                                : quote.customer.name.trim(),
                            style: pw.TextStyle(
                              fontSize: 10.5,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          if (quote.customer.phone.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 1),
                            pw.Text(
                              'Phone: ${quote.customer.phone.trim()}',
                              style: const pw.TextStyle(fontSize: 8.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'PROJECT / कार्य:',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          trade == Trade.tiling
                              ? 'Tiling & Flooring Work'
                              : trade == Trade.painting
                                  ? 'Painting & Surface Finish'
                                  : 'Labour & Materials Quote',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ── 3. Line Items Table ───────────────────────────────────────
              pw.Table(
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: borderColor, width: 0.5),
                  bottom: pw.BorderSide(color: primaryColor, width: 1),
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(24), // S.No
                  1: pw.FlexColumnWidth(5), // Description
                  2: pw.FixedColumnWidth(50), // Qty
                  3: pw.FixedColumnWidth(46), // Unit
                  4: pw.FixedColumnWidth(65), // Rate
                  5: pw.FixedColumnWidth(75), // Amount
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: primaryColor),
                    children: [
                      _th('#', align: pw.TextAlign.center),
                      _th('Item & Description / मद का विवरण'),
                      _th('Qty / मात्रा', align: pw.TextAlign.right),
                      _th('Unit', align: pw.TextAlign.center),
                      _th('Rate / दर', align: pw.TextAlign.right),
                      _th('Amount / कुल', align: pw.TextAlign.right),
                    ],
                  ),

                  // Data Rows
                  for (var i = 0; i < quote.lineItems.length; i++) ...[
                    _buildTableRow(
                      index: i + 1,
                      item: quote.lineItems[i],
                      isEven: i % 2 == 0,
                      lightBg: lightBgColor,
                    ),
                  ],
                ],
              ),

              pw.SizedBox(height: 12),

              // ── 4. Totals Summary & Notes ─────────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Notes & Terms
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (notes != null && notes.trim().isNotEmpty) ...[
                          pw.Text(
                            'Special Notes / विशेष विवरण:',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(6),
                            decoration: pw.BoxDecoration(
                              color: lightBgColor,
                              borderRadius: pw.BorderRadius.circular(4),
                              border: pw.Border.all(color: borderColor),
                            ),
                            child: pw.Text(
                              notes.trim(),
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                          pw.SizedBox(height: 8),
                        ],
                        pw.Text(
                          'Terms & Conditions / नियम व शर्तें:',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        _termBullet('1. Estimate valid for $validityDays days from date of issue.'),
                        _termBullet('2. 50% advance before commencement, balance as per work progress.'),
                        _termBullet('3. Water and electricity to be provided by client at site.'),
                        _termBullet('4. Rates are for standard execution as per industry norms.'),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 16),

                  // Right: Totals Calculation
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: lightBgColor,
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: borderColor),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // Subtotal
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'Subtotal / उप-योग:',
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                              pw.Text(
                                formatRupeePaise(totals.subtotalPaise),
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          // GST if applied
                          if (quote.gstPercent != null && quote.gstPercent! > 0) ...[
                            pw.SizedBox(height: 4),
                            pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  'GST (${quote.gstPercent}%):',
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                                pw.Text(
                                  formatRupeePaise(totals.gstPaise),
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                              ],
                            ),
                          ],

                          pw.SizedBox(height: 6),
                          pw.Divider(color: borderColor, thickness: 0.8),
                          pw.SizedBox(height: 4),

                          // Grand Total Banner
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: pw.BoxDecoration(
                              color: primaryColor,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  'GRAND TOTAL / कुल:',
                                  style: pw.TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white,
                                  ),
                                ),
                                pw.Text(
                                  formatRupeePaise(totals.grandTotalPaise),
                                  style: pw.TextStyle(
                                    fontSize: 11,
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
              ),

              pw.Spacer(),

              // ── 5. Footer & Signature Space ───────────────────────────────
              pw.Divider(color: borderColor, thickness: 0.8),
              pw.SizedBox(height: 8),

              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Left greeting
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Thank you for your business! / आपके सहयोग के लिए धन्यवाद!',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Generated via Contractor Voice Quotation App',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),

                  // Right Signature Box
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'For $contractorName',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 32),
                      pw.Container(
                        width: 140,
                        height: 0.8,
                        color: secondaryColor,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Authorized Signatory / अधिकृत हस्ताक्षर',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ── Helper table cell builders ─────────────────────────────────────────────

  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8.5,
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
    required PdfColor lightBg,
  }) {
    final amountPaise = calculateAmount(item);
    final rateRupees = item.unitRatePaise ~/ 100;
    final rowBg = isEven ? PdfColors.white : lightBg;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: rowBg),
      children: [
        // S.No
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: pw.Text(
            '$index',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),

        // Description
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(
            item.description,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),

        // Qty
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(
            '${item.quantity}',
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),

        // Unit
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: pw.Text(
            item.unit,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),

        // Rate
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(
            formatRupee(rateRupees),
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),

        // Amount
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(
            formatRupeePaise(amountPaise),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
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
        style: const pw.TextStyle(
          fontSize: 7.5,
          color: PdfColors.grey700,
        ),
      ),
    );
  }
}

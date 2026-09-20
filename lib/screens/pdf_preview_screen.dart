import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../catalog/catalog.dart';
import '../models/quote.dart';
import '../pdf/pdf_service.dart';

/// Day 8 — PDF Preview Screen.
///
/// Displays an interactive preview of the generated A4 quotation PDF,
/// supporting pinch-to-zoom, printing, and file sharing.
class PdfPreviewScreen extends StatelessWidget {
  final Quote quote;
  final Trade? trade;
  final int validityDays;
  final String? notes;

  const PdfPreviewScreen({
    super.key,
    required this.quote,
    this.trade,
    this.validityDays = 15,
    this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final tradeBadge = trade == null
        ? null
        : Chip(
            label: Text(
              trade == Trade.tiling ? '🪣 Tiling' : '🖌️ Painting',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            backgroundColor: cs.primary.withOpacity(0.15),
            side: BorderSide(color: cs.primary.withOpacity(0.4)),
            visualDensity: VisualDensity.compact,
          );

    final sanitizedName = quote.customer.name.trim().isEmpty
        ? 'Client'
        : quote.customer.name.trim().replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('PDF Preview / पूर्वावलोकन'),
            if (tradeBadge != null) ...[
              const SizedBox(width: 10),
              tradeBadge,
            ],
          ],
        ),
      ),
      body: PdfPreview(
        build: (format) => PdfService.generateQuotationPdf(
          quote: quote,
          format: format,
          trade: trade,
          validityDays: validityDays,
          notes: notes,
        ),
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: 'Quotation_$sanitizedName.pdf',
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
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../catalog/catalog.dart';
import '../models/quote.dart';
import '../pdf/pdf_service.dart';
import '../storage/quote_repository.dart';
import '../storage/saved_quote.dart';

/// Day 8 & 9 — PDF Preview Screen.
///
/// Displays an interactive preview of the generated A4 quotation PDF,
/// auto-saves the document to app-scoped storage, persists quote metadata
/// to QuoteRepository, and provides direct sharing via the native Android
/// Sharesheet (WhatsApp, Gmail, etc.).
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
  bool _hasSaved = false;

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final bytes = await PdfService.generateQuotationPdf(
      quote: widget.quote,
      format: format,
      trade: widget.trade,
      validityDays: widget.validityDays,
      notes: widget.notes,
    );

    _lastGeneratedBytes = bytes;

    // Auto-save to app storage & update local repository (Day 9)
    if (!_hasSaved) {
      _hasSaved = true;
      _saveQuoteAndPdf(bytes);
    }

    return bytes;
  }

  Future<void> _saveQuoteAndPdf(Uint8List bytes) async {
    final sanitizedCustomer = widget.quote.customer.name.trim().isEmpty
        ? 'Client'
        : widget.quote.customer.name.trim().replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    final fileName = 'Quotation_${sanitizedCustomer}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    try {
      final savedPath = await PdfService.savePdfToAppStorage(
        bytes: bytes,
        fileName: fileName,
      );

      final id = widget.savedQuoteId ?? 'quote_${DateTime.now().millisecondsSinceEpoch}';
      final saved = SavedQuote(
        id: id,
        quoteNumber: 'Q-${DateTime.now().year}-${id.length > 4 ? id.substring(id.length - 4) : id}',
        createdAt: DateTime.now(),
        trade: widget.trade,
        customerName: widget.quote.customer.name.trim().isEmpty ? 'Client' : widget.quote.customer.name.trim(),
        customerPhone: widget.quote.customer.phone.trim(),
        customerAddress: widget.quote.customer.address.trim(),
        validityDays: widget.validityDays,
        notes: widget.notes ?? '',
        originalTranscript: widget.quote.originalTranscript,
        lineItems: widget.quote.lineItems,
        gstPercent: widget.quote.gstPercent,
        pdfPath: savedPath,
      );

      await QuoteRepository.saveQuote(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('PDF & Quote saved to History / कोटेशन सहेजा गया'),
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
    if (_lastGeneratedBytes != null) {
      final sanitizedName = widget.quote.customer.name.trim().isEmpty
          ? 'Client'
          : widget.quote.customer.name.trim().replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      await Printing.sharePdf(
        bytes: _lastGeneratedBytes!,
        filename: 'Quotation_$sanitizedName.pdf',
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
            backgroundColor: cs.primary.withOpacity(0.15),
            side: BorderSide(color: cs.primary.withOpacity(0.4)),
            visualDensity: VisualDensity.compact,
          );

    final sanitizedName = widget.quote.customer.name.trim().isEmpty
        ? 'Client'
        : widget.quote.customer.name.trim().replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');

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
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share via WhatsApp / शेयर करें',
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: PdfPreview(
        build: _buildPdf,
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

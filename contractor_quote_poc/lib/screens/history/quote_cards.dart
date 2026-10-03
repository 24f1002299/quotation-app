import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../templates/template_data.dart';
import '../../storage/saved_quote.dart';
import '../../utils/rupee_format.dart';

/// One saved quote row: business badge + number + status menu, customer +
/// amount. Callbacks keep navigation and mutation in the history screen.
// ─────────────────────────────────────────────────────────────────────────────

class SavedQuoteCard extends StatelessWidget {
  final SavedQuote quote;
  final VoidCallback onTap;
  final VoidCallback onViewPdf;
  final VoidCallback onDelete;

  const SavedQuoteCard({
    super.key,
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

    // Generic business-type badge: icon + English label from the
    // business-type metadata, so all types render (no trade special-case).
    // Free-text businesses print their saved custom snapshot.
    final typeInfo = quote.businessType == null
        ? null
        : businessTypeInfo(quote.businessType!);
    final typeLabel = quoteBusinessLabel(
      quote.businessType,
      quote.businessTypeLabel,
      'en',
    );

    // Status chip color
    Color statusBg = Colors.grey.shade200;
    Color statusFg = Colors.grey.shade800;
    String statusDisplay = quote.status.toUpperCase();
    if (quote.status == 'ready') {
      statusBg = Colors.green.shade100;
      statusFg = Colors.green.shade900;
      statusDisplay = 'READY';
    } else if (quote.status == 'shared') {
      statusBg = Colors.blue.shade100;
      statusFg = Colors.blue.shade900;
      statusDisplay = 'SHARED';
    } else if (quote.status == 'draft' || quote.status == 'needsReview') {
      statusBg = Colors.orange.shade100;
      statusFg = Colors.orange.shade900;
      statusDisplay = 'DRAFT';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: BusinessType badge + Quote Number + Status Chip + Menu
              Row(
                children: [
                  if (typeInfo != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(typeInfo.icon, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            typeLabel,
                            style: tt.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (typeInfo != null) const SizedBox(width: 8),
                  Text(
                    quote.displayNumber,
                    style: tt.bodySmall?.copyWith(
                      color: const Color(0xFF757575),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusDisplay,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusFg,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    tooltip: 'Quote actions',
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
                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text('Delete / हटाएं', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Middle: Customer name & amount
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
                          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${quote.lineItems.length} items • ${dateFormat.format(quote.effectiveDate)}',
                          style: tt.bodySmall?.copyWith(color: const Color(0xFF757575)),
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
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryEmptyState extends StatelessWidget {
  final VoidCallback onNewQuote;
  final bool hasFilters;

  const HistoryEmptyState(
      {super.key, required this.onNewQuote, this.hasFilters = false});

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
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: cs.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No matching quotes / कोई मेल नहीं'
                  : 'Your quotations will appear here / आपके कोटेशन यहाँ दिखेंगे',
              style: tt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Try clearing your search query or filters.'
                  : 'Start a voice quote to generate your first professional quotation.',
              style: tt.bodyMedium?.copyWith(color: const Color(0xFF757575)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!hasFilters)
              ElevatedButton.icon(
                onPressed: onNewQuote,
                icon: const Icon(Icons.mic_none_rounded),
                label: const Text('Create a voice quote / नया कोटेशन'),
              ),
          ],
        ),
      ),
    );
  }
}

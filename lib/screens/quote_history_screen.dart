import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/rupee_format.dart';

/// Day 1 — static placeholder for Quote History.
/// Day 9 will replace the dummy list with persisted data.
class QuoteHistoryScreen extends StatelessWidget {
  const QuoteHistoryScreen({super.key});

  // Dummy saved quotes for Day 1 navigation / UI test.
  static const _dummyHistory = [
    _HistoryEntry('Sharma Ji – Tiling', '15 Sep 2026', 45450 + 7200),
    _HistoryEntry('Verma Ji – Painting', '10 Sep 2026', 21600 + 14400),
  ];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote History / पुराने कोटेशन'),
      ),
      body: SafeArea(
        child: _dummyHistory.isEmpty
            ? _EmptyState(tt: tt)
            : ListView.builder(
                padding: const EdgeInsets.all(kPagePadding),
                itemCount: _dummyHistory.length,
                itemBuilder: (ctx, i) =>
                    _HistoryCard(entry: _dummyHistory[i]),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Simple immutable history entry — replaced by model Day 9
// ─────────────────────────────────────────────────────────
class _HistoryEntry {
  final String title;
  final String date;
  final int total; // whole rupees

  const _HistoryEntry(this.title, this.date, this.total);
}

class _HistoryCard extends StatelessWidget {
  final _HistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.description_outlined,
                    color: cs.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: tt.titleMedium),
                    const SizedBox(height: 2),
                    Text(entry.date, style: tt.bodyMedium),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatRupee(entry.total), style: tt.titleMedium),
                  const SizedBox(height: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
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
  final TextTheme tt;
  const _EmptyState({required this.tt});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No quotes yet', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text('Your saved quotes will appear here.',
              style: tt.bodyMedium),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Greeting header ──────────────────────────
              Text('नमस्ते 👷', style: tt.displaySmall),
              const SizedBox(height: 4),
              Text(
                'Contractor Quote App',
                style: tt.bodyMedium,
              ),

              const SizedBox(height: 40),

              // ── Primary CTA ───────────────────────────────
              ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/new-quote'),
                icon: const Icon(Icons.mic_rounded, size: 24),
                label: const Text('New Quote / नया कोटेशन'),
              ),

              const SizedBox(height: 16),

              // ── History shortcut ──────────────────────────
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/history'),
                icon: const Icon(Icons.history_rounded, size: 24),
                label: const Text('Quote History / पुराने कोटेशन'),
              ),

              const Spacer(),

              // ── Footer hint ───────────────────────────────
              Center(
                child: Text(
                  'Tiling · Painting · More coming soon',
                  style: tt.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

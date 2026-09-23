import 'package:flutter/material.dart';

import '../models/contractor_profile.dart';
import '../storage/profile_repository.dart';
import '../theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ContractorProfile _profile = ContractorProfile.empty();
  bool _hasCompletedOnboarding = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await ProfileRepository.getProfile();
    final completed = await ProfileRepository.hasCompletedOnboarding();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _hasCompletedOnboarding = completed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    final greeting = _profile.name.isNotEmpty
        ? 'नमस्ते, ${_profile.name.split(' ').first} 👷'
        : 'नमस्ते 👷';

    final subheader = _profile.businessName.isNotEmpty
        ? _profile.businessName
        : 'Contractor Quote App';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // ── Header with Profile shortcut ─────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greeting, style: tt.displaySmall),
                        const SizedBox(height: 4),
                        Text(subheader, style: tt.bodyMedium),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/profile');
                      _loadProfile();
                    },
                    icon: const Icon(Icons.person_outline_rounded, size: 20),
                    label: const Text('Profile'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),

              // ── Onboarding Banner if not yet configured ────
              if (!_hasCompletedOnboarding) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sage.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sage),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: forest, size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Set your standard rates once to speed up future quotes!',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Navigator.pushNamed(context, '/onboarding');
                          _loadProfile();
                        },
                        child: const Text('Setup'),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

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

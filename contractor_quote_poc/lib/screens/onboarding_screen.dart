import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import '../l10n/app_strings.dart';
import '../storage/profile_repository.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';

/// Phase 6 — single-page progressive setup.
///
/// Only what the first quote needs: name + business name + trade.
/// Phone, GSTIN, logo, city and rates live in Profile — never front-loaded.
/// Rates setup is deferred: a "set your rates" nudge appears in Profile.
class OnboardingScreen extends StatefulWidget {
  final bool isEditMode;
  const OnboardingScreen({super.key, this.isEditMode = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  Trade _trade = Trade.tiling;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    final profile = await ProfileRepository.getProfile();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = profile.name;
      _businessCtrl.text = profile.businessName;
      _trade = profile.trade;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _businessCtrl.dispose();
    super.dispose();
  }

  Future<void> _getStarted() async {
    if (_nameCtrl.text.trim().isEmpty &&
        _businessCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.of(context, 'client_name')} *'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final existing = await ProfileRepository.getProfile();
    await ProfileRepository.saveProfile(
      existing.copyWith(
        name: _nameCtrl.text.trim(),
        businessName: _businessCtrl.text.trim(),
        trade: _trade,
      ),
    );
    await ProfileRepository.setOnboardingCompleted(true);
    if (!mounted) return;
    if (widget.isEditMode) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/shell', (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => AppStrings.of(context, k);
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kForest)),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kForest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.handyman_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t('get_started'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 24),
              Text(t('client_name'), style: _labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: t('client_name')),
              ),
              const SizedBox(height: 16),
              Text(t('business'), style: _labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _businessCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: t('business')),
              ),
              const SizedBox(height: 16),
              Text(
                // Trade heading — uses raw trade names (proper nouns).
                'Trade',
                style: _labelStyle,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _TradeOption(
                    label: t('tiling'),
                    icon: Icons.grid_4x4_rounded,
                    selected: _trade == Trade.tiling,
                    onTap: () =>
                        setState(() => _trade = Trade.tiling),
                  ),
                  const SizedBox(width: 12),
                  _TradeOption(
                    label: t('painting'),
                    icon: Icons.format_paint_rounded,
                    selected: _trade == Trade.painting,
                    onTap: () =>
                        setState(() => _trade = Trade.painting),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _saving ? null : _getStarted,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(t('get_started')),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '${t('rate_card')} · ${t('settings')}',
                  style: const TextStyle(fontSize: 13, color: kInkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const TextStyle _labelStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: kInk,
);

class _TradeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TradeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? kSage.withValues(alpha: 0.3)
                : kSurfaceCard,
            borderRadius:
                BorderRadius.circular(AppDimensions.cardRadius),
            border: Border.all(
              color: selected ? kForest : kSurfaceMuted,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? kForest : kInkMuted,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? kForest : kInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

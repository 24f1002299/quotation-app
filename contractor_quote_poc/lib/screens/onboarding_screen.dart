import 'package:flutter/material.dart';

import '../templates/template_data.dart';
import '../l10n/app_strings.dart';
import '../storage/profile_repository.dart';
import '../storage/service_item_repository.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../widgets/business_type_chips.dart';

/// Phase 6 — single-page progressive setup.
///
/// Only what the first quote needs: name + business name + businessType.
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
  BusinessType _businessType = BusinessType.tiling;
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
      _nameCtrl.text = profile.ownerName;
      _businessCtrl.text = profile.businessName;
      _businessType = profile.businessType;
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
        ownerName: _nameCtrl.text.trim(),
        businessName: _businessCtrl.text.trim(),
        businessType: _businessType,
      ),
    );
    await ProfileRepository.setOnboardingCompleted(true);
    // Seed the starter service list for the chosen work so the first quote is
    // usable without the user typing a catalog.
    await ServiceItemRepository.seedFromTemplate(_businessType);
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
              Text(t('business_type'), style: _labelStyle),
              const SizedBox(height: 2),
              Text(
                t('business_type_note'),
                style: const TextStyle(fontSize: 13, color: kInkMuted),
              ),
              const SizedBox(height: 8),
              BusinessTypeChips(
                selected: _businessType,
                onChanged: (type) => setState(() => _businessType = type),
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

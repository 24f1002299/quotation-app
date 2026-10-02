import 'package:flutter/material.dart';

import '../templates/template_data.dart';
import '../templates/template_loader.dart';
import '../l10n/app_strings.dart';
import '../storage/profile_repository.dart';
import '../storage/service_item_repository.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../widgets/business_type_chips.dart';

/// Onboarding: language (separate picker screen) → business details →
/// starter-template preview. Step 1 collects only what the first quote
/// needs; step 2 previews the common services for the chosen work with an
/// opt-out, so the first quote is usable without typing a service list.
/// Phone, GSTIN, logo, city and rates live in Profile — never front-loaded.
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
  int _step = 0;
  List<StarterService> _preview = [];
  bool _addTemplate = true;

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
    // Step 0 → step 1: preview the starter template for the chosen work.
    if (_step == 0 && !widget.isEditMode) {
      setState(() => _saving = true);
      try {
        final template = await TemplateLoader.load(_businessType);
        if (!mounted) return;
        setState(() {
          _preview = template.services;
          _step = 1;
          _saving = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _preview = [];
          _step = 1;
          _saving = false;
        });
      }
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
    // Seed the starter service list only when the user kept the opt-in:
    // the preview step lets them skip it and start from an empty list.
    if (_addTemplate) {
      await ServiceItemRepository.seedFromTemplate(_businessType);
    }
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
              if (_step == 1) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('use_template'),
                        style: _labelStyle,
                      ),
                    ),
                    Switch(
                      value: _addTemplate,
                      onChanged: (v) => setState(() => _addTemplate = v),
                      activeThumbColor: kForest,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_addTemplate)
                  Container(
                    decoration: BoxDecoration(
                      color: kSurfaceCard,
                      borderRadius: BorderRadius.circular(
                        AppDimensions.cardRadius,
                      ),
                      border: Border.all(color: kSurfaceMuted),
                    ),
                    child: Column(
                      children: [
                        for (final s in _preview)
                          ListTile(
                            dense: true,
                            title: Text(
                              s.name,
                              style: const TextStyle(fontSize: 14),
                            ),
                            trailing: Text(
                              s.defaultRatePaise > 0
                                  ? '₹${s.defaultRatePaise ~/ 100} / ${s.unit}'
                                  : s.unit,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kInkMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _step = 0),
                  child: Text(t('change_business_type')),
                ),
              ],
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
                    : Text(_step == 1 ? t('continue') : t('get_started')),
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

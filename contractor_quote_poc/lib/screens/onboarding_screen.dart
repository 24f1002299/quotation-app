import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import '../models/contractor_profile.dart';
import '../models/rate_memory_item.dart';
import '../storage/profile_repository.dart';
import '../storage/rate_memory_repository.dart';
import '../theme.dart';

/// Day 12 — Short 2-step onboarding flow for contractor profile & rate memory.
///
/// Follows design.md:
/// - Step 1: Business details (name, business name, phone, city, trade, optional GSTIN, logo, terms)
/// - Step 2: Rate memory setup seeded by catalog (no bulk spreadsheets)
class OnboardingScreen extends StatefulWidget {
  final bool isEditMode;
  const OnboardingScreen({super.key, this.isEditMode = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 1; // 1: Business Details, 2: Standard Rates
  bool _isLoading = true;

  // Controllers for Step 1
  final _nameCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  Trade _selectedTrade = Trade.tiling;
  String? _logoPath;
  String? _logoSignedUrl;

  // Controllers for Step 2
  final Map<String, TextEditingController> _rateControllers = {};
  List<RateMemoryItem> _currentRates = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final profile = await ProfileRepository.getProfile();
    final rates = await RateMemoryRepository.getAllRates();

    if (!mounted) return;

    setState(() {
      _nameCtrl.text = profile.name;
      _businessNameCtrl.text = profile.businessName;
      _phoneCtrl.text = profile.phone;
      _cityCtrl.text = profile.city;
      _gstinCtrl.text = profile.gstin ?? '';
      _termsCtrl.text = profile.quoteTerms;
      _selectedTrade = profile.trade;
      _logoPath = profile.logoPath;
      _logoSignedUrl = profile.logoSignedUrl;

      _currentRates = rates;
      for (final r in rates) {
        _rateControllers[r.catalogItemId] =
            TextEditingController(text: r.rateRupees > 0 ? '${r.rateRupees}' : '');
      }

      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _businessNameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _gstinCtrl.dispose();
    _termsCtrl.dispose();
    for (final ctrl in _rateControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _saveStep1AndContinue() async {
    if (_businessNameCtrl.text.trim().isEmpty && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name or business name / अपना नाम लिखें'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final existing = await ProfileRepository.getProfile();
    final updated = existing.copyWith(
      name: _nameCtrl.text.trim(),
      businessName: _businessNameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      trade: _selectedTrade,
      gstin: _gstinCtrl.text.trim().isNotEmpty ? _gstinCtrl.text.trim() : null,
      logoPath: _logoPath,
      logoSignedUrl: _logoSignedUrl,
      quoteTerms: _termsCtrl.text.trim().isNotEmpty
          ? _termsCtrl.text.trim()
          : existing.quoteTerms,
    );

    await ProfileRepository.saveProfile(updated);

    if (!mounted) return;
    setState(() => _currentStep = 2);
  }

  Future<void> _saveStep2AndFinish() async {
    // Save updated rates
    for (final rateItem in _currentRates) {
      final ctrl = _rateControllers[rateItem.catalogItemId];
      if (ctrl != null) {
        final rupees = int.tryParse(ctrl.text.trim()) ?? 0;
        final updatedRate = rateItem.copyWith(
          unitRatePaise: rupees * 100,
          updatedAt: DateTime.now(),
        );
        await RateMemoryRepository.saveRate(updatedRate);
      }
    }

    await ProfileRepository.setOnboardingCompleted(true);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile & Rates saved / प्रोफाइल और रेट सुरक्षित हो गए'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (widget.isEditMode) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  Future<void> _simulateLogoUpload() async {
    final res = await ProfileRepository.uploadLogo(
      bytes: [0x89, 0x50, 0x4E, 0x47], // Mock PNG magic header
      filename: 'contractor_logo_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    setState(() {
      _logoPath = res.logoPath;
      _logoSignedUrl = res.signedUrl;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logo uploaded securely / लोगो सुरक्षित अपलोड हुआ'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStep == 1 ? 'Step 1 of 2: Business' : 'Step 2 of 2: Rates'),
        leading: _currentStep == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _currentStep = 1),
              )
            : (widget.isEditMode ? null : const SizedBox.shrink()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kPagePadding),
          child: _currentStep == 1 ? _buildStep1(tt, cs) : _buildStep2(tt, cs),
        ),
      ),
    );
  }

  // ── Step 1: Business Details ──────────────────────────────────────────────

  Widget _buildStep1(TextTheme tt, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Business details / व्यापार जानकारी',
          style: tt.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Used to generate clean, branded quotation PDFs for your clients.',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: 24),

        // Contractor Name
        TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Your Name / आपका नाम',
            hintText: 'e.g. Ramesh Patil',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),

        // Business Name
        TextFormField(
          controller: _businessNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Business Name / दुकान या फर्म का नाम *',
            hintText: 'e.g. Patil Tiling Works',
            prefixIcon: Icon(Icons.storefront_rounded),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),

        // Phone
        TextFormField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(
            labelText: 'Phone / मोबाइल नंबर',
            hintText: 'e.g. +91 98765 43210',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),

        // City
        TextFormField(
          controller: _cityCtrl,
          decoration: const InputDecoration(
            labelText: 'City or Area / शहर या इलाका',
            hintText: 'e.g. Pune, Maharashtra',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),

        // Primary Trade
        Text('Primary Trade / मुख्य काम', style: tt.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TradeChoiceCard(
                icon: Icons.grid_4x4_rounded,
                label: 'Tiling / टाइल्स',
                selected: _selectedTrade == Trade.tiling,
                onTap: () => setState(() => _selectedTrade = Trade.tiling),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TradeChoiceCard(
                icon: Icons.format_paint_rounded,
                label: 'Painting / पेंटिंग',
                selected: _selectedTrade == Trade.painting,
                onTap: () => setState(() => _selectedTrade = Trade.painting),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Optional Section: Logo, GSTIN, Terms
        ExpansionTile(
          title: const Text('Logo, GSTIN & Terms (Optional)'),
          subtitle: const Text('Add brand details for professional PDFs'),
          leading: const Icon(Icons.tune_rounded),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
          children: [
            // Logo upload card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: surfaceMuted),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _logoPath != null ? sage.withValues(alpha: 0.3) : surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _logoPath != null ? Icons.check_circle_rounded : Icons.image_rounded,
                      color: _logoPath != null ? forest : ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _logoPath != null ? 'Logo attached' : 'Business Logo',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _logoPath != null ? 'User-scoped storage' : 'Max 5MB (PNG/JPG)',
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _simulateLogoUpload,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text(_logoPath != null ? 'Change' : 'Upload'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // GSTIN
            TextFormField(
              controller: _gstinCtrl,
              decoration: const InputDecoration(
                labelText: 'GSTIN (Optional)',
                hintText: 'e.g. 27AAAAA0000A1Z5',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),

            // Terms
            TextFormField(
              controller: _termsCtrl,
              decoration: const InputDecoration(
                labelText: 'Default Terms / कोटेशन शर्तें',
                hintText: 'e.g. 50% advance before starting work',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              maxLines: 2,
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Primary Action Button
        ElevatedButton(
          onPressed: _saveStep1AndContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
          ),
          child: const Text('Continue to Rates / आगे बढ़ें (Step 2)'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Step 2: Rate Memory Setup ─────────────────────────────────────────────

  Widget _buildStep2(TextTheme tt, ColorScheme cs) {
    final tradeRates =
        _currentRates.where((r) => r.trade == _selectedTrade).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Standard Rates / अपने काम के रेट',
          style: tt.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Set your standard rates once. In future quotes, just speak the quantity and your rates are applied automatically!',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: 20),

        // Trade selector chip
        Row(
          children: [
            Text('Viewing rates for:', style: tt.titleSmall),
            const SizedBox(width: 8),
            ActionChip(
              avatar: Icon(
                _selectedTrade == Trade.tiling
                    ? Icons.grid_4x4_rounded
                    : Icons.format_paint_rounded,
                size: 16,
              ),
              label: Text(_selectedTrade == Trade.tiling ? 'Tiling' : 'Painting'),
              onPressed: () {
                setState(() {
                  _selectedTrade = _selectedTrade == Trade.tiling
                      ? Trade.painting
                      : Trade.tiling;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Editable list seeded from catalog
        ...tradeRates.map((rateItem) {
          final ctrl = _rateControllers[rateItem.catalogItemId] ??
              TextEditingController(
                text: rateItem.rateRupees > 0 ? '${rateItem.rateRupees}' : '',
              );
          _rateControllers[rateItem.catalogItemId] = ctrl;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: surfaceMuted.withValues(alpha: 0.6)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rateItem.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Unit: per ${rateItem.unit}',
                          style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        prefixStyle: const TextStyle(fontWeight: FontWeight.bold),
                        hintText: '0',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 24),

        // Primary: Save & Finish
        ElevatedButton(
          onPressed: _saveStep2AndFinish,
          style: ElevatedButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
          ),
          child: const Text('Save & Finish / सुरक्षित करें'),
        ),
        const SizedBox(height: 12),

        // Secondary: Set later
        TextButton(
          onPressed: () async {
            await ProfileRepository.setOnboardingCompleted(true);
            if (!mounted) return;
            if (widget.isEditMode) {
              Navigator.pop(context);
            } else {
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            }
          },
          child: const Text('Set later / बाद में तय करें'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TradeChoiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TradeChoiceCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? sage.withValues(alpha: 0.3) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? forest : surfaceMuted,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? forest : ink, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? forest : ink,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

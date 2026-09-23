import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import '../models/contractor_profile.dart';
import '../models/rate_memory_item.dart';
import '../storage/profile_repository.dart';
import '../storage/rate_memory_repository.dart';
import '../theme.dart';

/// Day 12 — Profile & Rate Memory management screen.
///
/// Reachable from the Home screen top bar.
/// Allows contractors to update their business branding and saved item rates anytime.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Profile controllers
  final _nameCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  Trade _selectedTrade = Trade.tiling;
  String? _logoPath;
  String? _logoSignedUrl;

  // Rate controllers
  final Map<String, TextEditingController> _rateControllers = {};
  List<RateMemoryItem> _rates = [];
  Trade _rateViewTrade = Trade.tiling;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
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
      _rateViewTrade = profile.trade;
      _logoPath = profile.logoPath;
      _logoSignedUrl = profile.logoSignedUrl;

      _rates = rates;
      for (final r in rates) {
        _rateControllers[r.catalogItemId] =
            TextEditingController(text: r.rateRupees > 0 ? '${r.rateRupees}' : '');
      }

      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  Future<void> _saveProfile() async {
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated / प्रोफाइल सुरक्षित हो गया'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveRates() async {
    for (final rateItem in _rates) {
      final ctrl = _rateControllers[rateItem.catalogItemId];
      if (ctrl != null) {
        final rupees = int.tryParse(ctrl.text.trim()) ?? 0;
        final updated = rateItem.copyWith(
          unitRatePaise: rupees * 100,
          updatedAt: DateTime.now(),
        );
        await RateMemoryRepository.saveRate(updated);
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rates updated / रेट सुरक्षित हो गए'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _uploadLogo() async {
    final res = await ProfileRepository.uploadLogo(
      bytes: [0x89, 0x50, 0x4E, 0x47],
      filename: 'contractor_logo_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    setState(() {
      _logoPath = res.logoPath;
      _logoSignedUrl = res.signedUrl;
    });
    await _saveProfile();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Rates / प्रोफाइल'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: forest,
          unselectedLabelColor: ink.withValues(alpha: 0.6),
          indicatorColor: forest,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.business_rounded), text: 'Profile'),
            Tab(icon: Icon(Icons.price_change_rounded), text: 'Rate Card'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProfileTab(tt),
          _buildRatesTab(tt),
        ],
      ),
    );
  }

  Widget _buildProfileTab(TextTheme tt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kPagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: surfaceMuted),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _logoPath != null ? sage.withValues(alpha: 0.4) : surfaceMuted,
                  child: Icon(
                    _logoPath != null ? Icons.verified_rounded : Icons.camera_alt_outlined,
                    color: _logoPath != null ? forest : ink,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _businessNameCtrl.text.isNotEmpty
                            ? _businessNameCtrl.text
                            : 'Your Business Logo',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        _logoPath != null ? 'Logo attached' : 'No logo uploaded',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _uploadLogo,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(_logoPath != null ? 'Change' : 'Upload'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Name
          TextFormField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Contractor Name / नाम',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),

          // Business Name
          TextFormField(
            controller: _businessNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Business Name / दुकान या फर्म का नाम',
              prefixIcon: Icon(Icons.storefront_rounded),
            ),
          ),
          const SizedBox(height: 16),

          // Phone
          TextFormField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Phone / मोबाइल नंबर',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),

          // City
          TextFormField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City or Site / शहर',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // GSTIN
          TextFormField(
            controller: _gstinCtrl,
            decoration: const InputDecoration(
              labelText: 'GSTIN (Optional)',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // Default Terms
          TextFormField(
            controller: _termsCtrl,
            decoration: const InputDecoration(
              labelText: 'Default Terms / कोटेशन शर्तें',
              prefixIcon: Icon(Icons.description_outlined),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: forest,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Save Profile Changes / सुरक्षित करें'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRatesTab(TextTheme tt) {
    final tradeRates = _rates.where((r) => r.trade == _rateViewTrade).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(kPagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Trade: ', style: tt.titleSmall),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Tiling / टाइल्स'),
                selected: _rateViewTrade == Trade.tiling,
                onSelected: (val) {
                  if (val) setState(() => _rateViewTrade = Trade.tiling);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Painting / पेंटिंग'),
                selected: _rateViewTrade == Trade.painting,
                onSelected: (val) {
                  if (val) setState(() => _rateViewTrade = Trade.painting);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

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
                            style: TextStyle(
                              fontSize: 13,
                              color: ink.withValues(alpha: 0.7),
                            ),
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

          ElevatedButton(
            onPressed: _saveRates,
            style: ElevatedButton.styleFrom(
              backgroundColor: forest,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Save Rates / रेट सुरक्षित करें'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

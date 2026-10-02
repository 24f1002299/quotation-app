import 'package:flutter/material.dart';

import '../templates/template_data.dart';
import '../l10n/app_strings.dart';
import '../storage/profile_repository.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../widgets/business_type_chips.dart';

/// Business details edit sub-page, opened from Settings rows.
/// Edits name, business, contact, GSTIN, terms and business type on the
/// saved [BusinessProfile]; the service list itself lives in My services.
class BusinessEditPage extends StatefulWidget {
  const BusinessEditPage({super.key});

  @override
  State<BusinessEditPage> createState() => _BusinessEditPageState();
}

class _BusinessEditPageState extends State<BusinessEditPage> {
  final _nameCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  BusinessType _businessType = BusinessType.tiling;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    final p = await ProfileRepository.getProfile();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = p.ownerName;
      _businessCtrl.text = p.businessName;
      _phoneCtrl.text = p.phone;
      _cityCtrl.text = p.city;
      _gstinCtrl.text = p.gstin ?? '';
      _termsCtrl.text = p.quoteTerms;
      _businessType = p.businessType;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _businessCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _gstinCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final existing = await ProfileRepository.getProfile();
    await ProfileRepository.saveProfile(
      existing.copyWith(
        ownerName: _nameCtrl.text.trim(),
        businessName: _businessCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        businessType: _businessType,
        gstin:
            _gstinCtrl.text.trim().isNotEmpty ? _gstinCtrl.text.trim() : null,
        quoteTerms: _termsCtrl.text.trim().isNotEmpty
            ? _termsCtrl.text.trim()
            : existing.quoteTerms,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved / सुरक्षित हो गया'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
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
      appBar: AppBar(title: Text(t('business'))),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.page),
        children: [
          _field(t('client_name'), _nameCtrl),
          _field(t('business'), _businessCtrl),
          _field(t('phone'), _phoneCtrl,
              keyboard: TextInputType.phone),
          _field(t('site'), _cityCtrl),
          _field('GSTIN', _gstinCtrl),
          _field('Terms', _termsCtrl, maxLines: 3),
          const SizedBox(height: 8),
          Text(
            t('business_type'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kInk,
            ),
          ),
          const SizedBox(height: 8),
          BusinessTypeChips(
            selected: _businessType,
            onChanged: (type) => setState(() => _businessType = type),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _save, child: Text(t('done'))),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {int maxLines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kInk,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboard,
            decoration: InputDecoration(hintText: label),
          ),
        ],
      ),
    );
  }
}

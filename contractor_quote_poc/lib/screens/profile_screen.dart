import 'package:flutter/material.dart';

import '../templates/template_data.dart';
import '../l10n/app_strings.dart';
import '../models/business_profile.dart';
import '../models/service_item.dart';
import '../storage/app_preferences.dart';
import '../storage/auth_repository.dart';
import '../storage/data_deletion_service.dart';
import '../storage/diagnostic_consent.dart';
import '../storage/pdf_backup_settings.dart';
import '../storage/profile_repository.dart';
import '../storage/service_item_repository.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../widgets/business_type_chips.dart';
import 'my_services_screen.dart';

/// Phase 6 — clean grouped Settings (was tab-based Profile + Rate Card).
///
/// Groups: Business · My services · Preferences (incl. Language) · Account.
/// - Business rows open one edit page (name, business, type, contact, terms).
/// - My services is a sub-page for the user's own service list.
/// - Language switches instantly via [appLanguage], no restart.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  BusinessProfile _profile = BusinessProfile.empty();
  List<ServiceItem> _services = [];
  bool _loading = true;
  bool _signedIn = false;
  String _language = 'hi';
  bool _backupOptIn = false;
  bool _diagnosticOptIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await ProfileRepository.getProfile();
    final services =
        await ServiceItemRepository.getActiveForBusinessType(profile.businessType);
    final signedIn = await AuthRepository.isSignedIn();
    final lang = await AppPreferences.getLanguage();
    final backup = await PdfBackupSettings.isOptedIn();
    final diag = await DiagnosticConsent.isOptedIn();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _services = services;
      _signedIn = signedIn;
      _language = (lang == 'en' || lang == 'mr') ? lang : 'hi';
      _backupOptIn = backup;
      _diagnosticOptIn = diag;
      _loading = false;
    });
  }

  int get _ratedCount => _services.where((s) => s.ratePaise > 0).length;

  Future<void> _pickLanguage() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kSurfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final c in ['hi', 'en', 'mr'])
              ListTile(
                title: Text(
                  c == 'hi'
                      ? 'हिंदी'
                      : c == 'en'
                          ? 'English'
                          : 'मराठी',
                ),
                trailing: _language == c
                    ? const Icon(Icons.check_rounded, color: kForest)
                    : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (code == null || !mounted) return;
    await AppPreferences.setLanguage(code);
    appLanguage.value = code;
    setState(() => _language = code);
  }

  Future<void> _deleteMyData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete my data?'),
        content: const Text(
          'This removes all quotes, drafts and profile data on '
          'this phone. Cloud copies need per-quote delete while signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kError),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final summary = await DataDeletionService.deleteAllLocal();
    await PdfBackupSettings.setOptedIn(false);
    if (!mounted) return;
    setState(() {
      _backupOptIn = false;
      _profile = BusinessProfile.empty();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted $summary from this phone'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _openBusinessEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _BusinessEditPage()),
    );
    _load();
  }

  Future<void> _openServices() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyServicesScreen(businessType: _profile.businessType),
      ),
    );
    _load();
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
      appBar: AppBar(title: Text(t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.page),
        children: [
          _GroupLabel(t('business').toUpperCase()),
          _Group(
            children: [
              _Row(
                label: t('client_name'),
                value: _profile.ownerName.isEmpty ? '—' : _profile.ownerName,
                onTap: _openBusinessEdit,
              ),
              _Row(
                label: t('business'),
                value: _profile.businessName.isEmpty
                    ? '—'
                    : _profile.businessName,
                onTap: _openBusinessEdit,
              ),
              _Row(
                label: t('business_type'),
                value: businessTypeInfo(_profile.businessType).label(_language),
                onTap: _openBusinessEdit,
              ),
              _Row(
                label: t('phone'),
                value: _profile.phone.isEmpty ? '—' : _profile.phone,
                onTap: _openBusinessEdit,
              ),
              _Row(
                label: t('site'),
                value: _profile.city.isEmpty ? '—' : _profile.city,
                onTap: _openBusinessEdit,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GroupLabel(t('my_services').toUpperCase()),
          _Group(
            children: [
              _Row(
                label: t('my_services'),
                value: '${_services.length} · $_ratedCount ✓',
                onTap: _openServices,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GroupLabel(t('preferences').toUpperCase()),
          _Group(
            children: [
              _Row(
                label: t('language'),
                value: _language == 'hi'
                    ? 'हिंदी'
                    : _language == 'en'
                        ? 'English'
                        : 'मराठी',
                onTap: _pickLanguage,
              ),
              _SwitchRow(
                label: 'PDF backup',
                value: _backupOptIn,
                onChanged: (v) async {
                  await PdfBackupSettings.setOptedIn(v);
                  if (mounted) setState(() => _backupOptIn = v);
                },
              ),
              _SwitchRow(
                label: 'Diagnostics',
                value: _diagnosticOptIn,
                onChanged: (v) async {
                  await DiagnosticConsent.setOptedIn(v);
                  if (mounted) setState(() => _diagnosticOptIn = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GroupLabel(t('account').toUpperCase()),
          _Group(
            children: [
              _Row(
                label: _signedIn ? 'Sign out' : 'Sign in',
                value: '',
                onTap: () async {
                  if (_signedIn) {
                    await AuthRepository.signOut();
                  } else {
                    await Navigator.pushNamed(context, '/sign-in');
                  }
                  _load();
                },
              ),
              _Row(
                label: 'Privacy notice',
                value: '',
                onTap: () => Navigator.pushNamed(context, '/privacy'),
              ),
              _Row(
                label: 'Delete my data',
                value: '',
                destructive: true,
                onTap: _deleteMyData,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: kInkMuted,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceCard,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: kSurfaceMuted),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool destructive;
  const _Row({
    required this.label,
    required this.value,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: destructive ? kError : kInk,
                ),
              ),
            ),
            if (value.isNotEmpty)
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 14, color: kInkMuted),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: kInkMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: kForest),
        ],
      ),
    );
  }
}

/// Business details edit sub-page (fields moved out of the old tab).
class _BusinessEditPage extends StatefulWidget {
  const _BusinessEditPage();

  @override
  State<_BusinessEditPage> createState() => _BusinessEditPageState();
}

class _BusinessEditPageState extends State<_BusinessEditPage> {
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

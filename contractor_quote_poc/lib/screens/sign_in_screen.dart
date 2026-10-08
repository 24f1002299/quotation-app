import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../storage/auth_repository.dart';
import '../theme.dart';

/// Day 19 — Minimal phone sign-in (Supabase phone OTP).
///
/// Bilingual, one thumb, large targets. When Supabase is unconfigured
/// (local dev without --dart-define keys) shows a clearly-labelled dev
/// bypass instead of blocking the contractor's first quote.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (!AuthRepository.isValidIndianPhone(raw)) {
      if (!mounted) return;
      setState(() => _error = AppStrings.read(context, 'invalid_phone'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthRepository.sendOtp(AuthRepository.normalizeToE164(raw));
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppStrings.read(context, 'otp_send_failed');
      });
    }
  }

  Future<void> _verifyOtp() async {
    final phone = AuthRepository.normalizeToE164(_phoneCtrl.text.trim());
    final token = _otpCtrl.text.trim();
    if (token.length < 4) {
      setState(() => _error = AppStrings.read(context, 'enter_otp'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthRepository.verifyOtp(phone: phone, token: token);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.read(context, 'signed_in')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppStrings.read(context, 'wrong_otp');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context, 'sign_in'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.of(context, 'login_mobile'),
                  style: tt.titleLarge),
              const SizedBox(height: 6),
              Text(
                AppStrings.of(context, 'otp_info'),
                style: tt.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _phoneCtrl,
                enabled: !_otpSent,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context, 'mobile_number'),
                  hintText: 'e.g. 98765 43210',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  prefixText: '+91 ',
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s+]')),
                ],
              ),
              if (_otpSent) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otpCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context, 'otp_label'),
                    hintText: 'e.g. 123456',
                    prefixIcon: const Icon(Icons.sms_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : (_otpSent ? _verifyOtp : _sendOtp),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_otpSent
                        ? AppStrings.of(context, 'verify_otp')
                        : AppStrings.of(context, 'send_otp')),
              ),
              if (_otpSent) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _otpSent = false;
                            _otpCtrl.clear();
                          }),
                  child: Text(AppStrings.of(context, 'change_number')),
                ),
              ],
              // Dev bypass: only when Supabase keys are absent.
              if (!AuthRepository.isSupabaseConfigured) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Dev mode: Supabase keys not configured.',
                  style: tt.bodySmall,
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Continue without sign-in (dev)'),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

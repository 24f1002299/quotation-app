import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      setState(() => _error = 'Enter a valid 10-digit mobile number / 10 अंक का मोबाइल नंबर लिखें');
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
        _error = 'Could not send OTP. Check internet and retry. / OTP नहीं भेजा गया — पुनः प्रयास करें';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final phone = AuthRepository.normalizeToE164(_phoneCtrl.text.trim());
    final token = _otpCtrl.text.trim();
    if (token.length < 4) {
      setState(() => _error = 'Enter the OTP sent to your phone / फोन पर आया OTP लिखें');
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
        const SnackBar(
          content: Text('Signed in / साइन इन हो गया ✓'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Wrong or expired OTP. Try again. / गलत OTP — दोबारा कोशिश करें';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in / साइन इन')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Login with mobile number', style: tt.titleLarge),
              const SizedBox(height: 6),
              Text(
                'OTP आएगा — We send an SMS code. Your quotes stay on this phone even offline.',
                style: tt.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _phoneCtrl,
                enabled: !_otpSent,
                decoration: const InputDecoration(
                  labelText: 'Mobile number / मोबाइल नंबर *',
                  hintText: 'e.g. 98765 43210',
                  prefixIcon: Icon(Icons.phone_outlined),
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
                  decoration: const InputDecoration(
                    labelText: 'OTP / ओटीपी *',
                    hintText: 'e.g. 123456',
                    prefixIcon: Icon(Icons.sms_outlined),
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
                    : Text(_otpSent ? 'Verify OTP / सत्यापित करें' : 'Send OTP / OTP भेजें'),
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
                  child: const Text('Change number / नंबर बदलें'),
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

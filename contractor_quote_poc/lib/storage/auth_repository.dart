import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Day 19 — Minimal phone sign-in repository (Supabase phone OTP).
///
/// - Uses Supabase Auth phone OTP when configured; never ships secrets
///   (anon key only, enforced by `supabase_config.dart`).
/// - Degrades gracefully offline / unconfigured: [isSupabaseConfigured]
///   is false when no anon key was supplied via --dart-define, and the UI
///   offers a clearly-labelled dev bypass instead of blocking first quote.
/// - Caches the verified phone locally so Home/Profile can greet the user
///   even before the next sync.
class AuthRepository {
  static const _phoneKey = 'auth_verified_phone_v1';

  /// False in local dev without --dart-define keys: sign-in UI must not
  /// block the contractor's first quote in that case.
  static bool get isSupabaseConfigured => supabaseAnonKey.trim().isNotEmpty;

  static Future<void> sendOtp(String phone) async {
    await Supabase.instance.client.auth.signInWithOtp(phone: phone);
  }

  static Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) async {
    final res = await Supabase.instance.client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
    final verified = res.user?.phone ?? phone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneKey, verified);
    return res;
  }

  static Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_phoneKey);
  }

  /// Cached verified phone (empty when never signed in on this phone).
  static Future<String> cachedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey) ?? '';
  }

  static Future<bool> isSignedIn() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) return true;
    } catch (_) {
      // Supabase uninitialized in tests / dev — fall through to cache.
    }
    return (await cachedPhone()).trim().isNotEmpty;
  }

  /// Pure helper for input validation; unit-testable.
  /// Accepts 10-digit Indian mobile numbers with optional +91 / spaces.
  static bool isValidIndianPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final normalized =
        digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
    return RegExp(r'^[6-9]\d{9}$').hasMatch(normalized);
  }

  /// Normalizes to +91XXXXXXXXXX for Supabase OTP.
  static String normalizeToE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final ten =
        digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
    return '+91$ten';
  }
}

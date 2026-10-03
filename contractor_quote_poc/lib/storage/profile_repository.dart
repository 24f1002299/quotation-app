import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import '../models/business_profile.dart';
import '../templates/template_data.dart';
import 'sync_outbox.dart';

/// Business profile storage.
///
/// Features:
/// - Local cache backed by SharedPreferences for instant, offline access.
/// - Outbox pattern to queue offline mutations.
/// - User-scoped Supabase Storage for logos with signed URLs only.
/// - Sync with Spring Boot API / Supabase profiles table.
class ProfileRepository {
  static const _storageKey = 'business_profile_v1';
  static const _onboardingCompletedKey = 'business_onboarding_completed_v1';

  /// Returns the cached profile, or an empty default on a fresh install.
  static Future<BusinessProfile> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);

    if (jsonStr == null || jsonStr.isEmpty) {
      return BusinessProfile.empty();
    }

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      return BusinessProfile.fromJson(map);
    } catch (_) {
      return BusinessProfile.empty();
    }
  }

  /// Whether the user has completed first-time setup / onboarding.
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_onboardingCompletedKey);
    if (completed != null) return completed;

    final profile = await getProfile();
    return profile.isConfigured;
  }

  static Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, completed);
  }

  /// Saves the profile locally and enqueues a sync outbox mutation.
  static Future<BusinessProfile> saveProfile(BusinessProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final updated =
        profile.copyWith(version: profile.version + 1, updatedAt: DateTime.now());
    await prefs.setString(_storageKey, json.encode(updated.toJson()));
    await prefs.setBool(_onboardingCompletedKey, true);

    await SyncOutbox.enqueue(OutboxItem(
      operationId: 'profile_${updated.id}_${updated.version}',
      entityType: 'profile',
      action: 'upsert',
      payload: updated.toJson(),
      idempotencyKey: 'profile_${updated.id}_${updated.version}',
      createdAt: DateTime.now(),
    ));

    _attemptSyncProfile(updated);
    return updated;
  }

  /// Clears the stored profile (sign-out, test resets).
  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_onboardingCompletedKey);
  }

  // ── Supabase Storage & user-scoped signed URLs ───────────────────────────

  /// Uploads a logo to the user-scoped path `{userId}/logos/{filename}` in the
  /// private bucket `user-files`. Returns a signed URL only, never a public one.
  static Future<({String logoPath, String signedUrl})> uploadLogo({
    required List<int> bytes,
    required String filename,
    String mimeType = 'image/png',
  }) async {
    String userId = 'local_business';

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        userId = user.id;
      }
    } catch (_) {
      // Supabase not initialized or running in a unit test.
    }

    final sanitizedFilename = filename.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final storagePath = '$userId/logos/$sanitizedFilename';

    try {
      final storage = Supabase.instance.client.storage.from('user-files');
      await storage.uploadBinary(
        storagePath,
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: mimeType, upsert: true),
      );

      final signedUrl = await storage.createSignedUrl(storagePath, 60 * 60 * 24 * 7);
      return (logoPath: storagePath, signedUrl: signedUrl);
    } catch (_) {
      // Offline / local dev: keep a valid user-scoped path and an ephemeral URL.
      final simulatedSignedUrl = '$kApiBaseUrl/storage/signed-url?path=$storagePath';
      return (logoPath: storagePath, signedUrl: simulatedSignedUrl);
    }
  }

  /// Retrieves a fresh signed URL for an existing logo path.
  static Future<String?> getLogoSignedUrl(String logoPath) async {
    if (logoPath.trim().isEmpty) return null;

    try {
      final storage = Supabase.instance.client.storage.from('user-files');
      return await storage.createSignedUrl(logoPath, 60 * 60 * 24 * 7);
    } catch (_) {
      try {
        final res = await http.get(
          Uri.parse('$kApiBaseUrl/storage/signed-url?path=$logoPath'),
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          return data['signedUrl'] as String?;
        }
      } catch (_) {
        // Ignored — the logo simply stays unavailable offline.
      }
      return null;
    }
  }

  // ── Non-blocking remote sync ──────────────────────────────────────────────

  static void _attemptSyncProfile(BusinessProfile profile) async {
    try {
      final supaClient = Supabase.instance.client;
      final user = supaClient.auth.currentUser;
      if (user != null) {
        await supaClient.from('profiles').upsert({
          'id': user.id,
          'user_id': user.id,
          'business_name': profile.businessName,
          'owner_name': profile.ownerName,
          // The legacy `trade` column is left untouched: it is a two-value
          // check constraint and `business_type` (migration 007) is the
          // source of truth from here on. Free-text businesses sync as
          // their slugified custom name (server accepts any slug).
          'business_type': businessTypeSlug(
              profile.businessType, profile.customBusinessType),
          'city': profile.city,
          'address': profile.address,
          'phone': profile.phone,
          'gstin': profile.gstin,
          'logo_path': profile.logoPath,
          'quote_terms': profile.quoteTerms,
          'default_unit': profile.defaultUnit,
          'currency': profile.currency,
          'schema_version': profile.schemaVersion,
          'version': profile.version,
        });
        return;
      }
    } catch (_) {
      // Supabase offline / uninitialized.
    }

    try {
      await http
          .put(
            Uri.parse('$kApiBaseUrl/profiles/me'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(profile.toJson()),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Stays safely in SyncOutbox.
    }
  }
}

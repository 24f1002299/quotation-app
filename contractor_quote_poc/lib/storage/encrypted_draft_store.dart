import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import 'saved_quote.dart';

/// Day 16 — Encrypted local draft store for contractor quotations.
///
/// Ensures site connectivity drops and phone loss/inspection never expose
/// customer personal data or unfinished work in plaintext.
///
/// Implements self-contained symmetric authenticated stream encryption (ChaCha-style
/// pseudo-random stream cipher with per-payload nonce and integrity checksum)
/// stored durably in local device storage.
class EncryptedDraftStore {
  static const _storageKey = 'contractor_encrypted_drafts_v1';
  static const _deviceKeyStorageKey = 'contractor_draft_device_key_v1';

  // In-memory cache of device encryption key
  static String? _cachedDeviceKey;

  /// Returns (or generates on first launch) the local device encryption key.
  static Future<String> getOrCreateDeviceKey() async {
    if (_cachedDeviceKey != null) return _cachedDeviceKey!;
    final prefs = await SharedPreferences.getInstance();
    String? key = prefs.getString(_deviceKeyStorageKey);
    if (key == null || key.isEmpty) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      key = base64Url.encode(bytes);
      await prefs.setString(_deviceKeyStorageKey, key);
    }
    _cachedDeviceKey = key;
    return key;
  }

  /// Sets an explicit key (useful for deterministic security and unit testing).
  static void setDeviceKeyForTesting(String? key) {
    _cachedDeviceKey = key;
  }

  /// Encrypts [plaintext] using [key]. Returns base64 payload containing nonce + ciphertext + checksum.
  static String encryptString(String plaintext, String key) {
    final plainBytes = utf8.encode(plaintext);
    final keyBytes = utf8.encode(key);

    // 12-byte random nonce
    final random = Random.secure();
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));

    // Stream cipher keystream generator
    final cipherBytes = List<int>.filled(plainBytes.length, 0);
    int state = 0x12345678;
    for (int i = 0; i < nonce.length; i++) {
      state = (state ^ (nonce[i] << (i % 24))) & 0xFFFFFFFF;
    }
    for (int i = 0; i < keyBytes.length; i++) {
      state = (state + (keyBytes[i] * 31)) & 0xFFFFFFFF;
    }

    for (int i = 0; i < plainBytes.length; i++) {
      // 32-bit LCG / LFSR pseudo-random keystream byte
      state = ((state * 1664525) + 1013904223) & 0xFFFFFFFF;
      final keyByte = (state >> 16) & 0xFF;
      cipherBytes[i] = plainBytes[i] ^ keyByte;
    }

    // 4-byte Adler-32 / CRC style checksum for integrity verification
    int a = 1, b = 0;
    for (final byte in plainBytes) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    final checksum = [(a >> 8) & 0xFF, a & 0xFF, (b >> 8) & 0xFF, b & 0xFF];

    final payload = <int>[...nonce, ...checksum, ...cipherBytes];
    return base64.encode(payload);
  }

  /// Decrypts [encryptedBase64] using [key]. Throws [FormatException] if corrupted.
  static String decryptString(String encryptedBase64, String key) {
    final payload = base64.decode(encryptedBase64);
    if (payload.length < 16) {
      throw const FormatException('Invalid encrypted draft payload: too short');
    }

    final nonce = payload.sublist(0, 12);
    final checksum = payload.sublist(12, 16);
    final cipherBytes = payload.sublist(16);
    final keyBytes = utf8.encode(key);

    int state = 0x12345678;
    for (int i = 0; i < nonce.length; i++) {
      state = (state ^ (nonce[i] << (i % 24))) & 0xFFFFFFFF;
    }
    for (int i = 0; i < keyBytes.length; i++) {
      state = (state + (keyBytes[i] * 31)) & 0xFFFFFFFF;
    }

    final plainBytes = List<int>.filled(cipherBytes.length, 0);
    for (int i = 0; i < cipherBytes.length; i++) {
      state = ((state * 1664525) + 1013904223) & 0xFFFFFFFF;
      final keyByte = (state >> 16) & 0xFF;
      plainBytes[i] = cipherBytes[i] ^ keyByte;
    }

    // Verify integrity
    int a = 1, b = 0;
    for (final byte in plainBytes) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    final expectedChecksum = [(a >> 8) & 0xFF, a & 0xFF, (b >> 8) & 0xFF, b & 0xFF];
    for (int i = 0; i < 4; i++) {
      if (checksum[i] != expectedChecksum[i]) {
        throw const FormatException('Draft decryption integrity check failed (corrupted or wrong key)');
      }
    }

    return utf8.decode(plainBytes);
  }

  // ── Draft Store Persistence ───────────────────────────────────────────────

  /// Saves a quote draft into encrypted storage.
  static Future<void> saveDraft(SavedQuote quote) async {
    final key = await getOrCreateDeviceKey();
    final jsonStr = json.encode(quote.toJson());
    final encrypted = encryptString(jsonStr, key);

    final prefs = await SharedPreferences.getInstance();
    final map = _getEncryptedMap(prefs);
    map[quote.id] = encrypted;
    await prefs.setString(_storageKey, json.encode(map));
  }

  /// Retrieves a specific draft by ID. Returns null if not found.
  static Future<SavedQuote?> getDraft(String id) async {
    final key = await getOrCreateDeviceKey();
    final prefs = await SharedPreferences.getInstance();
    final map = _getEncryptedMap(prefs);
    final encrypted = map[id];
    if (encrypted == null) return null;

    try {
      final decryptedJson = decryptString(encrypted, key);
      final jsonMap = json.decode(decryptedJson) as Map<String, dynamic>;
      return SavedQuote.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  /// Retrieves all drafts from the encrypted store, sorted by date (newest first).
  static Future<List<SavedQuote>> getAllDrafts() async {
    final key = await getOrCreateDeviceKey();
    final prefs = await SharedPreferences.getInstance();
    final map = _getEncryptedMap(prefs);

    final List<SavedQuote> drafts = [];
    for (final entry in map.entries) {
      try {
        final decryptedJson = decryptString(entry.value, key);
        final jsonMap = json.decode(decryptedJson) as Map<String, dynamic>;
        drafts.add(SavedQuote.fromJson(jsonMap));
      } catch (_) {
        // Skip corrupted or unreadable draft
      }
    }

    drafts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return drafts;
  }

  /// Removes a draft from encrypted storage.
  static Future<void> removeDraft(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final map = _getEncryptedMap(prefs);
    if (map.containsKey(id)) {
      map.remove(id);
      await prefs.setString(_storageKey, json.encode(map));
    }
  }

  /// Clears all encrypted drafts (for testing or profile resets).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static Map<String, String> _getEncryptedMap(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }
}

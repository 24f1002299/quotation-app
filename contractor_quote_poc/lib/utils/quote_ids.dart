import 'dart:math';

/// Day 15 — Local quote identity helpers (offline-safe, no backend needed).
///
/// - [newQuoteId] is the immutable UUID v4 generated on the phone. It is the
///   idempotency anchor: it never changes, even across edits, retries, or
///   reinstall restores from backup. Every write sends this as the key.
/// - [newDisplayNumber] is a human-friendly label for the screen/PDF only.
///   It is NOT gap-free sequential numbering — the backend may later assign
///   [SavedQuote.serverDisplayNumber], which then takes precedence in UI.
/// - [shortId] shows the first 8 chars of the immutable ID where useful
///   (PDF footer, history subtitle) without bloating data entry.
String newQuoteId() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  // UUID v4 variant bits.
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Local human-readable number, e.g. `Q-2026-A3F9`. Random suffix on purpose:
/// never promise gap-free sequential numbering from the phone.
String newDisplayNumber([DateTime? date]) {
  final d = date ?? DateTime.now();
  final rnd = Random.secure();
  final suffix =
      List<int>.generate(4, (_) => rnd.nextInt(36)).map((n) => n < 10
          ? String.fromCharCode(48 + n)
          : String.fromCharCode(55 + n)).join();
  return 'Q-${d.year}-$suffix';
}

/// First 8 characters of an immutable ID for compact display.
String shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

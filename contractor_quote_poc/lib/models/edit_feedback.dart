// Day 21 — Privacy-minimal correction feedback model.
//
// What is stored (and only this):
//   businessType, serviceItemId, modelResult, finalValue, changedField, quoteIdHash.
// What is NEVER stored here: raw audio, full transcripts, customer PII,
// microphone data. See docs/feedback-privacy.md for the deletion policy.
library;

import 'dart:convert';

/// Allowed field types a user can correct. Mirrors the
/// `edit_feedback.changed_field` CHECK constraint in Supabase.
const Set<String> kFeedbackChangedFields = {
  'description',
  'quantity',
  'unit',
  'rate',
};

/// Legacy two-trade allow-list. No longer used as a gate: correction feedback
/// is recorded for any business slug. Kept for backward compatibility.
const Set<String> kFeedbackTrades = {'tiling', 'painting'};

class EditFeedback {
  final String id;
  final String quoteIdHash; // SHA-256 hex of the quote UUID — never raw ID.
  final String businessType; // any business slug, e.g. 'tiling' | 'pest_control'
  final String? serviceItemId; // catalog id the model picked (if any)
  final String? modelResult; // what the model/extraction produced
  final String? finalValue; // what the user ended with
  final String changedField; // description | quantity | unit | rate
  final DateTime createdAt;

  const EditFeedback({
    required this.id,
    required this.quoteIdHash,
    required this.businessType,
    this.serviceItemId,
    this.modelResult,
    this.finalValue,
    required this.changedField,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'quote_id_hash': quoteIdHash,
        'business_type': businessType,
        'service_item_id': serviceItemId,
        'model_result': modelResult,
        'final_value': finalValue,
        'changed_field': changedField,
        // Wire contract: FeedbackDto.createdAt is an Instant — zone-less
        // ISO is rejected with 400. Always emit UTC (see SavedQuote.toJson).
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory EditFeedback.fromJson(Map<String, dynamic> json) => EditFeedback(
        id: json['id'] as String? ?? '',
        quoteIdHash: json['quote_id_hash'] as String? ?? '',
        businessType: json['business_type'] as String? ?? 'tiling',
        serviceItemId: json['service_item_id'] as String?,
        modelResult: json['model_result'] as String?,
        finalValue: json['final_value'] as String?,
        changedField: json['changed_field'] as String? ?? 'description',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// SHA-256 hex of [quoteId]. Used so feedback rows never contain the raw
/// quote UUID (Supabase `edit_feedback.quote_id_hash`).
///
/// Pure-Dart implementation — avoids adding a crypto dependency for one hash.
String hashQuoteId(String quoteId) {
  final bytes = utf8.encode(quoteId);
  return _sha256Hex(bytes);
}

// ── Minimal SHA-256 (FIPS 180-4) ────────────────────────────────────────────
const _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

String _sha256Hex(List<int> message) {
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final ml = message.length * 8;
  final padded = List<int>.from(message)..add(0x80);
  while ((padded.length % 64) != 56) {
    padded.add(0x00);
  }
  for (var i = 7; i >= 0; i--) {
    padded.add((ml >> (i * 8)) & 0xFF);
  }

  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < padded.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = (padded[chunk + i * 4] << 24) |
          (padded[chunk + i * 4 + 1] << 16) |
          (padded[chunk + i * 4 + 2] << 8) |
          padded[chunk + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = h0, b = h1, c = h2, d = h3;
    var e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = ((e & f) ^ ((~e) & g)) & 0xFFFFFFFF;
      final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = ((a & b) ^ (a & c) ^ (b & c)) & 0xFFFFFFFF;
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
    h5 = (h5 + f) & 0xFFFFFFFF;
    h6 = (h6 + g) & 0xFFFFFFFF;
    h7 = (h7 + h) & 0xFFFFFFFF;
  }

  final parts = [h0, h1, h2, h3, h4, h5, h6, h7];
  final sb = StringBuffer();
  for (final p in parts) {
    sb.write(p.toRadixString(16).padLeft(8, '0'));
  }
  return sb.toString();
}

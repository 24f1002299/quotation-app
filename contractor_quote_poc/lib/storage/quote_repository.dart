import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';
import '../models/quote.dart';
import '../parser/demo_transcripts.dart';
import 'saved_quote.dart';

/// Day 9 — Local repository for persistent quotation management.
///
/// Handles CRUD operations via SharedPreferences with JSON serialization.
class QuoteRepository {
  static const _storageKey = 'contractor_saved_quotes_v1';

  /// Returns all saved quotes, sorted by creation date (newest first).
  static Future<List<SavedQuote>> getQuotes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey);

    if (jsonList == null || jsonList.isEmpty) {
      // Seed initial demo quotes on fresh install so History is ready
      final seeded = _getSeedQuotes();
      await saveAll(seeded);
      return seeded;
    }

    try {
      final quotes = jsonList
          .map((str) => SavedQuote.fromJson(json.decode(str) as Map<String, dynamic>))
          .toList();
      quotes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return quotes;
    } catch (_) {
      return [];
    }
  }

  /// Saves or updates [quote]. If a quote with the same `id` exists, it is replaced.
  static Future<void> saveQuote(SavedQuote quote) async {
    final quotes = await getQuotes();
    final existingIndex = quotes.indexWhere((q) => q.id == quote.id);

    if (existingIndex >= 0) {
      quotes[existingIndex] = quote;
    } else {
      quotes.insert(0, quote);
    }

    await saveAll(quotes);
  }

  /// Deletes the quote with [id].
  static Future<void> deleteQuote(String id) async {
    final quotes = await getQuotes();
    quotes.removeWhere((q) => q.id == id);
    await saveAll(quotes);
  }

  /// Looks up a quote by [id]. Returns null if not found.
  static Future<SavedQuote?> getQuoteById(String id) async {
    final quotes = await getQuotes();
    try {
      return quotes.firstWhere((q) => q.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Overwrites the full quote list in storage.
  static Future<void> saveAll(List<SavedQuote> quotes) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = quotes.map((q) => json.encode(q.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  /// Clears all saved quotes (useful for test resets).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ── Initial demo seeds for seamless presentation ──────────────────────────

  static List<SavedQuote> _getSeedQuotes() {
    return [
      SavedQuote(
        id: 'seed_tiling_1',
        quoteNumber: 'Q-2026-0042',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        trade: Trade.tiling,
        customerName: 'Sharma Ji / शर्मा जी',
        customerPhone: '+91 98765 43210',
        customerAddress: 'Flat 302, Green Acres, Mumbai',
        validityDays: 15,
        notes: '50% advance before tile delivery, balance on completion.',
        originalTranscript: kTilingDemoTranscript,
        lineItems: const [
          QuoteLineItem(
            description: 'Tile Labour / टाइल मजदूरी',
            quantity: 850,
            unit: 'sq ft',
            unitRatePaise: 4500,
          ),
          QuoteLineItem(
            description: 'Skirting / स्कर्टिंग',
            quantity: 120,
            unit: 'rft',
            unitRatePaise: 6000,
          ),
        ],
      ),
      SavedQuote(
        id: 'seed_painting_2',
        quoteNumber: 'Q-2026-0041',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        trade: Trade.painting,
        customerName: 'Verma Ji / वर्मा जी',
        customerPhone: '+91 98220 54321',
        customerAddress: 'Bungalow 7, Model Colony, Pune',
        validityDays: 30,
        notes: 'Includes Asian Paints Royale luxury emulsion, 2 coats.',
        originalTranscript: kPaintingDemoTranscript,
        lineItems: const [
          QuoteLineItem(
            description: 'Wall Putty / वॉल पुट्टी',
            quantity: 1200,
            unit: 'sq ft',
            unitRatePaise: 1800,
          ),
          QuoteLineItem(
            description: 'Painting / पेंटिंग',
            quantity: 1200,
            unit: 'sq ft',
            unitRatePaise: 1200,
          ),
        ],
      ),
    ];
  }
}

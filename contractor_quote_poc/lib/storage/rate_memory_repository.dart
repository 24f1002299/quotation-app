import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog.dart';
import '../config/api_config.dart';
import '../models/rate_memory_item.dart';
import 'sync_outbox.dart';

/// Day 12 — Repository for contractor rate memory.
///
/// Features:
/// - Local cache backed by SharedPreferences for instant, offline access.
/// - Auto-seeds from the bundled trade catalog (no bulk spreadsheets needed).
/// - Enqueues mutations to the durable [SyncOutbox].
/// - Syncs to Spring Boot API and Supabase database when connectivity is available.
class RateMemoryRepository {
  static const _storageKey = 'contractor_rate_memory_v1';

  /// Returns all saved rates. If empty, seeds from [kCatalog].
  static Future<List<RateMemoryItem>> getAllRates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey);

    if (jsonList == null || jsonList.isEmpty) {
      final seeded = _seedCatalogRates();
      await saveAll(seeded);
      return seeded;
    }

    try {
      final items = jsonList
          .map((s) => RateMemoryItem.fromJson(json.decode(s) as Map<String, dynamic>))
          .toList();

      // Ensure any newly added catalog items are included
      final seeded = _ensureCatalogSeeded(items);
      if (seeded.length != items.length) {
        await saveAll(seeded);
        return seeded;
      }
      return items;
    } catch (_) {
      final seeded = _seedCatalogRates();
      await saveAll(seeded);
      return seeded;
    }
  }

  /// Returns rates filtered by [trade].
  static Future<List<RateMemoryItem>> getRatesForTrade(Trade trade) async {
    final all = await getAllRates();
    return all.where((item) => item.trade == trade).toList();
  }

  /// Returns a map of catalogItemId -> unitRatePaise for fast parser/extraction lookup.
  static Future<Map<String, int>> getRateMap(Trade trade) async {
    final rates = await getRatesForTrade(trade);
    final map = <String, int>{};
    for (final item in rates) {
      if (item.unitRatePaise > 0) {
        map[item.catalogItemId] = item.unitRatePaise;
      }
    }
    return map;
  }

  /// Looks up rate for a specific catalog item.
  static Future<RateMemoryItem?> getRateFor(String catalogItemId, Trade trade) async {
    final rates = await getRatesForTrade(trade);
    try {
      return rates.firstWhere(
        (r) => r.catalogItemId.toLowerCase() == catalogItemId.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves or updates a single rate item.
  static Future<void> saveRate(RateMemoryItem item) async {
    final all = await getAllRates();
    final index = all.indexWhere(
      (r) => r.catalogItemId == item.catalogItemId && r.trade == item.trade,
    );

    if (index >= 0) {
      all[index] = item;
    } else {
      all.add(item);
    }

    await saveAll(all);

    // Queue in sync outbox
    await SyncOutbox.enqueue(OutboxItem(
      operationId: 'rate_${item.catalogItemId}_${DateTime.now().millisecondsSinceEpoch}',
      entityType: 'rate_memory',
      action: 'upsert',
      payload: item.toJson(),
      idempotencyKey: 'rate_${item.catalogItemId}_${item.version}',
      createdAt: DateTime.now(),
    ));

    // Attempt non-blocking backend sync
    _attemptSyncRate(item);
  }

  /// Overwrites the full rate list locally.
  static Future<void> saveAll(List<RateMemoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.map((i) => json.encode(i.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  /// Resets storage (for testing).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ── Seeding & Catalog Synchronization ─────────────────────────────────────

  static List<RateMemoryItem> _seedCatalogRates() {
    final now = DateTime.now();
    return kCatalog.map((cat) {
      // Default common starting rates for POC demo, or 0 if unconfigured
      int defaultPaise = 0;
      if (cat.id == 'tile_labour') defaultPaise = 4500; // ₹45 / sq ft
      if (cat.id == 'skirting') defaultPaise = 6000;    // ₹60 / rft
      if (cat.id == 'waterproofing') defaultPaise = 2500; // ₹25 / sq ft
      if (cat.id == 'wall_putty') defaultPaise = 1800;  // ₹18 / sq ft
      if (cat.id == 'primer') defaultPaise = 800;       // ₹8 / sq ft
      if (cat.id == 'painting') defaultPaise = 1200;    // ₹12 / sq ft

      return RateMemoryItem(
        id: 'seed_${cat.id}',
        catalogItemId: cat.id,
        trade: cat.trade,
        unit: cat.defaultUnit,
        unitRatePaise: defaultPaise,
        updatedAt: now,
      );
    }).toList();
  }

  static List<RateMemoryItem> _ensureCatalogSeeded(List<RateMemoryItem> existing) {
    final result = List<RateMemoryItem>.from(existing);
    final now = DateTime.now();

    for (final cat in kCatalog) {
      final found = result.any((r) => r.catalogItemId == cat.id && r.trade == cat.trade);
      if (!found) {
        result.add(RateMemoryItem(
          id: 'seed_${cat.id}',
          catalogItemId: cat.id,
          trade: cat.trade,
          unit: cat.defaultUnit,
          unitRatePaise: 0,
          updatedAt: now,
        ));
      }
    }
    return result;
  }

  // ── Non-blocking remote sync ──────────────────────────────────────────────

  static void _attemptSyncRate(RateMemoryItem item) async {
    try {
      // 1. Try Supabase direct if authenticated
      final supaClient = Supabase.instance.client;
      final user = supaClient.auth.currentUser;
      if (user != null) {
        await supaClient.from('rate_memory').upsert({
          'user_id': user.id,
          'catalog_item_id': item.catalogItemId,
          'trade': item.trade.name,
          'unit': item.unit,
          'unit_rate_paise': item.unitRatePaise,
          'schema_version': item.schemaVersion,
          'version': item.version,
        });
        return;
      }
    } catch (_) {
      // Fall through to Spring Boot API or leave in outbox for retry
    }

    try {
      // 2. Try Spring Boot API
      final uri = Uri.parse('$kApiBaseUrl/rates/me');
      await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode([item.toJson()]),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Safe: stays in offline outbox
    }
  }
}

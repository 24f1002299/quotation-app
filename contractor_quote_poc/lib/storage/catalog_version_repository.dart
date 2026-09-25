import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';

/// Day 16 — Model representing the version metadata of a trade catalog.
class CatalogVersion {
  final Trade trade;
  final int version;
  final int itemCount;
  final String versionTag;
  final DateTime lastUpdated;

  const CatalogVersion({
    required this.trade,
    required this.version,
    required this.itemCount,
    required this.versionTag,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'trade': trade.name,
    'version': version,
    'itemCount': itemCount,
    'versionTag': versionTag,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory CatalogVersion.fromJson(Map<String, dynamic> json) {
    final tName = json['trade'] as String? ?? 'tiling';
    final trade = Trade.values.firstWhere(
      (t) => t.name == tName,
      orElse: () => Trade.tiling,
    );
    return CatalogVersion(
      trade: trade,
      version: json['version'] as int? ?? 1,
      itemCount: json['itemCount'] as int? ?? 0,
      versionTag: json['versionTag'] as String? ?? '${tName}_v1',
      lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Day 16 — Repository for trade catalog versions.
///
/// Tracks local catalog versions, detects stale catalogs when connected to server,
/// and maintains catalog synchronization state.
class CatalogVersionRepository {
  static const _storageKey = 'contractor_catalog_versions_v1';

  /// Returns version metadata for a specific [trade].
  static Future<CatalogVersion> getVersion(Trade trade) async {
    final all = await getAllVersions();
    return all[trade] ?? _defaultVersion(trade);
  }

  /// Returns version metadata for all supported trades.
  static Future<Map<Trade, CatalogVersion>> getAllVersions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      final defaults = _seedDefaults();
      await _saveAll(defaults);
      return defaults;
    }

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final result = <Trade, CatalogVersion>{};
      for (final trade in Trade.values) {
        if (map.containsKey(trade.name)) {
          result[trade] = CatalogVersion.fromJson(map[trade.name] as Map<String, dynamic>);
        } else {
          result[trade] = _defaultVersion(trade);
        }
      }
      return result;
    } catch (_) {
      final defaults = _seedDefaults();
      await _saveAll(defaults);
      return defaults;
    }
  }

  /// Checks if the local catalog for [trade] is stale compared to [remoteVersion].
  static Future<bool> isCatalogStale(Trade trade, int remoteVersion) async {
    final current = await getVersion(trade);
    return current.version < remoteVersion;
  }

  /// Updates or registers a catalog version.
  static Future<void> updateVersion(CatalogVersion version) async {
    final all = await getAllVersions();
    all[version.trade] = version;
    await _saveAll(all);
  }

  /// Resets catalog versions storage.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static Future<void> _saveAll(Map<Trade, CatalogVersion> versions) async {
    final prefs = await SharedPreferences.getInstance();
    final map = versions.map((k, v) => MapEntry(k.name, v.toJson()));
    await prefs.setString(_storageKey, json.encode(map));
  }

  static Map<Trade, CatalogVersion> _seedDefaults() {
    return {
      Trade.tiling: _defaultVersion(Trade.tiling),
      Trade.painting: _defaultVersion(Trade.painting),
    };
  }

  static CatalogVersion _defaultVersion(Trade trade) {
    final items = kCatalog.where((c) => c.trade == trade).toList();
    return CatalogVersion(
      trade: trade,
      version: 1,
      itemCount: items.length,
      versionTag: '${trade.name}_v1.0',
      lastUpdated: DateTime(2026, 9, 25),
    );
  }
}

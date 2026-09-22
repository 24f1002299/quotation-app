import '../catalog/catalog.dart';

/// Day 12 — Contractor rate memory domain item.
///
/// Holds the contractor's saved unit rate for a specific catalog item.
class RateMemoryItem {
  final String id;
  final String catalogItemId;
  final Trade trade;
  final String unit;
  final int unitRatePaise;
  final int schemaVersion;
  final int version;
  final DateTime updatedAt;

  const RateMemoryItem({
    required this.id,
    required this.catalogItemId,
    required this.trade,
    required this.unit,
    required this.unitRatePaise,
    this.schemaVersion = 1,
    this.version = 1,
    required this.updatedAt,
  }) : assert(unitRatePaise >= 0);

  int get rateRupees => unitRatePaise ~/ 100;

  String get displayName {
    final catItem = catalogItemById(catalogItemId);
    return catItem?.displayName ?? catalogItemId;
  }

  RateMemoryItem copyWith({
    String? id,
    String? catalogItemId,
    Trade? trade,
    String? unit,
    int? unitRatePaise,
    int? schemaVersion,
    int? version,
    DateTime? updatedAt,
  }) {
    return RateMemoryItem(
      id: id ?? this.id,
      catalogItemId: catalogItemId ?? this.catalogItemId,
      trade: trade ?? this.trade,
      unit: unit ?? this.unit,
      unitRatePaise: unitRatePaise ?? this.unitRatePaise,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      version: version ?? this.version,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'catalog_item_id': catalogItemId,
      'trade': trade.name,
      'unit': unit,
      'unit_rate_paise': unitRatePaise,
      'schema_version': schemaVersion,
      'version': version,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory RateMemoryItem.fromJson(Map<String, dynamic> json) {
    final tradeStr = json['trade'] as String? ?? 'tiling';
    final trade = tradeStr.toLowerCase() == 'painting'
        ? Trade.painting
        : Trade.tiling;

    return RateMemoryItem(
      id: json['id'] as String? ?? json['catalog_item_id'] as String? ?? 'rate_item',
      catalogItemId: json['catalog_item_id'] as String? ?? json['catalogItemId'] as String? ?? '',
      trade: trade,
      unit: json['unit'] as String? ?? 'sq ft',
      unitRatePaise: (json['unit_rate_paise'] as num? ?? json['unitRatePaise'] as num? ?? 0).toInt(),
      schemaVersion: json['schema_version'] as int? ?? 1,
      version: json['version'] as int? ?? 1,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

import 'dart:math';

import '../templates/template_data.dart';

/// One service the user sells — the app's replacement for a fixed catalog
/// entry plus its saved rate.
///
/// A service carries its own name, unit, rate, and the keywords the parser and
/// extraction use to recognise it in speech. Everything is user-editable.
class ServiceItem {
  final String id;
  final String name;

  /// Optional localized names; the parser also matches these.
  final String? nameHi;
  final String? nameMr;

  /// Default unit for this service ('sq ft', 'rft', 'point', 'item', …).
  final String unit;

  /// Saved unit rate in paise. Never negative; 0 means "rate not set yet".
  final int ratePaise;

  final BusinessType businessType;

  /// Lower-case speech keywords: Hindi/Marathi/Hinglish synonyms of [name].
  final List<String> keywords;

  /// Inactive services stay saved but are hidden from the quote flow.
  final bool isActive;

  /// Display order in the user's service list.
  final int sortOrder;

  final String notes;
  final int schemaVersion;

  /// Record version for optimistic concurrency and conflict detection.
  final int version;
  final DateTime updatedAt;

  const ServiceItem({
    required this.id,
    required this.name,
    this.nameHi,
    this.nameMr,
    this.unit = 'item',
    this.ratePaise = 0,
    this.businessType = BusinessType.tiling,
    this.keywords = const [],
    this.isActive = true,
    this.sortOrder = 0,
    this.notes = '',
    this.schemaVersion = 1,
    this.version = 1,
    required this.updatedAt,
  })  : assert(ratePaise >= 0),
        assert(sortOrder >= 0);

  int get rateRupees => ratePaise ~/ 100;

  /// A fresh, unsaved service ready for the add-item form.
  factory ServiceItem.draft({
    required String name,
    BusinessType businessType = BusinessType.tiling,
    String unit = 'item',
    int ratePaise = 0,
    List<String> keywords = const [],
  }) {
    return ServiceItem(
      id: newServiceItemId(),
      name: name,
      unit: unit,
      ratePaise: ratePaise,
      businessType: businessType,
      keywords: keywords,
      sortOrder: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now(),
    );
  }

  /// Every phrase that should match this service in a transcript.
  List<String> get matchTerms {
    final terms = <String>{name.trim().toLowerCase()};
    for (final value in [nameHi, nameMr]) {
      final v = value?.trim().toLowerCase();
      if (v != null && v.isNotEmpty) terms.add(v);
    }
    for (final k in keywords) {
      final v = k.trim().toLowerCase();
      if (v.isNotEmpty) terms.add(v);
    }
    return terms.toList(growable: false);
  }

  ServiceItem copyWith({
    String? id,
    String? name,
    String? nameHi,
    String? nameMr,
    String? unit,
    int? ratePaise,
    BusinessType? businessType,
    List<String>? keywords,
    bool? isActive,
    int? sortOrder,
    String? notes,
    int? schemaVersion,
    int? version,
    DateTime? updatedAt,
  }) {
    return ServiceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      nameHi: nameHi ?? this.nameHi,
      nameMr: nameMr ?? this.nameMr,
      unit: unit ?? this.unit,
      ratePaise: ratePaise ?? this.ratePaise,
      businessType: businessType ?? this.businessType,
      keywords: keywords ?? this.keywords,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      notes: notes ?? this.notes,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      version: version ?? this.version,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'name_hi': nameHi,
        'name_mr': nameMr,
        'unit': unit,
        'rate_paise': ratePaise,
        'business_type': businessTypeInfo(businessType).id,
        'keywords': keywords,
        'is_active': isActive,
        'sort_order': sortOrder,
        'notes': notes,
        'schema_version': schemaVersion,
        'version': version,
        // Wire contract: service records are parsed as Instant on the server —
        // zone-less ISO is rejected with 400. Always UTC (see SavedQuote).
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    return ServiceItem(
      id: json['id'] as String? ?? newServiceItemId(),
      name: json['name'] as String? ?? '',
      nameHi: json['name_hi'] as String? ?? json['nameHi'] as String?,
      nameMr: json['name_mr'] as String? ?? json['nameMr'] as String?,
      unit: json['unit'] as String? ?? 'item',
      ratePaise:
          (json['rate_paise'] as num? ?? json['ratePaise'] as num? ?? 0).toInt(),
      businessType: businessTypeFromId(
        json['business_type'] as String? ?? json['businessType'] as String?,
      ),
      keywords: [
        for (final k in (json['keywords'] as List<dynamic>? ?? const []))
          if (k is String) k,
      ],
      isActive: json['is_active'] as bool? ?? json['isActive'] as bool? ?? true,
      sortOrder:
          (json['sort_order'] as num? ?? json['sortOrder'] as num? ?? 0).toInt(),
      notes: json['notes'] as String? ?? '',
      schemaVersion: json['schema_version'] as int? ?? 1,
      version: json['version'] as int? ?? 1,
      updatedAt: DateTime.tryParse(
            json['updated_at'] as String? ?? json['updatedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }
}

/// Local id for a service the user just created. Offline-safe: the id is
/// generated on the phone and reused as the idempotency anchor on sync.
String newServiceItemId() =>
    'svc_${DateTime.now().microsecondsSinceEpoch}_${_shortRandom()}';

String _shortRandom() {
  final rnd = Random.secure();
  return List<int>.generate(4, (_) => rnd.nextInt(16))
      .map((n) => n.toRadixString(16))
      .join();
}

/// Business types and starter-template shapes.
///
/// A user owns a list of services ([ServiceItem]) instead of a fixed bundled
/// catalog. A starter template is only a seed: it is loaded once when the
/// user picks a business type, then the user edits it freely.
library;

import 'package:flutter/material.dart';

/// The business types the app ships a starter template for.
/// Universal extraction works for any domain via the user's own service list;
/// these are just the bundled seeds.
enum BusinessType {
  tiling,
  painting,
  plumbing,
  electrical,
  carpentry,
  waterproofing,
  masonry,
  furniture,
  applianceRepair,
  cleaning,
  pestControl,
  catering,
}

/// Static, non-user-editable metadata for one business type.
class BusinessTypeInfo {
  final BusinessType type;

  /// Stable id used in JSON, storage keys, and the backend contract.
  final String id;

  /// Localized display labels, keyed by language code ('en', 'hi', 'mr').
  final Map<String, String> labels;
  final IconData icon;

  const BusinessTypeInfo({
    required this.type,
    required this.id,
    required this.labels,
    required this.icon,
  });

  /// Label for [languageCode], falling back to English.
  String label(String languageCode) =>
      labels[languageCode] ?? labels['en'] ?? id;

  /// Bundled starter template for this type.
  String get templateAsset => 'assets/templates/$id.json';
}

/// All business types, in the order they are offered to users.
const List<BusinessTypeInfo> kBusinessTypes = [
  BusinessTypeInfo(
    type: BusinessType.tiling,
    id: 'tiling',
    labels: {'en': 'Tiling', 'hi': 'टाइलिंग', 'mr': 'टाइलिंग'},
    icon: Icons.grid_4x4_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.painting,
    id: 'painting',
    labels: {'en': 'Painting', 'hi': 'पेंटिंग', 'mr': 'पेंटिंग'},
    icon: Icons.format_paint_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.plumbing,
    id: 'plumbing',
    labels: {'en': 'Plumbing', 'hi': 'प्लंबिंग', 'mr': 'प्लंबिंग'},
    icon: Icons.plumbing_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.electrical,
    id: 'electrical',
    labels: {'en': 'Electrical', 'hi': 'इलेक्ट्रिकल', 'mr': 'इलेक्ट्रिकल'},
    icon: Icons.electrical_services_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.carpentry,
    id: 'carpentry',
    labels: {'en': 'Carpentry', 'hi': 'बढ़ईगरी', 'mr': 'सुतारकाम'},
    icon: Icons.handyman_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.waterproofing,
    id: 'waterproofing',
    labels: {
      'en': 'Waterproofing',
      'hi': 'वॉटरप्रूफिंग',
      'mr': 'पाणीरोधक काम',
    },
    icon: Icons.shower_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.masonry,
    id: 'masonry',
    labels: {'en': 'Masonry', 'hi': 'गवंडी का काम', 'mr': 'गवंडीकाम'},
    icon: Icons.foundation_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.furniture,
    id: 'furniture',
    labels: {'en': 'Furniture', 'hi': 'फर्नीचर', 'mr': 'फर्निचर'},
    icon: Icons.chair_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.applianceRepair,
    id: 'appliance_repair',
    labels: {
      'en': 'AC & appliance repair',
      'hi': 'एसी एवं उपकरण सर्विस',
      'mr': 'एसी दुरुस्ती',
    },
    icon: Icons.ac_unit_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.cleaning,
    id: 'cleaning',
    labels: {'en': 'Cleaning', 'hi': 'सफ़ाई', 'mr': 'साफसफाई'},
    icon: Icons.cleaning_services_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.pestControl,
    id: 'pest_control',
    labels: {'en': 'Pest control', 'hi': 'कीट नियंत्रण', 'mr': 'कीड नियंत्रण'},
    icon: Icons.bug_report_rounded,
  ),
  BusinessTypeInfo(
    type: BusinessType.catering,
    id: 'catering',
    labels: {'en': 'Catering', 'hi': 'कैटरिंग', 'mr': 'जेवण पुरवठा'},
    icon: Icons.restaurant_rounded,
  ),
];

/// Metadata for [type], or the first entry when unknown.
BusinessTypeInfo businessTypeInfo(BusinessType type) =>
    kBusinessTypes.firstWhere(
      (info) => info.type == type,
      orElse: () => kBusinessTypes.first,
    );

/// Resolves a persisted/backend id ('appliance_repair') to a business type.
/// Unknown or missing ids fall back to [fallback] (default: tiling).
BusinessType businessTypeFromId(String? id, {BusinessType fallback = BusinessType.tiling}) {
  if (id == null || id.trim().isEmpty) return fallback;
  final lower = id.trim().toLowerCase();
  for (final info in kBusinessTypes) {
    if (info.id == lower) return info.type;
  }
  return fallback;
}

/// One service row inside a starter template (JSON).
class StarterService {
  final String name;
  final String? nameHi;
  final String? nameMr;
  final String unit;

  /// Starting rate in paise. A hint only — the user edits it.
  final int defaultRatePaise;
  final List<String> keywords;

  const StarterService({
    required this.name,
    this.nameHi,
    this.nameMr,
    required this.unit,
    this.defaultRatePaise = 0,
    this.keywords = const [],
  });

  factory StarterService.fromJson(Map<String, dynamic> json) => StarterService(
        name: json['name'] as String? ?? 'Service',
        nameHi: json['name_hi'] as String?,
        nameMr: json['name_mr'] as String?,
        unit: json['unit'] as String? ?? 'item',
        defaultRatePaise:
            (json['default_rate_paise'] as num? ?? 0).toInt(),
        keywords: [
          for (final k in (json['keywords'] as List<dynamic>? ?? const []))
            if (k is String && k.trim().isNotEmpty) k.trim(),
        ],
      );
}

/// A parsed starter template: one business type plus its seeded services.
class ServiceTemplate {
  final BusinessType businessType;
  final String labelEn;
  final String? labelHi;
  final String? labelMr;
  final String defaultUnit;
  final List<StarterService> services;

  const ServiceTemplate({
    required this.businessType,
    required this.labelEn,
    this.labelHi,
    this.labelMr,
    required this.defaultUnit,
    required this.services,
  });

  /// Every keyword in the template, lower-cased and de-duplicated.
  List<String> get keywords {
    final seen = <String>{};
    for (final service in services) {
      for (final keyword in service.keywords) {
        seen.add(keyword.toLowerCase());
      }
    }
    return seen.toList(growable: false);
  }

  factory ServiceTemplate.fromJson(Map<String, dynamic> json) => ServiceTemplate(
        businessType: businessTypeFromId(json['business_type'] as String?),
        labelEn: (json['label'] as Map<String, dynamic>?)?['en'] as String? ??
            'Business',
        labelHi: (json['label'] as Map<String, dynamic>?)?['hi'] as String?,
        labelMr: (json['label'] as Map<String, dynamic>?)?['mr'] as String?,
        defaultUnit: json['default_unit'] as String? ?? 'item',
        services: [
          for (final raw in (json['services'] as List<dynamic>? ?? const []))
            StarterService.fromJson(raw as Map<String, dynamic>),
        ],
      );
}

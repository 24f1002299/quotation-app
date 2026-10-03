import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../templates/template_data.dart';
import '../templates/template_loader.dart';

/// Version metadata for the user's saved service list.
///
/// The list is user-owned but still synced, so the review screen warns when
/// the server holds a newer version than the phone (e.g. the same services
/// were edited on another device).
class ServiceListVersion {
  final BusinessType businessType;
  final int version;
  final int itemCount;
  final String versionTag;
  final DateTime lastUpdated;

  const ServiceListVersion({
    required this.businessType,
    required this.version,
    required this.itemCount,
    required this.versionTag,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'business_type': businessTypeInfo(businessType).id,
        'version': version,
        'itemCount': itemCount,
        'versionTag': versionTag,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory ServiceListVersion.fromJson(Map<String, dynamic> json) {
    final id = json['business_type'] as String?;
    final businessType = businessTypeFromId(id);
    return ServiceListVersion(
      businessType: businessType,
      version: json['version'] as int? ?? 1,
      itemCount: json['itemCount'] as int? ?? 0,
      versionTag: json['versionTag'] as String? ?? '${businessTypeInfo(businessType).id}_v1',
      lastUpdated:
          DateTime.tryParse(json['lastUpdated'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Stores the locally-known version of each business type's service list.
class ServiceListVersionRepository {
  static const _storageKey = 'service_list_versions_v1';

  static Future<ServiceListVersion> getVersion(BusinessType businessType) async {
    final all = await getAllVersions();
    return all[businessType] ?? _defaultVersion(businessType);
  }

  static Future<Map<BusinessType, ServiceListVersion>> getAllVersions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      final defaults = await _seedDefaults();
      await _saveAll(defaults);
      return defaults;
    }

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final result = <BusinessType, ServiceListVersion>{};
      for (final info in kBusinessTypes) {
        final raw = map[info.id];
        result[info.type] = raw is Map<String, dynamic>
            ? ServiceListVersion.fromJson(raw)
            : await _defaultWithTemplateCount(info.type);
      }
      return result;
    } catch (_) {
      final defaults = await _seedDefaults();
      await _saveAll(defaults);
      return defaults;
    }
  }

  /// True when the server's [remoteVersion] is ahead of the local copy.
  static Future<bool> isServiceListStale(
    BusinessType businessType,
    int remoteVersion,
  ) async {
    final current = await getVersion(businessType);
    return current.version < remoteVersion;
  }

  static Future<void> updateVersion(ServiceListVersion version) async {
    final all = await getAllVersions();
    all[version.businessType] = version;
    await _saveAll(all);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static Future<void> _saveAll(
    Map<BusinessType, ServiceListVersion> versions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final map = versions.map(
      (k, v) => MapEntry(businessTypeInfo(k).id, v.toJson()),
    );
    await prefs.setString(_storageKey, json.encode(map));
  }

  static Future<Map<BusinessType, ServiceListVersion>> _seedDefaults() async {
    final map = <BusinessType, ServiceListVersion>{};
    for (final info in kBusinessTypes) {
      map[info.type] = await _defaultWithTemplateCount(info.type);
    }
    return map;
  }

  /// Default version carrying the bundled template's item count, so a fresh
  /// install reports real seeds (tiling: 6) instead of zeros. Types without
  /// a template (Other) stay at 0.
  static Future<ServiceListVersion> _defaultWithTemplateCount(
    BusinessType businessType,
  ) async {
    var count = 0;
    try {
      final template = await TemplateLoader.load(businessType);
      count = template.services.length;
    } catch (_) {
      count = 0;
    }
    return ServiceListVersion(
      businessType: businessType,
      version: 1,
      itemCount: count,
      versionTag: '${businessTypeInfo(businessType).id}_v1',
      lastUpdated: DateTime.now(),
    );
  }

  static ServiceListVersion _defaultVersion(BusinessType businessType) {
    return ServiceListVersion(
      businessType: businessType,
      version: 1,
      itemCount: 0,
      versionTag: '${businessTypeInfo(businessType).id}_v1',
      lastUpdated: DateTime.now(),
    );
  }
}

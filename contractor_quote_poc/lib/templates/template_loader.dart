import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/service_item.dart';
import 'template_data.dart';

/// Loads the bundled starter templates for a business type.
///
/// Templates are JSON assets so the service list can grow without shipping new
/// Dart code. Each template is read once and cached for the app's lifetime.
class TemplateLoader {
  const TemplateLoader._();

  static final Map<String, ServiceTemplate> _cache = {};

  /// The starter template for [businessType].
  ///
  /// Throws [FlutterError] when the asset is missing or malformed — a broken
  /// template must fail loudly at development time, not silently seed nothing.
  static Future<ServiceTemplate> load(BusinessType businessType) async {
    final info = businessTypeInfo(businessType);
    final cached = _cache[info.id];
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(info.templateAsset);
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw FlutterError('Starter template ${info.id} is not a JSON object');
    }

    final template = ServiceTemplate.fromJson(json);
    _cache[info.id] = template;
    return template;
  }

  /// Starter services for [businessType] as ready-to-save [ServiceItem]s.
  ///
  /// Rates come from the template as starting points; the user is expected to
  /// correct them. Ids are generated on the phone so the list works offline.
  static Future<List<ServiceItem>> starterServiceItems(
    BusinessType businessType,
  ) async {
    final template = await load(businessType);
    var order = 0;
    return [
      for (final starter in template.services)
        ServiceItem(
          id: newServiceItemId(),
          name: starter.name,
          nameHi: starter.nameHi,
          nameMr: starter.nameMr,
          unit: starter.unit.isNotEmpty ? starter.unit : template.defaultUnit,
          ratePaise: starter.defaultRatePaise,
          businessType: businessType,
          keywords: starter.keywords,
          sortOrder: order++,
          updatedAt: DateTime.now(),
        ),
    ];
  }

  /// Drops the in-memory cache (used by tests that rebundle assets).
  static void clearCache() => _cache.clear();
}

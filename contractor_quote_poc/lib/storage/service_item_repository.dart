import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import '../models/service_item.dart';
import '../templates/template_data.dart';
import '../templates/template_loader.dart';
import 'sync_outbox.dart';

/// The user's own service list — CRUD plus the lookups the quote flow needs.
///
/// Features:
/// - Local cache in SharedPreferences for instant, offline access.
/// - Seeds itself from the bundled starter template the first time a business
///   type is used, so a fresh install is usable without typing a service list.
/// - Enqueues every mutation to the durable [SyncOutbox], then attempts a
///   non-blocking remote sync.
class ServiceItemRepository {
  static const _storageKey = 'service_items_v1';

  /// All services, ordered by [ServiceItem.sortOrder] then name.
  static Future<List<ServiceItem>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey);
    if (jsonList == null || jsonList.isEmpty) return [];

    try {
      final items = jsonList
          .map((s) => ServiceItem.fromJson(json.decode(s) as Map<String, dynamic>))
          .toList();
      items.sort(_bySortOrder);
      return items;
    } catch (_) {
      // A corrupt cache must not block the app; start from the seed below.
      return [];
    }
  }

  /// Active services only — what the quote flow and voice matching use.
  static Future<List<ServiceItem>> getActive() async {
    final all = await getAll();
    return all.where((s) => s.isActive).toList(growable: false);
  }

  /// Active services for one business type.
  static Future<List<ServiceItem>> getActiveForBusinessType(
    BusinessType businessType,
  ) async {
    final all = await getActive();
    return all
        .where((s) => s.businessType == businessType)
        .toList(growable: false);
  }

  static Future<ServiceItem?> getById(String id) async {
    final all = await getAll();
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Services whose name or keywords contain [query] (case-insensitive).
  static Future<List<ServiceItem>> search(String query) async {
    final needle = query.trim().toLowerCase();
    final all = await getActive();
    if (needle.isEmpty) return all;
    return all
        .where((s) =>
            s.name.toLowerCase().contains(needle) ||
            s.matchTerms.any((term) => term.contains(needle)))
        .toList(growable: false);
  }

  /// Saved rate per service id (paise) for fast parser/extraction lookup.
  static Future<Map<String, int>> getRateMap(BusinessType businessType) async {
    final services = await getActiveForBusinessType(businessType);
    return {
      for (final s in services)
        if (s.ratePaise > 0) s.id: s.ratePaise,
    };
  }

  /// Creates or updates one service: persists locally, enqueues the sync
  /// outbox mutation, then attempts a non-blocking remote sync.
  static Future<ServiceItem> save(ServiceItem item) async {
    final all = await getAll();
    final updated = item.copyWith(
      version: item.version + 1,
      updatedAt: DateTime.now(),
    );

    final index = all.indexWhere((s) => s.id == updated.id);
    if (index >= 0) {
      all[index] = updated;
    } else {
      all.add(updated);
    }
    await saveAll(all);

    await SyncOutbox.enqueue(OutboxItem(
      operationId: 'service_item_${updated.id}_${updated.version}',
      entityType: 'service_item',
      action: 'upsert',
      payload: updated.toJson(),
      idempotencyKey: 'service_item_${updated.id}_${updated.version}',
      createdAt: DateTime.now(),
    ));

    _attemptSync(updated, index >= 0 ? 'update' : 'insert');
    return updated;
  }

  /// Convenience for the add/edit form: updates [id] when it exists,
  /// otherwise creates a new service from the given values.
  static Future<ServiceItem> upsert({
    String? id,
    required String name,
    String? nameHi,
    String? nameMr,
    String unit = 'item',
    int ratePaise = 0,
    required BusinessType businessType,
    List<String> keywords = const [],
    bool isActive = true,
    int? sortOrder,
    String notes = '',
  }) async {
    final existing = id == null ? null : await getById(id);
    return save(
      ServiceItem(
        id: existing?.id ?? newServiceItemId(),
        name: name,
        nameHi: nameHi,
        nameMr: nameMr,
        unit: unit,
        ratePaise: ratePaise < 0 ? 0 : ratePaise,
        businessType: businessType,
        keywords: keywords,
        isActive: isActive,
        sortOrder: sortOrder ?? existing?.sortOrder ?? 0,
        notes: notes,
        schemaVersion: existing?.schemaVersion ?? 1,
        version: existing?.version ?? 1,
        updatedAt: existing?.updatedAt ?? DateTime.now(),
      ),
    );
  }

  /// Removes one service locally and queues the delete for the server.
  static Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((s) => s.id == id);
    await saveAll(all);

    await SyncOutbox.enqueue(OutboxItem(
      operationId: 'service_item_delete_$id',
      entityType: 'service_item',
      action: 'delete',
      payload: {'id': id},
      idempotencyKey: 'service_item_delete_$id',
      createdAt: DateTime.now(),
    ));
  }

  /// Replaces the whole list (bulk edit, seeding, sync merges).
  static Future<void> saveAll(List<ServiceItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...items]..sort(_bySortOrder);
    await prefs.setStringList(
      _storageKey,
      sorted.map((i) => json.encode(i.toJson())).toList(),
    );
  }

  /// Seeds the starter template for [businessType] when the user has no
  /// service for it yet. Existing services are never overwritten.
  /// Returns the services now on file for that business type.
  static Future<List<ServiceItem>> seedFromTemplate(
    BusinessType businessType,
  ) async {
    final existing = await getActiveForBusinessType(businessType);
    if (existing.isNotEmpty) return existing;

    final seeded = await TemplateLoader.starterServiceItems(businessType);
    final all = await getAll();
    await saveAll([...all, ...seeded]);
    return seeded;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static int _bySortOrder(ServiceItem a, ServiceItem b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
  }

  // ── Non-blocking remote sync ──────────────────────────────────────────────

  static void _attemptSync(ServiceItem item, String action) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        await client.from('service_items').upsert({
          'id': item.id,
          'user_id': user.id,
          'name': item.name,
          'name_hi': item.nameHi,
          'name_mr': item.nameMr,
          'unit': item.unit,
          'rate_paise': item.ratePaise,
          'business_type': businessTypeInfo(item.businessType).id,
          'keywords': item.keywords,
          'is_active': item.isActive,
          'sort_order': item.sortOrder,
          'notes': item.notes,
          'schema_version': item.schemaVersion,
          'version': item.version,
          'updated_at': item.updatedAt.toUtc().toIso8601String(),
        });
        return;
      }
    } catch (_) {
      // Supabase offline / uninitialized — fall through to the API.
    }

    try {
      await http
          .put(
            Uri.parse('$kApiBaseUrl/services/me'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'action': action, 'service': item.toJson()}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Stays safely in the outbox until connectivity returns.
    }
  }
}

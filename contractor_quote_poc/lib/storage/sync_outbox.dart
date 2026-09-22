import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// An item pending synchronization with backend / Supabase.
class OutboxItem {
  final String operationId;
  final String entityType; // 'profile' or 'rate_memory'
  final String action;     // 'upsert' or 'delete'
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final int retryCount;
  final DateTime createdAt;

  const OutboxItem({
    required this.operationId,
    required this.entityType,
    required this.action,
    required this.payload,
    required this.idempotencyKey,
    this.retryCount = 0,
    required this.createdAt,
  });

  OutboxItem incrementRetry() {
    return OutboxItem(
      operationId: operationId,
      entityType: entityType,
      action: action,
      payload: payload,
      idempotencyKey: idempotencyKey,
      retryCount: retryCount + 1,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'entityType': entityType,
        'action': action,
        'payload': payload,
        'idempotencyKey': idempotencyKey,
        'retryCount': retryCount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        operationId: json['operationId'] as String,
        entityType: json['entityType'] as String,
        action: json['action'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        idempotencyKey: json['idempotencyKey'] as String,
        retryCount: json['retryCount'] as int? ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now(),
      );
}

/// Durable local outbox stored in SharedPreferences.
class SyncOutbox {
  static const _storageKey = 'contractor_sync_outbox_v1';

  static Future<List<OutboxItem>> getPending() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey);
    if (jsonList == null || jsonList.isEmpty) return [];

    try {
      return jsonList
          .map((s) => OutboxItem.fromJson(json.decode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> enqueue(OutboxItem item) async {
    final items = await getPending();
    items.add(item);
    await _save(items);
  }

  static Future<void> remove(String operationId) async {
    final items = await getPending();
    items.removeWhere((item) => item.operationId == operationId);
    await _save(items);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static Future<void> _save(List<OutboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.map((i) => json.encode(i.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }
}

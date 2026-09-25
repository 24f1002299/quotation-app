import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Day 12 & Day 16 — An item pending synchronization with backend / Supabase.
///
/// Contains operation ID, idempotency key, retry count, and payload version
/// as required for durable, offline-safe operation synchronization.
class OutboxItem {
  final String operationId;
  final String entityType; // 'profile', 'rate_memory', or 'quote'
  final String action;     // 'upsert' or 'delete'
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final int retryCount;
  final int payloadVersion;
  final DateTime createdAt;
  final DateTime? nextRetryAt;
  final String? lastError;
  final bool hasConflict;
  final Map<String, dynamic>? conflictingPayload;

  const OutboxItem({
    required this.operationId,
    required this.entityType,
    required this.action,
    required this.payload,
    required this.idempotencyKey,
    this.retryCount = 0,
    this.payloadVersion = 1,
    required this.createdAt,
    this.nextRetryAt,
    this.lastError,
    this.hasConflict = false,
    this.conflictingPayload,
  });

  /// Calculates bounded exponential backoff: base 1s, doubling up to bound of 30s.
  static Duration calculateBackoff(int retry) {
    const int baseSec = 1;
    const int maxSec = 30;
    final int expSec = baseSec * (1 << min(5, retry));
    final int clamped = min(maxSec, expSec);
    return Duration(seconds: clamped);
  }

  OutboxItem incrementRetry({Duration? backoffDelay, String? error}) {
    final nextRetry = retryCount + 1;
    final delay = backoffDelay ?? calculateBackoff(nextRetry);
    return OutboxItem(
      operationId: operationId,
      entityType: entityType,
      action: action,
      payload: payload,
      idempotencyKey: idempotencyKey,
      retryCount: nextRetry,
      payloadVersion: payloadVersion,
      createdAt: createdAt,
      nextRetryAt: DateTime.now().add(delay),
      lastError: error ?? lastError,
      hasConflict: hasConflict,
      conflictingPayload: conflictingPayload,
    );
  }

  OutboxItem markConflict(Map<String, dynamic> serverPayload) {
    return OutboxItem(
      operationId: operationId,
      entityType: entityType,
      action: action,
      payload: payload,
      idempotencyKey: idempotencyKey,
      retryCount: retryCount,
      payloadVersion: payloadVersion,
      createdAt: createdAt,
      nextRetryAt: nextRetryAt,
      lastError: 'VERSION_CONFLICT',
      hasConflict: true,
      conflictingPayload: serverPayload,
    );
  }

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'entityType': entityType,
    'action': action,
    'payload': payload,
    'idempotencyKey': idempotencyKey,
    'retryCount': retryCount,
    'payloadVersion': payloadVersion,
    'createdAt': createdAt.toIso8601String(),
    'nextRetryAt': nextRetryAt?.toIso8601String(),
    'lastError': lastError,
    'hasConflict': hasConflict,
    'conflictingPayload': conflictingPayload,
  };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
    operationId: json['operationId'] as String,
    entityType: json['entityType'] as String,
    action: json['action'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    idempotencyKey: json['idempotencyKey'] as String,
    retryCount: json['retryCount'] as int? ?? 0,
    payloadVersion: json['payloadVersion'] as int? ?? 1,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    nextRetryAt: json['nextRetryAt'] != null
        ? DateTime.tryParse(json['nextRetryAt'] as String)
        : null,
    lastError: json['lastError'] as String?,
    hasConflict: json['hasConflict'] as bool? ?? false,
    conflictingPayload: json['conflictingPayload'] != null
        ? Map<String, dynamic>.from(json['conflictingPayload'] as Map)
        : null,
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
    // If an item with the same operationId OR same entityType + payload['id'] exists, replace it
    final idx = items.indexWhere((i) {
      if (i.operationId == item.operationId) return true;
      if (i.entityType == item.entityType && i.action == item.action) {
        final existingId = i.payload['id'];
        final newId = item.payload['id'];
        if (existingId != null && newId != null && existingId == newId) {
          return true;
        }
      }
      return false;
    });
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _save(items);
  }

  static Future<void> update(OutboxItem item) async {
    final items = await getPending();
    final idx = items.indexWhere((i) => i.operationId == item.operationId);
    if (idx >= 0) {
      items[idx] = item;
      await _save(items);
    }
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

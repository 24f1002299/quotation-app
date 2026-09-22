package com.quotapp.security;

import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Thread-safe in-memory cache for idempotency keys scoped per authenticated user.
 *
 * <p>Guarantees that retry requests carrying the same {@code Idempotency-Key} header
 * return the exact previously computed response without re-triggering upstream processing.
 */
@Service
public class IdempotencyService {

    private static final long TTL_MILLIS = 10 * 60 * 1000L; // 10 minutes TTL
    private static final int MAX_ENTRIES = 10_000;

    private record CachedResponse(Object response, Instant createdAt) {}

    private final ConcurrentHashMap<String, CachedResponse> cache = new ConcurrentHashMap<>();

    /**
     * Retrieves a cached response if valid and not expired.
     */
    public Object get(String userId, String idempotencyKey) {
        if (userId == null || idempotencyKey == null || idempotencyKey.isBlank()) {
            return null;
        }
        String key = makeKey(userId, idempotencyKey);
        CachedResponse cached = cache.get(key);
        if (cached == null) {
            return null;
        }
        if (Instant.now().toEpochMilli() - cached.createdAt().toEpochMilli() > TTL_MILLIS) {
            cache.remove(key);
            return null;
        }
        return cached.response();
    }

    /**
     * Stores a response for the given user and idempotency key.
     */
    public void put(String userId, String idempotencyKey, Object response) {
        if (userId == null || idempotencyKey == null || idempotencyKey.isBlank() || response == null) {
            return;
        }
        if (cache.size() >= MAX_ENTRIES) {
            cleanupExpired();
        }
        String key = makeKey(userId, idempotencyKey);
        cache.put(key, new CachedResponse(response, Instant.now()));
    }

    private String makeKey(String userId, String idempotencyKey) {
        return userId + ":" + idempotencyKey.trim();
    }

    private void cleanupExpired() {
        long now = Instant.now().toEpochMilli();
        cache.entrySet().removeIf(entry -> now - entry.getValue().createdAt().toEpochMilli() > TTL_MILLIS);
    }
}

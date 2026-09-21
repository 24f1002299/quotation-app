package com.quotapp.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Sliding-window rate limiter per user ID.
 *
 * <p>Enforces Day 9 constraint: rate limiting user requests to prevent abuse
 * and unexpected third-party STT bills.
 */
@Component
public class UserRateLimiter {

    private final int maxRequests;
    private final long windowMillis;
    private final Map<String, Deque<Long>> userRequestTimestamps = new ConcurrentHashMap<>();

    public UserRateLimiter(
        @Value("${quotapp.rate-limit.max-requests-per-minute:10}") int maxRequestsPerMinute
    ) {
        this.maxRequests = maxRequestsPerMinute;
        this.windowMillis = 60_000L;
    }

    /**
     * Checks if a request for {@code userId} is allowed.
     *
     * @param userId authenticated user ID
     * @return true if request is permitted under rate limit, false if exceeded
     */
    public synchronized boolean tryAcquire(String userId) {
        if (userId == null || userId.isBlank()) {
            return false;
        }

        long now = System.currentTimeMillis();
        long windowStart = now - windowMillis;

        Deque<Long> timestamps = userRequestTimestamps.computeIfAbsent(userId, k -> new ArrayDeque<>());

        // Evict expired timestamps outside window
        while (!timestamps.isEmpty() && timestamps.peekFirst() < windowStart) {
            timestamps.pollFirst();
        }

        if (timestamps.size() >= maxRequests) {
            return false;
        }

        timestamps.addLast(now);
        return true;
    }

    /** Reset rate limit for a specific user (useful in tests). */
    public synchronized void reset(String userId) {
        if (userId != null) {
            userRequestTimestamps.remove(userId);
        }
    }

    /** Reset all tracked users. */
    public synchronized void clear() {
        userRequestTimestamps.clear();
    }
}

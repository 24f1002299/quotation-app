package com.quotapp.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class UserRateLimiterTest {

    private UserRateLimiter rateLimiter;

    @BeforeEach
    void setUp() {
        rateLimiter = new UserRateLimiter(3);
    }

    @Test
    @DisplayName("Allows up to max requests per user")
    void testAllowsUpToMax() {
        String userId = "user-123";

        assertThat(rateLimiter.tryAcquire(userId)).isTrue();
        assertThat(rateLimiter.tryAcquire(userId)).isTrue();
        assertThat(rateLimiter.tryAcquire(userId)).isTrue();
        assertThat(rateLimiter.tryAcquire(userId)).isFalse();
    }

    @Test
    @DisplayName("Isolates limits across different users")
    void testUserIsolation() {
        String userA = "user-a";
        String userB = "user-b";

        assertThat(rateLimiter.tryAcquire(userA)).isTrue();
        assertThat(rateLimiter.tryAcquire(userA)).isTrue();
        assertThat(rateLimiter.tryAcquire(userA)).isTrue();
        assertThat(rateLimiter.tryAcquire(userA)).isFalse();

        // userB still has full quota
        assertThat(rateLimiter.tryAcquire(userB)).isTrue();
        assertThat(rateLimiter.tryAcquire(userB)).isTrue();
    }

    @Test
    @DisplayName("Rejects null or blank user IDs")
    void testRejectsInvalidUser() {
        assertThat(rateLimiter.tryAcquire(null)).isFalse();
        assertThat(rateLimiter.tryAcquire("")).isFalse();
        assertThat(rateLimiter.tryAcquire("   ")).isFalse();
    }

    @Test
    @DisplayName("Reset restores quota for user")
    void testResetRestoresQuota() {
        String userId = "user-reset";
        for (int i = 0; i < 3; i++) {
            rateLimiter.tryAcquire(userId);
        }
        assertThat(rateLimiter.tryAcquire(userId)).isFalse();

        rateLimiter.reset(userId);
        assertThat(rateLimiter.tryAcquire(userId)).isTrue();
    }
}

package com.quotapp.api.resilience;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Circuit breaker protecting the system from cascading upstream LLM provider failures.
 *
 * <p>Transitions to {@code OPEN} after consecutive failures reach the threshold,
 * fast-failing subsequent requests for {@code cooldownMillis} before testing in {@code HALF_OPEN}.
 */
@Component
public class ExtractionCircuitBreaker {

    private static final Logger log = LoggerFactory.getLogger(ExtractionCircuitBreaker.class);

    public enum State {
        CLOSED,
        OPEN,
        HALF_OPEN
    }

    private final int failureThreshold;
    private final long cooldownMillis;

    private final AtomicReference<State> state = new AtomicReference<>(State.CLOSED);
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private final AtomicLong lastStateChangeTime = new AtomicLong(System.currentTimeMillis());

    public ExtractionCircuitBreaker() {
        this(5, 30_000L); // 5 consecutive failures, 30s cooldown
    }

    public ExtractionCircuitBreaker(int failureThreshold, long cooldownMillis) {
        this.failureThreshold = failureThreshold;
        this.cooldownMillis = cooldownMillis;
    }

    public boolean canExecute() {
        State current = state.get();
        if (current == State.CLOSED) {
            return true;
        }

        long now = System.currentTimeMillis();
        long elapsed = now - lastStateChangeTime.get();

        if (current == State.OPEN) {
            if (elapsed >= cooldownMillis) {
                if (state.compareAndSet(State.OPEN, State.HALF_OPEN)) {
                    lastStateChangeTime.set(now);
                    log.info("Circuit breaker transitioned from OPEN to HALF_OPEN (cooldown {}ms elapsed)", elapsed);
                    return true;
                }
            }
            return false;
        }

        // HALF_OPEN allows probe
        return true;
    }

    public void recordSuccess() {
        consecutiveFailures.set(0);
        State previous = state.getAndSet(State.CLOSED);
        if (previous != State.CLOSED) {
            lastStateChangeTime.set(System.currentTimeMillis());
            log.info("Circuit breaker closed after successful upstream provider response");
        }
    }

    public void recordFailure() {
        int failures = consecutiveFailures.incrementAndGet();
        long now = System.currentTimeMillis();

        if (state.get() == State.HALF_OPEN) {
            state.set(State.OPEN);
            lastStateChangeTime.set(now);
            log.warn("Probe request in HALF_OPEN failed; circuit breaker tripped back to OPEN");
            return;
        }

        if (failures >= failureThreshold && state.compareAndSet(State.CLOSED, State.OPEN)) {
            lastStateChangeTime.set(now);
            log.error("Circuit breaker tripped to OPEN after {} consecutive provider failures", failures);
        }
    }

    public State getState() {
        // Evaluate timeout expiration if OPEN
        if (state.get() == State.OPEN && (System.currentTimeMillis() - lastStateChangeTime.get() >= cooldownMillis)) {
            state.compareAndSet(State.OPEN, State.HALF_OPEN);
            lastStateChangeTime.set(System.currentTimeMillis());
        }
        return state.get();
    }

    public void reset() {
        state.set(State.CLOSED);
        consecutiveFailures.set(0);
        lastStateChangeTime.set(System.currentTimeMillis());
    }
}

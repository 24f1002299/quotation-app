package com.quotapp.api.repository;

import com.quotapp.api.dto.FeedbackDto;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * Day 21 — In-memory correction-feedback store, scoped by user ID.
 * Mirrors the Supabase {@code edit_feedback} table: append-only from the
 * client; deletion/anonymisation happens only when its quote is deleted.
 */
@Repository
public class FeedbackRepository {

    // userId -> (feedbackId -> FeedbackDto)
    private final ConcurrentHashMap<String, Map<String, FeedbackDto>> store = new ConcurrentHashMap<>();

    public FeedbackDto save(String userId, FeedbackDto feedback) {
        if (userId == null || feedback == null) {
            throw new IllegalArgumentException("userId and feedback cannot be null");
        }
        String id = (feedback.id() != null && !feedback.id().isBlank())
            ? feedback.id()
            : UUID.randomUUID().toString();
        Instant createdAt = feedback.createdAt() != null ? feedback.createdAt() : Instant.now();
        FeedbackDto saved = new FeedbackDto(
            id,
            feedback.quoteIdHash().trim().toLowerCase(),
            feedback.trade().trim().toLowerCase(),
            feedback.catalogItemId(),
            feedback.modelResult(),
            feedback.finalValue(),
            feedback.changedField().trim().toLowerCase(),
            createdAt
        );
        store.computeIfAbsent(userId, k -> new ConcurrentHashMap<>()).put(id, saved);
        return saved;
    }

    public List<FeedbackDto> findByUser(String userId) {
        if (userId == null) return Collections.emptyList();
        Map<String, FeedbackDto> map = store.get(userId);
        if (map == null) return Collections.emptyList();
        return map.values().stream()
            .sorted(Comparator.comparing(FeedbackDto::createdAt))
            .collect(Collectors.toList());
    }

    public List<FeedbackDto> findByQuoteHash(String userId, String quoteIdHash) {
        if (userId == null || quoteIdHash == null) return Collections.emptyList();
        return findByUser(userId).stream()
            .filter(f -> quoteIdHash.equalsIgnoreCase(f.quoteIdHash()))
            .collect(Collectors.toList());
    }

    /**
     * Day 21 deletion policy: deleting a quote removes its feedback rows.
     * Returns the number of removed records.
     */
    public int deleteByQuoteHash(String userId, String quoteIdHash) {
        if (userId == null || quoteIdHash == null) return 0;
        Map<String, FeedbackDto> map = store.get(userId);
        if (map == null) return 0;
        List<String> toRemove = map.values().stream()
            .filter(f -> quoteIdHash.equalsIgnoreCase(f.quoteIdHash()))
            .map(FeedbackDto::id)
            .toList();
        toRemove.forEach(map::remove);
        return toRemove.size();
    }

    /**
     * Anonymisation alternative (for exports/retention): redacts model/final
     * values while keeping trade + changed-field counts.
     */
    public int anonymizeByQuoteHash(String userId, String quoteIdHash) {
        if (userId == null || quoteIdHash == null) return 0;
        Map<String, FeedbackDto> map = store.get(userId);
        if (map == null) return 0;
        int count = 0;
        for (Map.Entry<String, FeedbackDto> e : new ArrayList<>(map.entrySet())) {
            FeedbackDto f = e.getValue();
            if (quoteIdHash.equalsIgnoreCase(f.quoteIdHash())) {
                map.put(e.getKey(), new FeedbackDto(
                    f.id(), f.quoteIdHash(), f.trade(), f.catalogItemId(),
                    "[redacted]", "[redacted]", f.changedField(), f.createdAt()));
                count++;
            }
        }
        return count;
    }

    public boolean existsForOtherUser(String currentUserId, String feedbackId) {
        if (feedbackId == null) return false;
        for (Map.Entry<String, Map<String, FeedbackDto>> entry : store.entrySet()) {
            if (!entry.getKey().equals(currentUserId) && entry.getValue().containsKey(feedbackId)) {
                return true;
            }
        }
        return false;
    }
}

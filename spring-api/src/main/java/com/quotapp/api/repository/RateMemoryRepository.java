package com.quotapp.api.repository;

import com.quotapp.api.dto.RateMemoryItemDto;
import org.springframework.stereotype.Repository;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Repository for contractor rate memory.
 * Thread-safe and scoped by user ID.
 */
@Repository
public class RateMemoryRepository {

    // userId -> Map<catalogItemId, RateMemoryItemDto>
    private final ConcurrentHashMap<String, Map<String, RateMemoryItemDto>> userRates = new ConcurrentHashMap<>();

    public List<RateMemoryItemDto> findByUserId(String userId) {
        if (userId == null) {
            return Collections.emptyList();
        }
        Map<String, RateMemoryItemDto> rates = userRates.get(userId);
        if (rates == null) {
            return Collections.emptyList();
        }
        return new ArrayList<>(rates.values());
    }

    public List<RateMemoryItemDto> saveAll(String userId, List<RateMemoryItemDto> items) {
        if (userId == null || items == null) {
            return Collections.emptyList();
        }
        Map<String, RateMemoryItemDto> rates = userRates.computeIfAbsent(userId, k -> new ConcurrentHashMap<>());
        for (RateMemoryItemDto item : items) {
            if (item.catalogItemId() != null && !item.catalogItemId().isBlank()) {
                rates.put(item.catalogItemId().toLowerCase(Locale.ROOT), item);
            }
        }
        return new ArrayList<>(rates.values());
    }
}

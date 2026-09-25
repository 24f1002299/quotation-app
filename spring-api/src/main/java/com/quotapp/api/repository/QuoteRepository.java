package com.quotapp.api.repository;

import com.quotapp.api.dto.PageResponse;
import com.quotapp.api.dto.QuoteDto;
import com.quotapp.api.exception.QuoteVersionConflictException;
import org.springframework.stereotype.Repository;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.Year;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Day 15 & Day 16 — Repository for contractor quotations.
 * Scoped by user ID and protects idempotency using immutable client-supplied keys.
 */
@Repository
public class QuoteRepository {

    private final SecureRandom random = new SecureRandom();

    // userId -> Map<quoteId, QuoteDto>
    private final ConcurrentHashMap<String, Map<String, QuoteDto>> userQuotes = new ConcurrentHashMap<>();

    // userId:idempotencyKey -> quoteId
    private final ConcurrentHashMap<String, String> idempotencyIndex = new ConcurrentHashMap<>();

    public QuoteRepository() {
        seedCrossUserRecords();
    }

    private void seedCrossUserRecords() {
        String userA = "00000000-0000-0000-0000-000000000001";
        String userB = "00000000-0000-0000-0000-000000000002";
        String userAQuoteId = "aaaaaaaa-0000-0000-0000-000000000001";
        String userBQuoteId = "bbbbbbbb-0000-0000-0000-000000000002";

        save(userA, new QuoteDto(
            userAQuoteId,
            "idemp_user_a_1",
            "Q-2026-A101",
            "ready",
            "tiling",
            "Client A",
            "9876543210",
            "Flat 101, User A Site",
            18,
            100000L,
            18000L,
            118000L,
            "2026-09-25",
            15,
            50,
            "50% advance",
            "Test notes A",
            List.of("Term 1", "Term 2"),
            Collections.emptyList(),
            1,
            Instant.now(),
            Instant.now()
        ));

        save(userB, new QuoteDto(
            userBQuoteId,
            "idemp_user_b_2",
            "Q-2026-B202",
            "ready",
            "painting",
            "Client B",
            "9822054321",
            "Bungalow B, User B Site",
            null,
            200000L,
            0L,
            200000L,
            "2026-09-25",
            30,
            null,
            "",
            "Test notes B",
            List.of("Term B"),
            Collections.emptyList(),
            1,
            Instant.now(),
            Instant.now()
        ));
    }

    public Optional<QuoteDto> findById(String userId, String quoteId) {
        if (userId == null || quoteId == null) {
            return Optional.empty();
        }
        Map<String, QuoteDto> quotes = userQuotes.get(userId);
        if (quotes == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(quotes.get(quoteId));
    }

    public boolean existsForOtherUser(String currentUserId, String quoteId) {
        if (quoteId == null) return false;
        for (Map.Entry<String, Map<String, QuoteDto>> entry : userQuotes.entrySet()) {
            if (!entry.getKey().equals(currentUserId) && entry.getValue().containsKey(quoteId)) {
                return true;
            }
        }
        return false;
    }

    public Optional<QuoteDto> findByIdempotencyKey(String userId, String idempotencyKey) {
        if (userId == null || idempotencyKey == null) {
            return Optional.empty();
        }
        String indexKey = userId + ":" + idempotencyKey.trim();
        String quoteId = idempotencyIndex.get(indexKey);
        if (quoteId == null) {
            return Optional.empty();
        }
        return findById(userId, quoteId);
    }

    public List<QuoteDto> findAllByUserId(String userId) {
        if (userId == null) return Collections.emptyList();
        Map<String, QuoteDto> quotes = userQuotes.get(userId);
        if (quotes == null) return Collections.emptyList();
        List<QuoteDto> list = new ArrayList<>(quotes.values());
        list.sort((a, b) -> b.createdAt().compareTo(a.createdAt()));
        return list;
    }

    public PageResponse<QuoteDto> searchQuotes(String userId, int page, int size, String client, String status, String date) {
        if (userId == null) {
            return PageResponse.of(Collections.emptyList(), page, size, 0);
        }
        Map<String, QuoteDto> quotes = userQuotes.get(userId);
        if (quotes == null || quotes.isEmpty()) {
            return PageResponse.of(Collections.emptyList(), page, size, 0);
        }

        List<QuoteDto> all = new ArrayList<>(quotes.values());
        all.sort((a, b) -> {
            Instant bTime = b.createdAt() != null ? b.createdAt() : Instant.MIN;
            Instant aTime = a.createdAt() != null ? a.createdAt() : Instant.MIN;
            return bTime.compareTo(aTime);
        });

        List<QuoteDto> filtered = all.stream().filter(q -> {
            if (client != null && !client.isBlank()) {
                if (q.clientName() == null || !q.clientName().toLowerCase().contains(client.toLowerCase().trim())) {
                    return false;
                }
            }
            if (status != null && !status.isBlank()) {
                if (q.status() == null || !q.status().equalsIgnoreCase(status.trim())) {
                    return false;
                }
            }
            if (date != null && !date.isBlank()) {
                String dTrim = date.trim();
                String effectiveDate = (q.quoteDate() != null && !q.quoteDate().isBlank())
                    ? q.quoteDate()
                    : (q.createdAt() != null ? q.createdAt().toString() : "");
                if (!effectiveDate.contains(dTrim)) {
                    return false;
                }
            }
            return true;
        }).toList();

        long totalElements = filtered.size();
        int safePage = Math.max(0, page);
        int safeSize = size > 0 ? size : 10;
        int fromIndex = Math.min(safePage * safeSize, filtered.size());
        int toIndex = Math.min(fromIndex + safeSize, filtered.size());
        List<QuoteDto> pagedContent = filtered.subList(fromIndex, toIndex);

        return PageResponse.of(pagedContent, safePage, safeSize, totalElements);
    }

    public QuoteDto save(String userId, QuoteDto quote) {
        if (userId == null || quote == null) {
            throw new IllegalArgumentException("userId and quote cannot be null");
        }
        String idempKey = quote.idempotencyKey() != null ? quote.idempotencyKey().trim() : null;
        if (idempKey != null && !idempKey.isBlank()) {
            Optional<QuoteDto> existingByIdemp = findByIdempotencyKey(userId, idempKey);
            if (existingByIdemp.isPresent()) {
                // Idempotent: server accepts each idempotency key once and returns existing
                return existingByIdemp.get();
            }
        }

        String quoteId = (quote.id() != null && !quote.id().isBlank())
            ? quote.id()
            : UUID.randomUUID().toString();

        Optional<QuoteDto> existingForQuoteId = findById(userId, quoteId);
        Instant now = Instant.now();
        Instant createdAt = now;
        int targetVersion = 1;
        String displayNumber = quote.displayNumber();

        if (existingForQuoteId.isPresent()) {
            QuoteDto existing = existingForQuoteId.get();
            createdAt = existing.createdAt();
            if (displayNumber == null || displayNumber.isBlank()) {
                displayNumber = existing.displayNumber();
            }
            int incomingVersion = quote.version() != null ? quote.version() : 1;
            int existingVersion = existing.version() != null ? existing.version() : 1;
            if (incomingVersion < existingVersion) {
                // Same quote was updated on another device: version conflict
                throw new QuoteVersionConflictException(
                    "Quote was modified on another device (server version: " + existingVersion + ", device version: " + incomingVersion + ")",
                    existing
                );
            }
            targetVersion = existingVersion + 1;
        } else {
            targetVersion = (quote.version() != null && quote.version() > 0) ? quote.version() : 1;
            if (quote.createdAt() != null) {
                createdAt = quote.createdAt();
            }
            if (displayNumber == null || displayNumber.isBlank()) {
                displayNumber = generateDisplayNumber();
            }
        }

        QuoteDto saved = new QuoteDto(
            quoteId,
            idempKey != null ? idempKey : quoteId,
            displayNumber,
            quote.status() != null ? quote.status() : "ready",
            quote.trade() != null ? quote.trade() : "tiling",
            quote.clientName() != null ? quote.clientName() : "Client",
            quote.clientPhone(),
            quote.siteAddress(),
            quote.gstPercent(),
            quote.subtotalPaise() != null ? quote.subtotalPaise() : 0L,
            quote.gstPaise() != null ? quote.gstPaise() : 0L,
            quote.grandTotalPaise() != null ? quote.grandTotalPaise() : 0L,
            quote.quoteDate() != null ? quote.quoteDate() : now.toString(),
            quote.validityDays() != null ? quote.validityDays() : 15,
            quote.advancePercent(),
            quote.advanceText(),
            quote.notes(),
            quote.terms() != null ? quote.terms() : Collections.emptyList(),
            quote.lineItems() != null ? quote.lineItems() : Collections.emptyList(),
            targetVersion,
            createdAt,
            now
        );

        Map<String, QuoteDto> quotes = userQuotes.computeIfAbsent(userId, k -> new ConcurrentHashMap<>());
        quotes.put(quoteId, saved);

        if (idempKey != null && !idempKey.isBlank()) {
            idempotencyIndex.put(userId + ":" + idempKey, quoteId);
        }

        return saved;
    }

    public boolean delete(String userId, String quoteId) {
        if (userId == null || quoteId == null) return false;
        Map<String, QuoteDto> quotes = userQuotes.get(userId);
        if (quotes == null) return false;
        QuoteDto removed = quotes.remove(quoteId);
        if (removed != null && removed.idempotencyKey() != null) {
            idempotencyIndex.remove(userId + ":" + removed.idempotencyKey());
            return true;
        }
        return removed != null;
    }

    private String generateDisplayNumber() {
        int year = Year.now().getValue();
        char[] chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".toCharArray();
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 4; i++) {
            sb.append(chars[random.nextInt(chars.length)]);
        }
        return "Q-" + year + "-" + sb;
    }
}

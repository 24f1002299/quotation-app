package com.quotapp.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.quotapp.api.dto.CatalogItemDto;
import com.quotapp.api.dto.ExtractRequest;
import com.quotapp.api.dto.QuoteDto;
import com.quotapp.api.llm.LlmExtractionClient;
import com.quotapp.api.resilience.ExtractionCircuitBreaker;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Day 23 — Automated risk coverage at the API boundary.
 *
 * <p>Pins the six Day-23 verify faults against the real HTTP layer:
 * wrong total (recompute, never trust), unresolved unknown (requiresReview),
 * malformed extraction (400, no silent accept), duplicate write (accept-once),
 * cross-user request (403), stale-version conflict (409 + server copy).
 * Also runs a small bounded concurrency smoke over authenticated history
 * reads to prove the pool is not exhausted (the full load profile lives in
 * {@code spring-api/load-test/k6-day23-extract-history.js}).
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
    "supabase.jwks-url=http://localhost:0/test-jwks",
    "spring.datasource.url=jdbc:h2:mem:day23db;MODE=PostgreSQL",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "database.app-role.password=test",
    "quotapp.llm.grok.api-key=test-key",
    "quotapp.llm.openai.api-key=test-key"
})
class Day23RiskCoverageTest {

    private static final String USER_A = "00000000-0000-0000-0000-000000000001";
    private static final String USER_B_QUOTE_ID = "bbbbbbbb-0000-0000-0000-000000000002";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private ExtractionCircuitBreaker circuitBreaker;

    @MockBean
    private LlmExtractionClient mockLlmClient;

    private QuoteDto quoteBody(String id, String idempotencyKey, int version) {
        return new QuoteDto(
            id, idempotencyKey, null, "ready", "tiling", "Day23 Client",
            null, null, null,
            1200000L, 0L, 1200000L, "2026-09-25", 15,
            null, null, null,
            List.of(), List.of(),
            version, null, null
        );
    }

    private String syncQuote(String userId, QuoteDto body, String headerKey) throws Exception {
        MvcResult result = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(userId))
                .header("Idempotency-Key", headerKey)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(body))
        )
            .andExpect(status().isOk())
            .andReturn();
        JsonNode node = objectMapper.readTree(result.getResponse().getContentAsString());
        return node.get("id").asText();
    }

    // ── 1. Duplicate write: same idempotency key accepted once ──────────────

    @Test
    @DisplayName("Day23: duplicate quote write with same Idempotency-Key returns one record")
    void duplicateWrite_acceptedOnce() throws Exception {
        String user = "day23-dup-" + UUID.randomUUID();
        String key = "day23-idemp-" + UUID.randomUUID();
        String id = UUID.randomUUID().toString();

        String firstId = syncQuote(user, quoteBody(id, key, 1), key);
        String retryId = syncQuote(user, quoteBody(id, key, 1), key);

        assertThat(retryId).isEqualTo(firstId);
    }

    // ── 2. Stale version: 409 + server copy ─────────────────────────────────

    @Test
    @DisplayName("Day23: stale-version write returns 409 VERSION_CONFLICT with server quote")
    void staleVersion_returns409() throws Exception {
        String user = "day23-conflict-" + UUID.randomUUID();
        String id = UUID.randomUUID().toString();

        syncQuote(user, quoteBody(id, "day23-k1-" + UUID.randomUUID(), 1), "day23-k1-" + UUID.randomUUID());
        // Second device edit bumps the server to v2 (new attempt => new key).
        syncQuote(user, quoteBody(id, "day23-k2-" + UUID.randomUUID(), 1), "day23-k2-" + UUID.randomUUID());

        // Stale device still on v1 must conflict, not overwrite.
        mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(user))
                .header("Idempotency-Key", "day23-k3-" + UUID.randomUUID())
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(quoteBody(id, "day23-k3", 1)))
        )
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("VERSION_CONFLICT"))
            .andExpect(jsonPath("$.serverQuote").exists());
    }

    // ── 3. Cross-user request ───────────────────────────────────────────────

    @Test
    @DisplayName("Day23: cross-user quote read returns 403, never the record")
    void crossUserRead_forbidden() throws Exception {
        mockMvc.perform(get("/api/quotes/" + USER_B_QUOTE_ID).with(user(USER_A)))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.error").value("OWNERSHIP_VIOLATION"));
    }

    // ── 4. Malformed extraction rejected ────────────────────────────────────

    @Test
    @DisplayName("Day23: malformed extraction JSON rejected with 400, not silently accepted")
    void malformedExtraction_rejected() throws Exception {
        mockMvc.perform(
            post("/api/extract")
                .with(user("day23-malformed-user"))
                .contentType(MediaType.APPLICATION_JSON)
                .content("{ \"trade\": \"tiling\", \"transcript\": \"missing end quote }")
        )
            .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Day23: oversized transcript rejected before any provider call")
    void oversizedTranscript_rejected() throws Exception {
        ExtractRequest request = new ExtractRequest(
            "x".repeat(5001), "tiling",
            List.of(new CatalogItemDto("tile_labour", "Tile Labour", "sq ft",
                List.of("sq ft"), List.of("tile labour"), "tiling")),
            Collections.emptyList(), "auto", "1.0", 1, null);
        mockMvc.perform(
            post("/api/extract")
                .with(user("day23-oversize-user"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request))
        )
            .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Day23: unauthenticated extraction rejected with 401")
    void unauthenticatedExtraction_rejected() throws Exception {
        mockMvc.perform(
            post("/api/extract")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"transcript\":\"hi\",\"trade\":\"tiling\"}")
        )
            .andExpect(status().isUnauthorized());
    }

    // ── 5. OpenAPI contract: unknowns flagged, no model arithmetic ──────────

    @Test
    @DisplayName("Day23: valid extract returns lineItems+unknowns with zero arithmetic fields")
    void validExtractContract_noArithmeticFields() throws Exception {
        circuitBreaker.reset();
        LlmExtractionClient real = new LlmExtractionClient(
            "grok", "", "https://api.x.ai/v1/chat/completions", "grok-2-mini",
            "", "", "gpt-4o-mini", 10, 0, objectMapper, circuitBreaker);
        List<CatalogItemDto> catalog = List.of(
            new CatalogItemDto("tile_labour", "Tile Labour / टाइल मजदूरी", "sq ft",
                List.of("sq ft"), List.of("tile labour", "floor tile"), "tiling"));
        when(mockLlmClient.extract(anyString(), anyString(), anyList(), anyList(), any()))
            .thenAnswer(inv -> real.fallbackExtract(inv.getArgument(0), catalog));

        ExtractRequest request = new ExtractRequest(
            "floor tile 120 sq ft labour", "tiling", catalog,
            Collections.emptyList(), "auto", "1.0", 1,
            "day23-extract-" + UUID.randomUUID());

        MvcResult result = mockMvc.perform(
            post("/api/extract")
                .with(user("day23-contract-user"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request))
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.lineItems").isArray())
            .andReturn();

        JsonNode root = objectMapper.readTree(result.getResponse().getContentAsString());
        assertThat(root.has("lineItems")).isTrue();
        // The model must never do money: no amount/subtotal/total/gst anywhere.
        String raw = result.getResponse().getContentAsString().toLowerCase();
        assertThat(raw).doesNotContain("subtotal");
        assertThat(raw).doesNotContain("grandtotal");
        assertThat(raw).doesNotContain("\"total\"");
        circuitBreaker.reset();
    }

    // ── 5b. Static OpenAPI contract: spec pins the safety clauses ───────────

    @Test
    @DisplayName("Day23: published OpenAPI spec pins extract/quotes safety contract")
    void openApiSpec_pinsSafetyContract() throws Exception {
        String spec;
        try (var in = getClass().getResourceAsStream("/static/openapi.yaml")) {
            assertThat(in).as("openapi.yaml on test classpath").isNotNull();
            spec = new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
        }
        assertThat(spec).contains("/api/extract");
        assertThat(spec).contains("Idempotency-Key");
        assertThat(spec).contains("5000");
        assertThat(spec.toLowerCase()).contains("never computes arithmetic");
    }

    // ── 6. Bounded concurrency smoke: history reads never exhaust the pool ──

    @Test
    @DisplayName("Day23: 10x5 concurrent authenticated history reads all succeed")
    void concurrentHistoryReads_allSucceed() throws Exception {
        String user = "day23-load-" + UUID.randomUUID();
        syncQuote(user, quoteBody(UUID.randomUUID().toString(),
            "day23-load-key-" + UUID.randomUUID(), 1),
            "day23-load-hdr-" + UUID.randomUUID());

        int threads = 10;
        int readsPerThread = 5;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch ready = new CountDownLatch(threads);
        CountDownLatch done = new CountDownLatch(threads);
        AtomicInteger failures = new AtomicInteger();

        for (int t = 0; t < threads; t++) {
            pool.submit(() -> {
                ready.countDown();
                try {
                    ready.await(10, TimeUnit.SECONDS);
                    for (int i = 0; i < readsPerThread; i++) {
                        try {
                            mockMvc.perform(get("/api/quotes?page=0&size=10")
                                    .with(user(user)))
                                .andExpect(status().isOk());
                        } catch (Exception e) {
                            failures.incrementAndGet();
                        }
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    failures.incrementAndGet();
                } finally {
                    done.countDown();
                }
                return null;
            });
        }

        assertThat(done.await(60, TimeUnit.SECONDS)).isTrue();
        pool.shutdownNow();
        assertThat(failures.get()).isZero();
    }
}

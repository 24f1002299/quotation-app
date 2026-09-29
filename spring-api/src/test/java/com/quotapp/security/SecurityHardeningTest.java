package com.quotapp.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quotapp.api.dto.FeedbackDto;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.UUID;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Day 22 — Security hardening verification.
 *
 * <p>Covers the pilot gate: unauthenticated requests are rejected, validation
 * refuses non-hash quote IDs and bad enums, cross-user storage access is
 * denied, and error responses never leak provider secrets.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
    "supabase.jwks-url=http://localhost:0/test-jwks",
    "spring.datasource.url=jdbc:h2:mem:testdb;MODE=PostgreSQL",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "database.app-role.password=test"
})
class SecurityHardeningTest {

    private static final String USER_A = "00000000-0000-0000-0000-000000000001";
    private static final String USER_B = "00000000-0000-0000-0000-000000000002";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    // ─── Unauthenticated → 401 ──────────────────────────────────────────

    @Test
    @DisplayName("Unauthenticated: GET /api/quotes → 401")
    void unauthenticatedQuotesRejected() throws Exception {
        mockMvc.perform(get("/api/quotes"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Unauthenticated: POST /api/feedback → 401")
    void unauthenticatedFeedbackRejected() throws Exception {
        mockMvc.perform(post("/api/feedback")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Unauthenticated: GET /api/storage/signed-url → 401")
    void unauthenticatedStorageRejected() throws Exception {
        mockMvc.perform(get("/api/storage/signed-url").param("path", USER_A + "/logo.png"))
            .andExpect(status().isUnauthorized());
    }

    // ─── Validation ─────────────────────────────────────────────────────

    @Test
    @DisplayName("Feedback with raw quote ID (not SHA-256 hex) → 400, no secret leak")
    void feedbackRawQuoteIdRejected() throws Exception {
        FeedbackDto bad = new FeedbackDto(
            null, "quote-uuid-1", "tiling", null, "a", "b", "rate", Instant.now());
        mockMvc.perform(post("/api/feedback").with(user(USER_A))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(bad)))
            .andExpect(status().isBadRequest())
            .andExpect(content().string(org.hamcrest.Matchers.not(
                org.hamcrest.Matchers.containsString("OPENAI"))));
    }

    @Test
    @DisplayName("Feedback with invalid changedField → 400")
    void feedbackBadFieldRejected() throws Exception {
        String hash = "a".repeat(64);
        FeedbackDto bad = new FeedbackDto(
            null, hash, "tiling", null, "a", "b", "audio", Instant.now());
        mockMvc.perform(post("/api/feedback").with(user(USER_A))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(bad)))
            .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Transcribe with unsupported media type → 415")
    void transcribeUnsupportedMediaRejected() throws Exception {
        byte[] tiny = new byte[128];
        mockMvc.perform(multipart("/api/transcribe").file(
                    new org.springframework.mock.web.MockMultipartFile(
                        "file", "evil.exe", "application/x-msdownload", tiny))
                .with(user(USER_A)))
            .andExpect(result ->
                org.assertj.core.api.Assertions.assertThat(
                    java.util.Set.of(400, 415).contains(
                        result.getResponse().getStatus())).isTrue());
    }

    // ─── Cross-user storage ─────────────────────────────────────────────

    @Test
    @DisplayName("User A cannot mint signed URL for User B path → 403/404")
    void crossUserStorageDenied() throws Exception {
        mockMvc.perform(get("/api/storage/signed-url")
                    .param("path", USER_B + "/logo.png")
                    .with(user(USER_A)))
            .andExpect(result ->
                org.assertj.core.api.Assertions.assertThat(
                    java.util.Set.of(403, 404).contains(
                        result.getResponse().getStatus())).isTrue());
    }

    // ─── Dev bypass default ─────────────────────────────────────────────

    @Test
    @DisplayName("Dev JWT bypass is disabled by default")
    void devBypassDisabledByDefault() {
        org.assertj.core.api.Assertions.assertThat(
            new SupabaseJwtFilterDevBypassProbe().isBypassEnabledByDefault())
            .isFalse();
    }

    /** Reflective probe: the flag's default must be false. */
    static class SupabaseJwtFilterDevBypassProbe {
        boolean isBypassEnabledByDefault() {
            try {
                var field = SupabaseJwtFilter.class.getDeclaredField("devBypassEnabled");
                var ann = field.getAnnotation(org.springframework.beans.factory.annotation.Value.class);
                return ann != null && ann.value().contains(":true");
            } catch (Exception e) {
                return true; // fail closed: probe error counts as enabled
            }
        }
    }
}

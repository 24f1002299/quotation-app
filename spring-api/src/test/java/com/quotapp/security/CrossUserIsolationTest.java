package com.quotapp.security;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Cross-user isolation integration tests — Spring API layer.
 *
 * <p>These tests verify that a request authenticated as User A cannot read, write,
 * update, or delete User B's resources through any API endpoint.
 *
 * <p>Test strategy:
 * <ul>
 *   <li>MockMvc requests carry a User A JWT via WithMockJwt or custom header.
 *   <li>Requests target endpoints containing User B's resource IDs.
 *   <li>Expected result: 403 Forbidden or 404 Not Found (never 200).
 * </ul>
 *
 * NOTE: These tests require a real DB or test-doubles wired to enforce ownership.
 * The service layer must call UserContext.require() and filter by userId.
 * Below we use MockMvc + test Spring Security config that injects a user identity.
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
class CrossUserIsolationTest {

    // User A and User B UUIDs — match seed.sql
    static final String USER_A = "00000000-0000-0000-0000-000000000001";
    static final String USER_B = "00000000-0000-0000-0000-000000000002";
    static final String USER_B_QUOTE_ID = "bbbbbbbb-0000-0000-0000-000000000002";
    static final String USER_B_PROFILE_PATH = "/api/profiles/" + USER_B;

    @Autowired
    private MockMvc mockMvc;

    // ─── Helper ───────────────────────────────────────────────────────────────

    /**
     * Returns an Authorization header value for the given userId.
     * In real integration tests this would use a test JWT signed with a known key.
     * Here we use Spring Security's @WithMockUser equivalent via a helper.
     */
    private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder
    asUser(org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder req,
           String userId) {
        return req.with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user(userId));
    }

    // ─── Profile isolation ────────────────────────────────────────────────────

    @Test
    @DisplayName("User A: GET User B profile → 403 or 404")
    void userA_cannotGetUserBProfile() throws Exception {
        mockMvc.perform(
            asUser(get(USER_B_PROFILE_PATH), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    @Test
    @DisplayName("User A: PUT User B profile → 403 or 404")
    void userA_cannotUpdateUserBProfile() throws Exception {
        mockMvc.perform(
            asUser(put(USER_B_PROFILE_PATH)
                .contentType("application/json")
                .content("{\"business_name\": \"Hacked\"}"), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    // ─── Quote isolation ──────────────────────────────────────────────────────

    @Test
    @DisplayName("User A: GET User B quote → 403 or 404")
    void userA_cannotGetUserBQuote() throws Exception {
        mockMvc.perform(
            asUser(get("/api/quotes/" + USER_B_QUOTE_ID), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    @Test
    @DisplayName("User A: PATCH User B quote → 403 or 404")
    void userA_cannotPatchUserBQuote() throws Exception {
        mockMvc.perform(
            asUser(patch("/api/quotes/" + USER_B_QUOTE_ID)
                .contentType("application/json")
                .content("{\"client_name\": \"Evil Client\"}"), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    @Test
    @DisplayName("User A: DELETE User B quote → 403 or 404")
    void userA_cannotDeleteUserBQuote() throws Exception {
        mockMvc.perform(
            asUser(delete("/api/quotes/" + USER_B_QUOTE_ID), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    // ─── Line items isolation ─────────────────────────────────────────────────

    @Test
    @DisplayName("User A: GET User B quote line items → 403 or 404")
    void userA_cannotGetUserBLineItems() throws Exception {
        mockMvc.perform(
            asUser(get("/api/quotes/" + USER_B_QUOTE_ID + "/items"), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    // ─── Rate memory isolation ────────────────────────────────────────────────

    @Test
    @DisplayName("User A: GET User B rate memory → 403 or 404")
    void userA_cannotGetUserBRateMemory() throws Exception {
        mockMvc.perform(
            asUser(get("/api/rates/" + USER_B), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    // ─── Storage object isolation ─────────────────────────────────────────────

    @Test
    @DisplayName("User A: GET User B storage file signed URL → 403 or 404")
    void userA_cannotGetUserBStorageSignedUrl() throws Exception {
        // The API generates signed URLs for storage objects.
        // User A must never get a signed URL for a path under User B's folder.
        String userBLogoPath = USER_B + "/logo.png";
        mockMvc.perform(
            asUser(get("/api/storage/signed-url?path=" + userBLogoPath), USER_A)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    // ─── Symmetric checks ────────────────────────────────────────────────────

    @Test
    @DisplayName("User B: GET User A quote → 403 or 404")
    void userB_cannotGetUserAQuote() throws Exception {
        String userAQuoteId = "aaaaaaaa-0000-0000-0000-000000000001";
        mockMvc.perform(
            asUser(get("/api/quotes/" + userAQuoteId), USER_B)
        ).andExpect(result ->
            assertForbiddenOrNotFound(result.getResponse().getStatus())
        );
    }

    // ─── Helper ───────────────────────────────────────────────────────────────

    private void assertForbiddenOrNotFound(int status) {
        if (status != 403 && status != 404) {
            throw new AssertionError(
                "Expected 403 or 404 for cross-user access, but got: " + status
            );
        }
    }
}

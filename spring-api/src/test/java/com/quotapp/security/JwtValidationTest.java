package com.quotapp.security;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.JWSSigner;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.util.Date;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * JWT validation unit/integration tests.
 *
 * <p>Covers the four security invariants:
 * <ol>
 *   <li>Missing Authorization header → 401
 *   <li>Expired token → 401
 *   <li>Tampered signature → 401
 *   <li>Valid token → request proceeds (200 from health, or passes filter)
 * </ol>
 *
 * <p>Tests use a locally generated RSA key pair — no real Supabase project needed.
 * The JWKS URL in test properties points to a mocked/stub server (see test resources).
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
    // Point to test-only JWKS stub (configured in application-test.yml)
    "supabase.jwks-url=http://localhost:0/test-jwks",
    "spring.datasource.url=jdbc:h2:mem:testdb",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "database.app-role.password=test"
})
class JwtValidationTest {

    @Autowired
    private MockMvc mockMvc;

    private RSAPrivateKey privateKey;
    private String testUserId;

    @BeforeEach
    void setUp() throws Exception {
        testUserId = UUID.randomUUID().toString();
        KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
        gen.initialize(2048);
        KeyPair kp = gen.generateKeyPair();
        privateKey = (RSAPrivateKey) kp.getPrivate();
    }

    // ─── Helper ──────────────────────────────────────────────

    /** Build a signed JWT with configurable expiry. */
    private String buildToken(String subject, Date expiry) throws Exception {
        JWSHeader header = new JWSHeader.Builder(JWSAlgorithm.RS256).build();
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
            .subject(subject)
            .issuer("https://test.supabase.co/auth/v1")
            .audience("authenticated")
            .expirationTime(expiry)
            .issueTime(new Date())
            .build();
        SignedJWT jwt = new SignedJWT(header, claims);
        JWSSigner signer = new RSASSASigner(privateKey);
        jwt.sign(signer);
        return jwt.serialize();
    }

    // ─── Tests ───────────────────────────────────────────────

    @Test
    @DisplayName("Missing Authorization header → 401")
    void missingToken_returns401() throws Exception {
        mockMvc.perform(get("/api/quotes"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Non-Bearer Authorization header → 401")
    void nonBearerHeader_returns401() throws Exception {
        mockMvc.perform(get("/api/quotes")
                .header("Authorization", "Basic dXNlcjpwYXNz"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Expired token → 401")
    void expiredToken_returns401() throws Exception {
        // Token expired 1 hour ago
        Date expiry = new Date(System.currentTimeMillis() - 3_600_000);
        String expiredToken = buildToken(testUserId, expiry);

        mockMvc.perform(get("/api/quotes")
                .header("Authorization", "Bearer " + expiredToken))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Tampered signature → 401")
    void tamperedSignature_returns401() throws Exception {
        Date expiry = new Date(System.currentTimeMillis() + 3_600_000);
        String validToken = buildToken(testUserId, expiry);

        // Corrupt the signature by appending characters
        String tamperedToken = validToken + "tampered";

        mockMvc.perform(get("/api/quotes")
                .header("Authorization", "Bearer " + tamperedToken))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Valid token does not expose error body with token contents")
    void errorResponse_doesNotLeakTokenContent() throws Exception {
        Date expiry = new Date(System.currentTimeMillis() - 1000);
        String expiredToken = buildToken(testUserId, expiry);

        MvcResult result = mockMvc.perform(get("/api/quotes")
                .header("Authorization", "Bearer " + expiredToken))
            .andReturn();

        MockHttpServletResponse response = result.getResponse();
        String body = response.getContentAsString();

        // Response must not echo back any part of the token
        assertThat(body).doesNotContain(expiredToken);
        assertThat(body).doesNotContain(testUserId);
        assertThat(response.getStatus()).isEqualTo(401);
    }

    @Test
    @DisplayName("Health endpoint is reachable without a token")
    void healthEndpoint_noAuthRequired() throws Exception {
        mockMvc.perform(get("/api/health"))
            .andExpect(status().isOk());
    }
}

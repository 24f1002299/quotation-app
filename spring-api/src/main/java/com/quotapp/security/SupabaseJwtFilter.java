package com.quotapp.security;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.jwk.source.RemoteJWKSet;
import com.nimbusds.jose.proc.JWSAlgorithmFamilyJWSKeySelector;
import com.nimbusds.jose.proc.JWSKeySelector;
import com.nimbusds.jose.proc.SecurityContext;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.proc.ConfigurableJWTProcessor;
import com.nimbusds.jwt.proc.DefaultJWTProcessor;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.net.URL;
import java.util.List;

/**
 * Validates Supabase JWTs on every incoming request using the published JWKS endpoint.
 *
 * <p>Design decisions:
 * <ul>
 *   <li>Fetches JWKS from {@code SUPABASE_JWKS_URL} — no hardcoded secret required.
 *   <li>Supports ES256 (ECC P-256 — Supabase current default) and RS256 (legacy).
 *   <li>Rejects tokens with missing/expired/tampered signatures with HTTP 401.
 *   <li>On success, stores the authenticated {@code userId} in {@link UserContext}
 *       and sets a Spring {@link UsernamePasswordAuthenticationToken}.
 *   <li>The Supabase service-role key is NOT used here; we verify via the public key.
 * </ul>
 */
@Component
public class SupabaseJwtFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(SupabaseJwtFilter.class);

    private final ConfigurableJWTProcessor<SecurityContext> jwtProcessor;

    public SupabaseJwtFilter(@Value("${supabase.jwks-url}") String jwksUrl) throws Exception {
        String safeUrl = jwksUrl != null ? jwksUrl.replace(":0/", ":80/") : "http://localhost:8080";
        JWKSource<SecurityContext> jwkSource = new RemoteJWKSet<>(new URL(safeUrl));

        // Lazily select keys based on header without eager connection in constructor
        JWSKeySelector<SecurityContext> keySelector = (header, context) -> {
            try {
                return jwkSource.get(new com.nimbusds.jose.jwk.JWKSelector(com.nimbusds.jose.jwk.JWKMatcher.forJWSHeader(header)), context)
                    .stream()
                    .map(jwk -> {
                        try {
                            if (jwk instanceof com.nimbusds.jose.jwk.RSAKey rsaKey) {
                                return rsaKey.toRSAPublicKey();
                            } else if (jwk instanceof com.nimbusds.jose.jwk.ECKey ecKey) {
                                return ecKey.toECPublicKey();
                            }
                        } catch (Exception ignored) {}
                        return null;
                    })
                    .filter(java.util.Objects::nonNull)
                    .toList();
            } catch (Exception e) {
                log.debug("Could not resolve key from JWKS: {}", e.getMessage());
                return java.util.Collections.emptyList();
            }
        };

        jwtProcessor = new DefaultJWTProcessor<>();
        jwtProcessor.setJWSKeySelector(keySelector);
    }

    @Override
    protected void doFilterInternal(
        @NonNull HttpServletRequest request,
        @NonNull HttpServletResponse response,
        @NonNull FilterChain filterChain
    ) throws ServletException, IOException {

        String authHeader = request.getHeader("Authorization");

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            // No token — let SecurityConfig decide whether the path requires auth.
            filterChain.doFilter(request, response);
            return;
        }

        String token = authHeader.substring(7);

        try {
            JWTClaimsSet claims = jwtProcessor.process(token, null);

            // "sub" is the Supabase user UUID.
            String userId = claims.getSubject();
            if (userId == null || userId.isBlank()) {
                sendUnauthorized(response, "JWT missing sub claim");
                return;
            }

            // Store userId so service methods can enforce ownership checks.
            UserContext.set(userId);

            // Register authenticated principal with Spring Security.
            // We don't load a UserDetails object; the userId from JWT is the authority.
            UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(
                    userId,
                    null,
                    List.of(new SimpleGrantedAuthority("ROLE_USER"))
                );
            SecurityContextHolder.getContext().setAuthentication(auth);

            filterChain.doFilter(request, response);

        } catch (Exception ex) {
            // Log at debug level — don't emit token content to logs.
            log.debug("JWT validation failed: {}", ex.getMessage());
            sendUnauthorized(response, "Invalid or expired token");
        } finally {
            // Always clear the thread-local to prevent leaking across requests.
            UserContext.clear();
        }
    }

    private void sendUnauthorized(HttpServletResponse response, String reason) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        // Intentionally vague — do not echo token content back.
        response.getWriter().write("{\"error\":\"Unauthorized\"}");
        log.debug("Rejected request: {}", reason);
    }
}

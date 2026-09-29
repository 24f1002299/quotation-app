package com.quotapp.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

/**
 * Spring Security configuration.
 *
 * <p>The API is stateless (JWT per-request) — no sessions, no cookies.
 * The {@link SupabaseJwtFilter} runs before Spring's built-in auth filters.
 *
 * <p>Public endpoints (health check) are explicitly permitted.
 * Every other endpoint requires an authenticated principal.
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final SupabaseJwtFilter supabaseJwtFilter;
    private final RequestIdFilter requestIdFilter;
    private final List<String> allowedOrigins;

    public SecurityConfig(
        SupabaseJwtFilter supabaseJwtFilter,
        RequestIdFilter requestIdFilter,
        @org.springframework.beans.factory.annotation.Value("${quotapp.cors.allowed-origins:}") String allowedOriginsCsv
    ) {
        this.supabaseJwtFilter = supabaseJwtFilter;
        this.requestIdFilter = requestIdFilter;
        this.allowedOrigins = allowedOriginsCsv == null || allowedOriginsCsv.isBlank()
            ? List.of()
            : Arrays.stream(allowedOriginsCsv.split(",")).map(String::trim).filter(s -> !s.isEmpty()).toList();
    }

    /**
     * Day 22: restrictive CORS. Default is deny-all for browser origins
     * (the Android app is not a browser and sends no Origin).
     * Set {@code CORS_ALLOWED_ORIGINS=https://...} only for trusted web admin
     * origins. Credentials and wildcard origins are never allowed together.
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(allowedOrigins);
        config.setAllowedMethods(List.of("GET", "POST", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key", "X-Request-Id"));
        config.setExposedHeaders(List.of("X-Request-Id"));
        config.setAllowCredentials(false);
        config.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            // Stateless REST API — disable CSRF and sessions
            .csrf(csrf -> csrf.disable())
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            )
            // Public endpoints
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health", "/api/health", "/openapi.yaml", "/docs/**").permitAll()
                .anyRequest().authenticated()
            )
            // Return 401 Unauthorized for unauthenticated requests with structured format
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint((request, response, authException) -> {
                    response.setStatus(jakarta.servlet.http.HttpServletResponse.SC_UNAUTHORIZED);
                    response.setContentType("application/json");
                    String reqId = RequestIdFilter.getCurrentRequestId();
                    String json = String.format(
                        "{\"error\":\"UNAUTHORIZED\",\"message\":\"Authentication required\",\"requestId\":\"%s\",\"timestamp\":\"%s\"}",
                        reqId, java.time.Instant.now().toString()
                    );
                    response.getWriter().write(json);
                })
            )
            // RequestId filter runs first, then Supabase JWT filter
            .addFilterBefore(requestIdFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterBefore(supabaseJwtFilter, UsernamePasswordAuthenticationFilter.class)
            .build();
    }
}

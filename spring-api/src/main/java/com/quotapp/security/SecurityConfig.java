package com.quotapp.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

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

    public SecurityConfig(SupabaseJwtFilter supabaseJwtFilter, RequestIdFilter requestIdFilter) {
        this.supabaseJwtFilter = supabaseJwtFilter;
        this.requestIdFilter = requestIdFilter;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            // Stateless REST API — disable CSRF and sessions
            .csrf(csrf -> csrf.disable())
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

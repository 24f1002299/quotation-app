package com.quotapp.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * Filter that establishes an X-Request-Id for every incoming HTTP request.
 *
 * <p>Populates the SLF4J MDC with {@code requestId} so all downstream log lines
 * automatically include the correlation ID. Sets {@code X-Request-Id} on the response.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {

    public static final String REQUEST_ID_HEADER = "X-Request-Id";
    public static final String MDC_KEY = "requestId";

    @Override
    protected void doFilterInternal(
        @NonNull HttpServletRequest request,
        @NonNull HttpServletResponse response,
        @NonNull FilterChain filterChain
    ) throws ServletException, IOException {
        String requestId = request.getHeader(REQUEST_ID_HEADER);
        if (!StringUtils.hasText(requestId)) {
            requestId = UUID.randomUUID().toString();
        } else {
            // Sanitize header value to prevent header injection or log forging
            requestId = requestId.replaceAll("[^a-zA-Z0-9-_]", "").trim();
            if (requestId.isEmpty()) {
                requestId = UUID.randomUUID().toString();
            }
        }

        MDC.put(MDC_KEY, requestId);
        response.setHeader(REQUEST_ID_HEADER, requestId);

        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    /**
     * Helper to retrieve the current request ID from MDC or generate fallback.
     */
    public static String getCurrentRequestId() {
        String id = MDC.get(MDC_KEY);
        return (id != null && !id.isBlank()) ? id : UUID.randomUUID().toString();
    }
}

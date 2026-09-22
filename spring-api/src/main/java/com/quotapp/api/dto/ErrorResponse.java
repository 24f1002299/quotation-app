package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.quotapp.security.RequestIdFilter;

import java.time.Instant;
import java.util.List;

/**
 * Standard structured error payload adhering to RFC-7807 problem details style.
 *
 * <p>Never echoes internal stack traces, API keys, or raw provider secrets.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ErrorResponse(
    String error,
    String message,
    String requestId,
    String timestamp,
    List<FieldErrorDetail> details
) {
    public ErrorResponse(String error, String message) {
        this(error, message, RequestIdFilter.getCurrentRequestId(), Instant.now().toString(), null);
    }

    public ErrorResponse(String error, String message, List<FieldErrorDetail> details) {
        this(error, message, RequestIdFilter.getCurrentRequestId(), Instant.now().toString(), details);
    }

    public record FieldErrorDetail(
        String field,
        Object rejectedValue,
        String reason
    ) {}
}

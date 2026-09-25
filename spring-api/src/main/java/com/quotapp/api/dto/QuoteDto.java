package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.List;

/**
 * Top-level Quote DTO for quotation synchronization and storage.
 * Day 15: supports optional commercial terms, offline UUID identity,
 * and server-assigned human-readable display numbers.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record QuoteDto(
    String id,
    @NotBlank(message = "idempotencyKey is required")
    String idempotencyKey,
    String displayNumber,
    String status,
    String trade,
    @NotBlank(message = "clientName is required")
    String clientName,
    String clientPhone,
    String siteAddress,
    Integer gstPercent,
    Long subtotalPaise,
    Long gstPaise,
    Long grandTotalPaise,
    String quoteDate,
    Integer validityDays,
    Integer advancePercent,
    String advanceText,
    String notes,
    List<String> terms,
    List<QuoteLineItemDto> lineItems,
    Integer version,
    Instant createdAt,
    Instant updatedAt
) {
    public QuoteDto withDisplayNumber(String newDisplayNumber) {
        return new QuoteDto(
            id,
            idempotencyKey,
            newDisplayNumber,
            status,
            trade,
            clientName,
            clientPhone,
            siteAddress,
            gstPercent,
            subtotalPaise,
            gstPaise,
            grandTotalPaise,
            quoteDate,
            validityDays,
            advancePercent,
            advanceText,
            notes,
            terms,
            lineItems,
            version,
            createdAt,
            updatedAt
        );
    }
}

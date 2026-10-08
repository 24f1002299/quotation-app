package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.List;

/**
 * Top-level Quote DTO for quotation synchronization and storage.
 * Day 15: supports optional commercial terms, offline UUID identity,
 * and server-assigned human-readable display numbers.
 *
 * <p>Canonical name is {@code businessType}: a free-form business slug.
 * Legacy wire names {@code trade} and {@code business_type} are still
 * accepted on input.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record QuoteDto(
    String id,
    @NotBlank(message = "idempotencyKey is required")
    String idempotencyKey,
    String displayNumber,
    String status,
    @JsonProperty("businessType")
    @JsonAlias({"trade", "business_type"})
    String businessType,
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
            businessType,
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

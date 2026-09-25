package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Line item DTO for quotation synchronization and storage.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record QuoteLineItemDto(
    String description,
    Integer quantity,
    String unit,
    Long unitRatePaise,
    Long amountPaise,
    Double confidence,
    String uncertaintyNote,
    String sourceSpan,
    Boolean isUnknown,
    Boolean requiresReview,
    Boolean acknowledged
) {}

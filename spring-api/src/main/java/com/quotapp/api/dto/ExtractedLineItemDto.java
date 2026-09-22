package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * Extracted candidate line item.
 *
 * <p>STRICT INVARIANT: This contract strictly excludes all calculated arithmetic fields
 * (such as {@code amount}, {@code lineTotal}, {@code subtotal}, {@code grandTotal}, or {@code gst}).
 * Quotation arithmetic is performed deterministically by the client calculation engine,
 * NEVER by the extraction model.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public record ExtractedLineItemDto(
    @NotBlank(message = "catalogItemId is required")
    String catalogItemId,

    @NotBlank(message = "description is required")
    String description,

    @NotNull(message = "quantity is required")
    @Positive(message = "quantity must be positive")
    Double quantity,

    @NotBlank(message = "unit is required")
    @ValidContractorUnit(message = "unit must be a recognized contractor unit")
    String unit,

    Long unitRatePaise,

    @NotNull(message = "rateSource is required")
    RateSource rateSource,

    @NotNull(message = "confidence is required")
    @DecimalMin("0.0")
    @DecimalMax("1.0")
    Double confidence,

    SourceSpan sourceSpan,

    String uncertaintyNote
) {}

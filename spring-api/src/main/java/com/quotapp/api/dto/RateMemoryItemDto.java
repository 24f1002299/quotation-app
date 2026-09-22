package com.quotapp.api.dto;

import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * Contractor's saved per-item rate memory passed to the extraction endpoint.
 */
public record RateMemoryItemDto(
    @NotBlank(message = "catalogItemId is required in rate memory")
    String catalogItemId,

    @NotBlank(message = "unit is required in rate memory")
    @ValidContractorUnit(message = "unit in rateMemory must be a recognized contractor unit")
    String unit,

    @NotNull(message = "unitRatePaise is required")
    @Min(value = 0, message = "unitRatePaise cannot be negative")
    Long unitRatePaise,

    String trade
) {}

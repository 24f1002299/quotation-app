package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * Saved per-item rate passed to the extraction endpoint, for ANY business
 * domain.
 *
 * <p>Canonical names are {@code serviceItemId} (the user's own service id)
 * and {@code businessType} (free-text slug). Legacy wire names
 * {@code catalogItemId} and {@code trade} are still accepted on input.
 */
public record RateMemoryItemDto(
    @NotBlank(message = "serviceItemId is required in rate memory")
    @JsonAlias({"catalogItemId", "catalog_item_id"})
    String serviceItemId,

    @NotBlank(message = "unit is required in rate memory")
    @ValidContractorUnit(message = "unit in rateMemory must be a recognized contractor unit")
    String unit,

    @NotNull(message = "unitRatePaise is required")
    @Min(value = 0, message = "unitRatePaise cannot be negative")
    Long unitRatePaise,

    @JsonAlias({"trade", "business_type"})
    String businessType
) {}

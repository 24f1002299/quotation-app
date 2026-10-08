package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.Collections;
import java.util.List;

/**
 * Extraction endpoint request payload for ANY business domain.
 *
 * <p>Canonical names are {@code businessType} (free-form business slug),
 * {@code serviceItems} (the user's own service list) and {@code savedRates}.
 * Legacy wire names are still accepted on input: {@code trade} for
 * {@code businessType}, {@code catalogEntries} for {@code serviceItems}, and
 * {@code rateMemory} for {@code savedRates}. Legacy item keys
 * ({@code displayName}/{@code defaultUnit}/{@code synonyms}) also bind via
 * {@link ServiceItemDto} aliases.
 *
 * <p>Use {@link #resolvedBusinessType()} and {@link #resolvedServiceItems()}
 * in new code: they expose the canonical names regardless of which wire
 * key the client sent.
 *
 * <p>Enforces a 5,000 character transcript ceiling to protect backend latency and tokens.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ExtractRequest(
    @NotBlank(message = "Transcript cannot be blank")
    @Size(max = 5000, message = "Transcript exceeds maximum allowed length of 5000 characters")
    String transcript,

    @NotBlank(message = "Business type is required")
    @JsonProperty("businessType")
    @JsonAlias({"trade", "business_type"})
    String businessType,

    @Valid
    @JsonProperty("serviceItems")
    @JsonAlias({"catalogEntries", "catalog_entries"})
    List<ServiceItemDto> serviceItems,

    @Valid
    @JsonProperty("savedRates")
    @JsonAlias({"rateMemory", "rate_memory"})
    List<RateMemoryItemDto> savedRates,

    @Pattern(regexp = "^(hi|mr|en|auto)?$", message = "Language hint must be 'hi', 'mr', 'en', or 'auto'")
    String language,

    @NotBlank(message = "schemaVersion is required")
    String schemaVersion,

    Integer version,

    String idempotencyKey
) {
    public ExtractRequest {
        if (serviceItems == null) {
            serviceItems = Collections.emptyList();
        }
        if (savedRates == null) {
            savedRates = Collections.emptyList();
        }
        if (version == null) {
            version = 1;
        }
        if (schemaVersion == null || schemaVersion.isBlank()) {
            schemaVersion = "1.0";
        }
    }

    /** Canonical business-type slug, regardless of which wire key was sent. */
    public String resolvedBusinessType() {
        return businessType;
    }

    /** Canonical service-list view, regardless of which wire key was sent. */
    public List<ServiceItemDto> resolvedServiceItems() {
        return serviceItems;
    }
}

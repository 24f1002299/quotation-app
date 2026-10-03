package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.Collections;
import java.util.List;

/**
 * Extraction endpoint request payload.
 *
 * <p>Canonical names are {@code businessType} and {@code serviceItems}
 * (the user's own service list for any business domain). Legacy wire names
 * are still accepted: {@code trade} for {@code businessType},
 * {@code catalogEntries} for {@code serviceItems}, and {@code rateMemory}
 * for {@code savedRates}.
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
    @JsonAlias("businessType")
    String trade,

    @Valid
    @JsonAlias("serviceItems")
    List<CatalogItemDto> catalogEntries,

    @Valid
    @JsonAlias("savedRates")
    List<RateMemoryItemDto> rateMemory,

    @Pattern(regexp = "^(hi|mr|en|auto)?$", message = "Language hint must be 'hi', 'mr', 'en', or 'auto'")
    String language,

    @NotBlank(message = "schemaVersion is required")
    String schemaVersion,

    Integer version,

    String idempotencyKey
) {
    public ExtractRequest {
        if (catalogEntries == null) {
            catalogEntries = Collections.emptyList();
        }
        if (rateMemory == null) {
            rateMemory = Collections.emptyList();
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
        return trade;
    }

    /** Canonical service-list view of the legacy catalog entries. */
    public List<ServiceItemDto> resolvedServiceItems() {
        return catalogEntries.stream().map(ServiceItemDto::fromCatalog).toList();
    }
}

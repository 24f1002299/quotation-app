package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.Collections;
import java.util.List;

/**
 * Extraction endpoint request payload.
 *
 * <p>Specifies the spoken transcript, selected contractor trade, relevant catalog entries,
 * rate memory, language hint, and schema version.
 *
 * <p>Enforces a 5,000 character transcript ceiling to protect backend latency and tokens.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ExtractRequest(
    @NotBlank(message = "Transcript cannot be blank")
    @Size(max = 5000, message = "Transcript exceeds maximum allowed length of 5000 characters")
    String transcript,

    @NotBlank(message = "Trade is required")
    @Pattern(regexp = "(?i)tiling|painting", message = "Trade must be 'tiling' or 'painting'")
    String trade,

    @NotEmpty(message = "catalogEntries must contain at least one catalog item")
    @Valid
    List<CatalogItemDto> catalogEntries,

    @Valid
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
}

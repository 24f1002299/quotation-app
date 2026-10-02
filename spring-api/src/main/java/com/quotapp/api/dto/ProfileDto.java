package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;

/**
 * Contractor profile data transfer object.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ProfileDto(
    String id,

    @JsonProperty("user_id")
    @JsonAlias("userId")
    String userId,

    String name,

    @JsonProperty("business_name")
    @JsonAlias("businessName")
    String businessName,

    /**
     * Free-form business slug ('tiling', 'pest_control', 'catering', ...).
     * The old tiling|painting restriction was removed. Serialized as
     * {@code trade} for backward compatibility; also accepts
     * {@code businessType} on input.
     */
    @JsonAlias("businessType")
    String trade,

    String city,
    String phone,
    String gstin,

    @JsonProperty("logo_path")
    @JsonAlias("logoPath")
    String logoPath,

    @JsonProperty("quote_terms")
    @JsonAlias("quoteTerms")
    String quoteTerms,

    @JsonProperty("schema_version")
    @JsonAlias("schemaVersion")
    Integer schemaVersion,

    Integer version,

    @JsonProperty("updated_at")
    @JsonAlias("updatedAt")
    Instant updatedAt
) {
    public ProfileDto {
        if (trade == null || trade.isBlank()) {
            trade = "tiling";
        }
        if (schemaVersion == null) {
            schemaVersion = 1;
        }
        if (version == null) {
            version = 1;
        }
    }
}

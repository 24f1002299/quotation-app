package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Pattern;

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

    @Pattern(regexp = "(?i)tiling|painting|^$", message = "Trade must be 'tiling' or 'painting'")
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

package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;

/**
 * Contractor profile data transfer object, for ANY business domain.
 *
 * <p>Canonical name is {@code businessType}: a free-form business slug
 * ('tiling', 'pest_control', 'catering', ...). Legacy wire names
 * {@code trade} and {@code business_type} are still accepted on input.
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
     * Serialized as {@code businessType}; also accepts {@code trade} and
     * {@code business_type} on input for backward compatibility.
     */
    @JsonProperty("businessType")
    @JsonAlias({"trade", "business_type"})
    String businessType,

    String city,
    String phone,
    String gstin,

    @JsonProperty("logo_path")
    @JsonAlias("logoPath")
    String logoPath,

    @JsonProperty("quote_terms")
    @JsonAlias("quoteTerms")
    String quoteTerms,

    @JsonProperty("default_unit")
    @JsonAlias("defaultUnit")
    String defaultUnit,

    String currency,

    @JsonProperty("schema_version")
    @JsonAlias("schemaVersion")
    Integer schemaVersion,

    Integer version,

    @JsonProperty("updated_at")
    @JsonAlias("updatedAt")
    Instant updatedAt
) {
    public ProfileDto {
        if (businessType == null || businessType.isBlank()) {
            businessType = "tiling";
        }
        if (schemaVersion == null) {
            schemaVersion = 1;
        }
        if (version == null) {
            version = 1;
        }
    }
}

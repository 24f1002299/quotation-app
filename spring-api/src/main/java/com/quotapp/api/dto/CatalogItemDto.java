package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

/**
 * Catalog entry candidate passed to the extraction engine to constrain recognition.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record CatalogItemDto(
    @NotBlank(message = "Catalog item ID cannot be blank")
    String id,

    @NotBlank(message = "Display name cannot be blank")
    String displayName,

    @NotBlank(message = "defaultUnit is required")
    @ValidContractorUnit(message = "defaultUnit must be a recognized contractor unit (sq ft, rft, brass, nos, lumpsum, bags, point)")
    String defaultUnit,

    List<@ValidContractorUnit String> allowableUnits,

    List<String> synonyms,

    String trade
) {}

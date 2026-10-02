package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

/**
 * One service the contractor sells, passed as extraction context.
 *
 * <p>Legacy name kept for wire compatibility; the "catalog" is the user's own
 * service list and works for any business domain. New clients send
 * {@code name}/{@code unit}/{@code keywords}; the old
 * {@code displayName}/{@code defaultUnit}/{@code synonyms} names still bind.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record CatalogItemDto(
    @NotBlank(message = "Catalog item ID cannot be blank")
    String id,

    @NotBlank(message = "Display name cannot be blank")
    @JsonAlias("name")
    String displayName,

    @NotBlank(message = "defaultUnit is required")
    @ValidContractorUnit(message = "defaultUnit must be a recognized contractor unit (sq ft, rft, brass, nos, lumpsum, bags, point, kg, litre, hour, visit, room, plate, item)")
    @JsonAlias("unit")
    String defaultUnit,

    List<@ValidContractorUnit String> allowableUnits,

    @JsonAlias("keywords")
    List<String> synonyms,

    String trade
) {}

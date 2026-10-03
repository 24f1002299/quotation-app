package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.NotBlank;

import java.util.List;

/**
 * Canonical service item: one product/service from the user's own service
 * list, sent as extraction context. Works for any business domain.
 *
 * <p>Wire-compatible with the legacy {@link CatalogItemDto}: {@code name}
 * binds {@code displayName}, {@code unit} binds {@code defaultUnit},
 * {@code keywords} binds {@code synonyms}, {@code businessType} binds
 * {@code trade}. New clients should send the canonical names.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ServiceItemDto(
    @NotBlank(message = "Service item ID cannot be blank")
    String id,

    @NotBlank(message = "Service name cannot be blank")
    @JsonAlias("displayName")
    String name,

    @NotBlank(message = "unit is required")
    @ValidContractorUnit(message = "unit must be a recognized contractor unit (sq ft, rft, brass, nos, lumpsum, bags, point, kg, litre, hour, visit, room, plate, item)")
    @JsonAlias("defaultUnit")
    String unit,

    List<@ValidContractorUnit String> allowableUnits,

    @JsonAlias("synonyms")
    List<String> keywords,

    @JsonAlias("trade")
    String businessType
) {
    /** Converts a legacy catalog entry to its canonical service form. */
    public static ServiceItemDto fromCatalog(CatalogItemDto c) {
        if (c == null) return null;
        return new ServiceItemDto(
            c.id(),
            c.displayName(),
            c.defaultUnit(),
            c.allowableUnits(),
            c.synonyms(),
            c.trade()
        );
    }
}

package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.quotapp.api.validation.ValidContractorUnit;
import jakarta.validation.constraints.NotBlank;

/**
 * Billable work the model heard clearly (quantity + unit present) that matches
 * none of the contractor's services.
 *
 * <p>Unlike {@link ExplicitUnknownDto} (ambiguous fragments), a suggestion
 * carries enough structure to become a reviewable line item in one tap — but
 * it is NEVER priced or totalled server-side. The client decides the rate.
 *
 * <p>STRICT INVARIANT: no arithmetic fields (amount/subtotal/total). A rate
 * hint in paise is allowed: it is the contractor's spoken number, not a
 * model computation.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public record SuggestedItemDto(
    @NotBlank(message = "proposedName is required")
    String proposedName,

    Double quantity,

    @ValidContractorUnit(message = "unit must be a recognized contractor unit")
    String unit,

    Long rateHintPaise,

    String sourceSpan,

    String reason
) {}

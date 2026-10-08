package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Extraction response payload returned to mobile client.
 *
 * <p>Contains ONLY candidate line items, confidence, source spans, and explicit unknowns.
 * Works for ANY business domain: {@code businessType} echoes the free-form
 * business slug from the request (legacy {@code trade} key still accepted
 * on input; responses serialize the canonical name).
 *
 * <p>STRICT INVARIANT: Absolutely NO model-calculated totals (amount, subtotal, grandTotal).
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ExtractResponse(
    String schemaVersion,
    @JsonProperty("businessType")
    @JsonAlias({"trade", "business_type"})
    String businessType,
    List<ExtractedLineItemDto> lineItems,
    List<ExplicitUnknownDto> unknowns,
    List<SuggestedItemDto> suggestedItems,
    Map<String, Object> uncertaintyMetadata,
    Integer version,
    boolean requiresReview,
    String requestId
) {
    public ExtractResponse {
        if (lineItems == null) {
            lineItems = Collections.emptyList();
        }
        if (unknowns == null) {
            unknowns = Collections.emptyList();
        }
        if (suggestedItems == null) {
            suggestedItems = Collections.emptyList();
        }
        if (uncertaintyMetadata == null) {
            uncertaintyMetadata = Collections.emptyMap();
        }
        if (version == null) {
            version = 1;
        }
    }
}

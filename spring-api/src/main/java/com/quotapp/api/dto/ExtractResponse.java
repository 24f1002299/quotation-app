package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Extraction response payload returned to mobile client.
 *
 * <p>Contains ONLY candidate line items, confidence, source spans, and explicit unknowns.
 *
 * <p>STRICT INVARIANT: Absolutely NO model-calculated totals (amount, subtotal, grandTotal).
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ExtractResponse(
    String schemaVersion,
    String trade,
    List<ExtractedLineItemDto> lineItems,
    List<ExplicitUnknownDto> unknowns,
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
        if (uncertaintyMetadata == null) {
            uncertaintyMetadata = Collections.emptyMap();
        }
        if (version == null) {
            version = 1;
        }
    }
}

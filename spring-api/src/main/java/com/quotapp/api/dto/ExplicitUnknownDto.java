package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Explicit unknown or unmapped phrase extracted from the transcript.
 *
 * <p>Rather than hallucinating or guessing catalog items, the extraction engine flags
 * ambiguous or out-of-catalog contractor utterances as explicit unknowns for UI review.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ExplicitUnknownDto(
    String sourceSpan,
    String suspectedTerm,
    String reason,
    Double confidence
) {
    public ExplicitUnknownDto(String sourceSpan, String reason) {
        this(sourceSpan, null, reason, 0.0);
    }
}

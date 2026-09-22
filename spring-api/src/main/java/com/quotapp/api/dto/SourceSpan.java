package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Character offsets and substring from the spoken transcript corresponding to an extracted entity.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record SourceSpan(
    int startIndex,
    int endIndex,
    String text
) {
    public SourceSpan(String text) {
        this(-1, -1, text);
    }
}

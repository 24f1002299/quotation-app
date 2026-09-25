package com.quotapp.api.dto;

/**
 * Payload returned with HTTP 409 Conflict when the same quote was edited on another device.
 */
public record QuoteConflictResponse(
    String code,
    String message,
    QuoteDto serverQuote
) {}

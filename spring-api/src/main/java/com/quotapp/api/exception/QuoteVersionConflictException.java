package com.quotapp.api.exception;

import com.quotapp.api.dto.QuoteDto;

/**
 * Thrown when a concurrent edit from another device has already incremented
 * the quote record version on the server.
 */
public class QuoteVersionConflictException extends RuntimeException {

    private final QuoteDto serverQuote;

    public QuoteVersionConflictException(String message, QuoteDto serverQuote) {
        super(message);
        this.serverQuote = serverQuote;
    }

    public QuoteDto getServerQuote() {
        return serverQuote;
    }
}

package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;

/**
 * Minimal extraction job record.
 *
 * <p>Invariant: Contains only a redacted transcript snippet (max 40 chars).
 * Raw audio or full transcripts are never persisted in job records.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ExtractionJob(
    String jobId,
    String userId,
    ExtractionJobStatus status,
    String trade,
    String transcriptSnippet,
    ExtractResponse response,
    String errorMessage,
    Instant createdAt,
    Instant updatedAt
) {
    public static ExtractionJob createPending(String jobId, String userId, String trade, String transcript) {
        String snippet = sanitizeSnippet(transcript);
        Instant now = Instant.now();
        return new ExtractionJob(jobId, userId, ExtractionJobStatus.PENDING, trade, snippet, null, null, now, now);
    }

    public ExtractionJob complete(ExtractResponse response) {
        return new ExtractionJob(
            this.jobId, this.userId, ExtractionJobStatus.COMPLETED, this.trade, this.transcriptSnippet,
            response, null, this.createdAt, Instant.now()
        );
    }

    public ExtractionJob fail(String errorMessage) {
        return new ExtractionJob(
            this.jobId, this.userId, ExtractionJobStatus.FAILED, this.trade, this.transcriptSnippet,
            null, errorMessage, this.createdAt, Instant.now()
        );
    }

    private static String sanitizeSnippet(String text) {
        if (text == null || text.isBlank()) {
            return "";
        }
        String clean = text.trim().replaceAll("\\s+", " ");
        if (clean.length() <= 35) {
            return clean;
        }
        return clean.substring(0, 32) + "...";
    }
}

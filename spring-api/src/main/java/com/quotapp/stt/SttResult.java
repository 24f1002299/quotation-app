package com.quotapp.stt;

/**
 * Result of a speech-to-text transcription request.
 *
 * @param transcript     Raw transcribed text candidate (untrusted, requires user review)
 * @param provider       STT provider used ("grok" or "whisper")
 * @param language       Language code detected or requested ("hi", "mr", "en", etc.)
 * @param latencyMs      End-to-end provider roundtrip latency in milliseconds
 * @param audioSizeBytes Size of the submitted audio in bytes
 */
public record SttResult(
    String transcript,
    String provider,
    String language,
    long latencyMs,
    long audioSizeBytes
) {}

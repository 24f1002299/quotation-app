package com.quotapp.stt;

/**
 * Result of a speech-to-text transcription request.
 *
 * @param transcript       Raw transcribed text candidate (untrusted, requires user review)
 * @param provider         STT provider used ("grok" or "whisper")
 * @param language         Language code detected or requested ("hi", "mr", "en", etc.)
 * @param latencyMs        End-to-end provider roundtrip latency in milliseconds
 * @param audioSizeBytes   Size of the submitted audio in bytes
 * @param detectedLanguage ISO language code auto-detected by the provider
 *                         ("en", "hi", "mr", "is", ...), or null when unknown.
 *                         Used to catch hallucinations: if the mic captures
 *                         unintelligible noise, Whisper often returns fluent text
 *                         in an unrelated language (e.g. Icelandic) instead of
 *                         failing, which looks like a "wrong transcript".
 * @param confidence       0.0-1.0 speech confidence derived from segment
 *                         no-speech probabilities and log-probs (verbose_json).
 *                         Low values mean the mic audio was likely silence/noise.
 */
public record SttResult(
    String transcript,
    String provider,
    String language,
    long latencyMs,
    long audioSizeBytes,
    String detectedLanguage,
    double confidence
) {
    /** Backwards-compatible constructor for tests/mocks without detection data. */
    public SttResult(
        String transcript,
        String provider,
        String language,
        long latencyMs,
        long audioSizeBytes
    ) {
        this(transcript, provider, language, latencyMs, audioSizeBytes, null, 0.9);
    }
}

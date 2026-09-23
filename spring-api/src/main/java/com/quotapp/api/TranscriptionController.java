package com.quotapp.api;

import com.quotapp.security.UserContext;
import com.quotapp.security.UserRateLimiter;
import com.quotapp.stt.SttResult;
import com.quotapp.stt.SttService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Map;
import java.util.Set;

/**
 * Authenticated endpoint for contractor voice transcription.
 *
 * <p>Requirements:
 * <ul>
 *   <li>Requires a valid Supabase JWT via Bearer token (enforced by {@link com.quotapp.security.SupabaseJwtFilter}).</li>
 *   <li>Accepts compact mobile audio (prefer M4A / AAC).</li>
 *   <li>Enforces 10MB size limit and validates audio container types.</li>
 *   <li>Never stores raw audio on disk or in the database.</li>
 *   <li>Never logs raw audio bytes or provider API secrets.</li>
 *   <li>Returns candidate transcript for review; never treated as trusted quote data.</li>
 * </ul>
 */
@RestController
@RequestMapping("/api")
public class TranscriptionController {

    private static final Logger log = LoggerFactory.getLogger(TranscriptionController.class);

    private static final long MAX_AUDIO_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB

    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of(
        "audio/mp4",
        "audio/m4a",
        "audio/x-m4a",
        "audio/aac",
        "audio/wav",
        "audio/wave",
        "audio/x-wav",
        "audio/mpeg",
        "audio/mp3",
        "audio/ogg",
        "audio/webm",
        "application/octet-stream" // fallback for generic binary uploads from mobile
    );

    private static final int MAX_DURATION_SECONDS = 120;

    private final SttService sttService;
    private final UserRateLimiter rateLimiter;

    @org.springframework.beans.factory.annotation.Autowired
    public TranscriptionController(SttService sttService, UserRateLimiter rateLimiter) {
        this.sttService = sttService;
        this.rateLimiter = rateLimiter;
    }

    /** Constructor for tests where rateLimiter is optional */
    public TranscriptionController(SttService sttService) {
        this(sttService, new UserRateLimiter(10));
    }

    /**
     * Overload for 3-argument calls without durationSeconds.
     */
    public ResponseEntity<?> transcribe(MultipartFile file, String language, String provider) {
        return transcribe(file, language, provider, null);
    }

    /**
     * Transcribes an uploaded audio file using Grok STT (default) or Whisper.
     */
    @PostMapping(value = "/transcribe", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> transcribe(
        @RequestParam("file") MultipartFile file,
        @RequestParam(value = "language", required = false) String language,
        @RequestParam(value = "provider", required = false) String provider,
        @RequestParam(value = "durationSeconds", required = false) Integer durationSeconds
    ) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(structuredError("UNAUTHORIZED", "Authentication required"));
        }

        // Validate rate limit per user
        if (rateLimiter != null && !rateLimiter.tryAcquire(userId)) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .body(structuredError(
                    "RATE_LIMIT_EXCEEDED",
                    "Rate limit exceeded. Please wait a moment before sending another recording."
                ));
        }

        // Validate presence
        if (file == null || file.isEmpty()) {
            return ResponseEntity.badRequest()
                .body(structuredError("EMPTY_FILE", "Audio file is required and cannot be empty"));
        }

        // Validate duration if provided
        if (durationSeconds != null && (durationSeconds > MAX_DURATION_SECONDS || durationSeconds < 0)) {
            return ResponseEntity.badRequest()
                .body(structuredError(
                    "DURATION_EXCEEDED",
                    "Recording exceeds maximum duration of " + MAX_DURATION_SECONDS + " seconds (" + durationSeconds + "s received)"
                ));
        }

        // Validate size
        if (file.getSize() > MAX_AUDIO_SIZE_BYTES) {
            return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE)
                .body(structuredError(
                    "FILE_TOO_LARGE",
                    "Audio exceeds maximum allowed size of 10MB (" + file.getSize() + " bytes received)"
                ));
        }

        // Validate content type
        String contentType = file.getContentType();
        if (contentType != null && !ALLOWED_CONTENT_TYPES.contains(contentType.toLowerCase())) {
            return ResponseEntity.status(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
                .body(structuredError(
                    "UNSUPPORTED_MEDIA_TYPE",
                    "Audio format not supported: " + contentType + ". Supported: M4A, AAC, WAV, MP3, OGG, WebM"
                ));
        }

        try {
            byte[] audioBytes = file.getBytes();
            String originalFilename = file.getOriginalFilename();

            log.info("Processing transcription for user={}, filename={}, size={}, provider={}, language={}",
                userId, originalFilename, audioBytes.length, provider, language);

            SttResult result = sttService.transcribe(audioBytes, originalFilename, language, provider);

            String transcriptText = result.transcript() != null ? result.transcript() : "";
            // Hallucination guard: Whisper maps unintelligible mic noise to fluent
            // text in an unrelated language (observed: Icelandic) instead of
            // failing. Surface that as a mic/clarity warning, never as the
            // contractor's words.
            String detected = result.detectedLanguage();
            double confidence = result.confidence();
            boolean langMismatch = detected != null
                && !Set.of("en", "hi", "mr").contains(detected);
            boolean lowConfidence = confidence < 0.5;
            boolean isUncertain = transcriptText.isBlank()
                || transcriptText.contains("?")
                || langMismatch
                || lowConfidence;
            String reason = null;
            if (langMismatch) {
                reason = "We couldn't hear you clearly (heard something like '"
                    + detected + "' instead of Hindi/Marathi/English). "
                    + "Check the device microphone, speak closer and louder, then re-record.";
            } else if (lowConfidence) {
                reason = "We couldn't hear you clearly (low audio clarity). "
                    + "Check the device microphone, move to a quieter spot and re-record.";
            }
            if (reason != null) {
                log.warn("STT low-quality transcript for user={}: detectedLanguage={}, confidence={}, audioBytes={}",
                    userId, detected, String.format("%.3f", confidence), audioBytes.length);
            }
            java.util.Map<String, Object> uncertaintyMetadata = new java.util.HashMap<>(Map.of(
                "isUncertain", isUncertain,
                "confidence", isUncertain ? Math.min(0.65, confidence) : 0.95,
                "provider", result.provider(),
                "requiresReview", true
            ));
            if (reason != null) {
                uncertaintyMetadata.put("reason", reason);
            }
            if (detected != null) {
                uncertaintyMetadata.put("detectedLanguage", detected);
            }

            return ResponseEntity.ok(Map.of(
                "transcript", transcriptText,
                "provider", result.provider(),
                "language", result.language() != null ? result.language() : "auto",
                "latencyMs", result.latencyMs(),
                "audioSizeBytes", result.audioSizeBytes(),
                "status", "CANDIDATE_FOR_REVIEW",
                "uncertaintyMetadata", uncertaintyMetadata
            ));

        } catch (IllegalStateException e) {
            log.error("STT configuration error for user={}: {}", userId, e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(structuredError("CONFIG_ERROR", e.getMessage()));
        } catch (IOException e) {
            log.error("Failed to read audio bytes for user={}: {}", userId, e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(structuredError("READ_ERROR", "Could not read audio stream"));
        } catch (Exception e) {
            log.error("STT transcription failed for user={}: {}", userId, e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(structuredError("PROVIDER_ERROR", "Transcription failed: " + e.getMessage()));
        }
    }

    private Map<String, Object> structuredError(String code, String message) {
        return Map.of(
            "error", code,
            "message", message,
            "requestId", com.quotapp.security.RequestIdFilter.getCurrentRequestId(),
            "timestamp", java.time.Instant.now().toString()
        );
    }
}

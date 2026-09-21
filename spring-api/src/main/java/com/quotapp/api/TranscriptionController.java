package com.quotapp.api;

import com.quotapp.security.UserContext;
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

    private final SttService sttService;

    public TranscriptionController(SttService sttService) {
        this.sttService = sttService;
    }

    /**
     * Transcribes an uploaded audio file using Grok STT (default) or Whisper.
     */
    @PostMapping(value = "/transcribe", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> transcribe(
        @RequestParam("file") MultipartFile file,
        @RequestParam(value = "language", required = false) String language,
        @RequestParam(value = "provider", required = false) String provider
    ) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(Map.of("error", "UNAUTHORIZED", "message", "Authentication required"));
        }

        // Validate presence
        if (file == null || file.isEmpty()) {
            return ResponseEntity.badRequest()
                .body(Map.of("error", "EMPTY_FILE", "message", "Audio file is required and cannot be empty"));
        }

        // Validate size
        if (file.getSize() > MAX_AUDIO_SIZE_BYTES) {
            return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE)
                .body(Map.of(
                    "error", "FILE_TOO_LARGE",
                    "message", "Audio exceeds maximum allowed size of 10MB (" + file.getSize() + " bytes received)"
                ));
        }

        // Validate content type
        String contentType = file.getContentType();
        if (contentType != null && !ALLOWED_CONTENT_TYPES.contains(contentType.toLowerCase())) {
            return ResponseEntity.status(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
                .body(Map.of(
                    "error", "UNSUPPORTED_MEDIA_TYPE",
                    "message", "Audio format not supported: " + contentType + ". Supported: M4A, AAC, WAV, MP3, OGG, WebM"
                ));
        }

        try {
            byte[] audioBytes = file.getBytes();
            String originalFilename = file.getOriginalFilename();

            log.info("Processing transcription for user={}, filename={}, size={}, provider={}, language={}",
                userId, originalFilename, audioBytes.length, provider, language);

            SttResult result = sttService.transcribe(audioBytes, originalFilename, language, provider);

            return ResponseEntity.ok(Map.of(
                "transcript", result.transcript(),
                "provider", result.provider(),
                "language", result.language() != null ? result.language() : "auto",
                "latencyMs", result.latencyMs(),
                "audioSizeBytes", result.audioSizeBytes(),
                "status", "CANDIDATE_FOR_REVIEW"
            ));

        } catch (IllegalStateException e) {
            log.error("STT configuration error for user={}: {}", userId, e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of("error", "CONFIG_ERROR", "message", e.getMessage()));
        } catch (IOException e) {
            log.error("Failed to read audio bytes for user={}: {}", userId, e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "READ_ERROR", "message", "Could not read audio stream"));
        } catch (Exception e) {
            log.error("STT transcription failed for user={}: {}", userId, e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(Map.of("error", "PROVIDER_ERROR", "message", "Transcription failed: " + e.getMessage()));
        }
    }
}

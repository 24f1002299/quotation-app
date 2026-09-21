package com.quotapp.api;

import com.quotapp.security.UserContext;
import com.quotapp.stt.SttResult;
import com.quotapp.stt.SttService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockMultipartFile;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link TranscriptionController}.
 */
class TranscriptionControllerTest {

    private SttService sttService;
    private TranscriptionController controller;
    private final String testUserId = UUID.randomUUID().toString();

    @BeforeEach
    void setUp() {
        sttService = mock(SttService.class);
        controller = new TranscriptionController(sttService);
        UserContext.setUserId(testUserId);
    }

    @AfterEach
    void tearDown() {
        UserContext.clear();
    }

    @Test
    @DisplayName("Returns 401 when user is not authenticated in UserContext")
    void testUnauthorizedWhenNoUser() {
        UserContext.clear();
        MockMultipartFile file = new MockMultipartFile(
            "file", "audio.m4a", "audio/m4a", "test-audio".getBytes()
        );

        ResponseEntity<?> response = controller.transcribe(file, "hi", "grok");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    @DisplayName("Returns 400 when uploaded audio file is empty")
    void testBadRequestWhenEmptyFile() {
        MockMultipartFile emptyFile = new MockMultipartFile(
            "file", "audio.m4a", "audio/m4a", new byte[0]
        );

        ResponseEntity<?> response = controller.transcribe(emptyFile, "hi", "grok");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isInstanceOf(Map.class);
        Map<?, ?> body = (Map<?, ?>) response.getBody();
        assertThat(body.get("error")).isEqualTo("EMPTY_FILE");
    }

    @Test
    @DisplayName("Returns 413 when file exceeds 10MB limit")
    void testPayloadTooLarge() {
        // Create 11 MB dummy file
        byte[] largeBytes = new byte[11 * 1024 * 1024];
        MockMultipartFile largeFile = new MockMultipartFile(
            "file", "large.m4a", "audio/m4a", largeBytes
        );

        ResponseEntity<?> response = controller.transcribe(largeFile, "hi", "grok");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.PAYLOAD_TOO_LARGE);
        Map<?, ?> body = (Map<?, ?>) response.getBody();
        assertThat(body.get("error")).isEqualTo("FILE_TOO_LARGE");
    }

    @Test
    @DisplayName("Returns 415 when unsupported media type is uploaded")
    void testUnsupportedMediaType() {
        MockMultipartFile pdfFile = new MockMultipartFile(
            "file", "doc.pdf", "application/pdf", "fake-pdf".getBytes()
        );

        ResponseEntity<?> response = controller.transcribe(pdfFile, "hi", "grok");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNSUPPORTED_MEDIA_TYPE);
        Map<?, ?> body = (Map<?, ?>) response.getBody();
        assertThat(body.get("error")).isEqualTo("UNSUPPORTED_MEDIA_TYPE");
    }

    @Test
    @DisplayName("Returns 200 with transcript and latency when Grok transcription succeeds")
    void testSuccessfulTranscriptionGrok() {
        byte[] audioBytes = "fake-m4a-audio-data".getBytes();
        MockMultipartFile audioFile = new MockMultipartFile(
            "file", "quote_sample.m4a", "audio/m4a", audioBytes
        );

        when(sttService.transcribe(any(byte[].class), eq("quote_sample.m4a"), eq("mr"), eq("grok")))
            .thenReturn(new SttResult(
                "हॉल मध्ये 120 स्क्वेअर फूट टाईल लेबर आणि 40 रनिंग फूट स्कर्टिंग",
                "grok",
                "mr",
                620L,
                audioBytes.length
            ));

        ResponseEntity<?> response = controller.transcribe(audioFile, "mr", "grok", 25);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map<?, ?> body = (Map<?, ?>) response.getBody();
        assertThat(body.get("transcript")).isEqualTo("हॉल मध्ये 120 स्क्वेअर फूट टाईल लेबर आणि 40 रनिंग फूट स्कर्टिंग");
        assertThat(body.get("provider")).isEqualTo("grok");
        assertThat(body.get("language")).isEqualTo("mr");
        assertThat(body.get("latencyMs")).isEqualTo(620L);
        assertThat(body.get("status")).isEqualTo("CANDIDATE_FOR_REVIEW");
        assertThat(body.get("uncertaintyMetadata")).isNotNull();
    }

    @Test
    @DisplayName("Returns 400 when recording duration exceeds 120 seconds")
    void testDurationExceeded() {
        MockMultipartFile audioFile = new MockMultipartFile(
            "file", "long_sample.m4a", "audio/m4a", "short-bytes".getBytes()
        );

        ResponseEntity<?> response = controller.transcribe(audioFile, "hi", "grok", 125);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        Map<?, ?> body = (Map<?, ?>) response.getBody();
        assertThat(body.get("error")).isEqualTo("DURATION_EXCEEDED");
    }

    @Test
    @DisplayName("Returns 429 when user rate limit is exceeded")
    void testRateLimitExceeded() {
        com.quotapp.security.UserRateLimiter strictLimiter = new com.quotapp.security.UserRateLimiter(2);
        TranscriptionController rateLimitedController = new TranscriptionController(sttService, strictLimiter);

        MockMultipartFile audioFile = new MockMultipartFile(
            "file", "sample.m4a", "audio/m4a", "bytes".getBytes()
        );

        when(sttService.transcribe(any(byte[].class), anyString(), any(), any()))
            .thenReturn(new SttResult("sample text", "grok", "hi", 100L, 5));

        // Request 1 & 2 succeed
        assertThat(rateLimitedController.transcribe(audioFile, "hi", "grok", 10).getStatusCode())
            .isEqualTo(HttpStatus.OK);
        assertThat(rateLimitedController.transcribe(audioFile, "hi", "grok", 10).getStatusCode())
            .isEqualTo(HttpStatus.OK);

        // Request 3 exceeds limit of 2 requests per minute
        ResponseEntity<?> response3 = rateLimitedController.transcribe(audioFile, "hi", "grok", 10);
        assertThat(response3.getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        Map<?, ?> body = (Map<?, ?>) response3.getBody();
        assertThat(body.get("error")).isEqualTo("RATE_LIMIT_EXCEEDED");
    }
}

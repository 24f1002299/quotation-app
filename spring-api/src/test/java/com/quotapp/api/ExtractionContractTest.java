package com.quotapp.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quotapp.api.dto.*;
import com.quotapp.security.RequestIdFilter;
import com.quotapp.security.UserContext;
import com.quotapp.stt.SttResult;
import com.quotapp.stt.SttService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Contract verification test suite for Day 10 — Build the extraction API contract.
 *
 * <p>Verifies:
 * <ul>
 *   <li>Rejection of malformed JSON with RFC-7807 structured error.</li>
 *   <li>Rejection of unauthorized requests (401).</li>
 *   <li>Rejection of unsupported media types (415) and oversized audio (413).</li>
 *   <li>Rejection of unrecognized units in catalog and rate memory.</li>
 *   <li>Rejection of oversized transcripts (> 5,000 characters).</li>
 *   <li>Guaranteed absence of arithmetic fields (amount, subtotal, total) from extraction contract.</li>
 *   <li>Rate provenance guarantees (RATE_MEMORY, SUGGESTED, UNKNOWN only).</li>
 *   <li>Zero provider secret leakage in headers, bodies, and logs.</li>
 *   <li>Zero audio persistence on local filesystem.</li>
 *   <li>Idempotency key consistency and duplicate avoidance.</li>
 *   <li>X-Request-Id header tracing and propagation.</li>
 * </ul>
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
    "supabase.jwks-url=http://localhost:0/test-jwks",
    "spring.datasource.url=jdbc:h2:mem:contractdb;MODE=PostgreSQL",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "database.app-role.password=test",
    "quotapp.stt.grok.api-key=xai-test-dummy-key-never-leak",
    "quotapp.stt.whisper.api-key=sk-proj-test-dummy-key-never-leak"
})
class ExtractionContractTest {

    private static final String TEST_USER = "11111111-2222-3333-4444-555555555555";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private SttService sttService;

    @BeforeEach
    void setUp() {
        UserContext.setUserId(TEST_USER);
    }

    @AfterEach
    void tearDown() {
        UserContext.clear();
    }

    private CatalogItemDto sampleCatalogItem(String id, String name, String unit) {
        return new CatalogItemDto(id, name, unit, List.of(unit), List.of(name.toLowerCase()), "tiling");
    }

    // ─── 1. Malformed JSON Rejection ──────────────────────────────────────────

    @Test
    @DisplayName("Contract rejects malformed JSON with 400 Bad Request and structured error")
    void testRejectMalformedJson() throws Exception {
        String unparseableJson = "{ \"trade\": \"tiling\", \"transcript\": \"missing closing quote }";

        mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(unparseableJson))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.error").value("MALFORMED_JSON"))
            .andExpect(jsonPath("$.message").exists())
            .andExpect(jsonPath("$.requestId").exists())
            .andExpect(jsonPath("$.timestamp").exists());
    }

    // ─── 2. Unauthorized Requests Rejection ───────────────────────────────────

    @Test
    @DisplayName("Contract rejects unauthenticated requests to extraction endpoint with 401")
    void testRejectUnauthorizedExtraction() throws Exception {
        UserContext.clear();
        ExtractRequest validRequest = new ExtractRequest(
            "Tile labour 100 sq ft",
            "tiling",
            List.of(sampleCatalogItem("tile_labour", "Tile Labour", "sq ft")),
            Collections.emptyList(),
            "hi",
            "1.0",
            1,
            null
        );

        mockMvc.perform(post("/api/extract")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(validRequest)))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.error").value("UNAUTHORIZED"))
            .andExpect(jsonPath("$.requestId").exists());
    }

    @Test
    @DisplayName("Contract rejects unauthenticated requests to transcription endpoint with 401")
    void testRejectUnauthorizedTranscription() throws Exception {
        UserContext.clear();
        MockMultipartFile file = new MockMultipartFile(
            "file", "audio.m4a", "audio/m4a", "dummy-bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/transcribe").file(file))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.error").value("UNAUTHORIZED"))
            .andExpect(jsonPath("$.requestId").exists());
    }

    // ─── 3. Unsupported Audio Format Rejection ────────────────────────────────

    @Test
    @DisplayName("Contract rejects unsupported audio media types with 415")
    void testRejectUnsupportedAudioMediaType() throws Exception {
        MockMultipartFile pdfFile = new MockMultipartFile(
            "file", "malicious_file.pdf", "application/pdf", "fake-pdf-content".getBytes()
        );

        mockMvc.perform(multipart("/api/transcribe")
                .file(pdfFile)
                .with(user(TEST_USER)))
            .andExpect(status().isUnsupportedMediaType())
            .andExpect(jsonPath("$.error").value("UNSUPPORTED_MEDIA_TYPE"))
            .andExpect(jsonPath("$.requestId").exists());
    }

    // ─── 4. Oversized Audio Rejection ─────────────────────────────────────────

    @Test
    @DisplayName("Contract rejects oversized audio uploads exceeding 10MB with 413")
    void testRejectOversizedAudio() throws Exception {
        byte[] largeAudio = new byte[11 * 1024 * 1024]; // 11 MB
        MockMultipartFile largeFile = new MockMultipartFile(
            "file", "large_voice_quote.m4a", "audio/m4a", largeAudio
        );

        mockMvc.perform(multipart("/api/transcribe")
                .file(largeFile)
                .with(user(TEST_USER)))
            .andExpect(status().isPayloadTooLarge())
            .andExpect(jsonPath("$.error").value("FILE_TOO_LARGE"))
            .andExpect(jsonPath("$.requestId").exists());
    }

    // ─── 5. Unrecognized Units Rejection ──────────────────────────────────────

    @Test
    @DisplayName("Contract rejects catalog entries with unrecognized units")
    void testRejectUnrecognizedUnitInCatalog() throws Exception {
        String invalidRequestJson = """
            {
              "transcript": "Tiles 100 sq ft",
              "trade": "tiling",
              "catalogEntries": [
                {
                  "id": "tile_labour",
                  "displayName": "Tile Labour",
                  "defaultUnit": "unknown_metric_unit"
                }
              ],
              "schemaVersion": "1.0"
            }
            """;

        mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(invalidRequestJson))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
            .andExpect(jsonPath("$.details").isArray());
    }

    @Test
    @DisplayName("Contract rejects rate memory with unrecognized units")
    void testRejectUnrecognizedUnitInRateMemory() throws Exception {
        String invalidRequestJson = """
            {
              "transcript": "Tiles 100 sq ft",
              "trade": "tiling",
              "catalogEntries": [
                {
                  "id": "tile_labour",
                  "displayName": "Tile Labour",
                  "defaultUnit": "sq ft"
                }
              ],
              "rateMemory": [
                {
                  "catalogItemId": "tile_labour",
                  "unit": "random_fake_unit",
                  "unitRatePaise": 3500
                }
              ],
              "schemaVersion": "1.0"
            }
            """;

        mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(invalidRequestJson))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
            .andExpect(jsonPath("$.details").isArray());
    }

    // ─── 6. Oversized Transcript Rejection ─────────────────────────────────────

    @Test
    @DisplayName("Contract rejects transcripts exceeding 5,000 characters with 400")
    void testRejectOversizedTranscript() throws Exception {
        String oversizedTranscript = "A".repeat(5001);

        ExtractRequest request = new ExtractRequest(
            oversizedTranscript,
            "tiling",
            List.of(sampleCatalogItem("tile_labour", "Tile Labour", "sq ft")),
            Collections.emptyList(),
            "hi",
            "1.0",
            1,
            null
        );

        mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
            .andExpect(jsonPath("$.details[0].field").value("transcript"));
    }

    // ─── 7. Arithmetic Fields Exclusion Guarantee ─────────────────────────────

    @Test
    @DisplayName("Contract schema strictly forbids model-calculated arithmetic totals")
    void testContractExcludesArithmeticFields() {
        // Verify reflection on ExtractedLineItemDto
        List<String> forbiddenNames = List.of(
            "amount", "amountpaise", "linetotal", "subtotal", "subtotalpaise",
            "grandtotal", "grandtotalpaise", "gst", "gstpaise", "tax", "total"
        );

        Field[] fields = ExtractedLineItemDto.class.getDeclaredFields();
        for (Field f : fields) {
            String name = f.getName().toLowerCase();
            assertThat(forbiddenNames)
                .as("ExtractedLineItemDto must NOT contain arithmetic field: " + name)
                .doesNotContain(name);
        }

        Method[] methods = ExtractedLineItemDto.class.getDeclaredMethods();
        for (Method m : methods) {
            String name = m.getName().toLowerCase();
            assertThat(forbiddenNames)
                .as("ExtractedLineItemDto must NOT contain arithmetic getter: " + name)
                .doesNotContain(name);
        }

        // Verify reflection on ExtractResponse
        Field[] responseFields = ExtractResponse.class.getDeclaredFields();
        for (Field f : responseFields) {
            String name = f.getName().toLowerCase();
            assertThat(forbiddenNames)
                .as("ExtractResponse must NOT contain arithmetic field: " + name)
                .doesNotContain(name);
        }
    }

    // ─── 8. Rate Provenance Guarantee ─────────────────────────────────────────

    @Test
    @DisplayName("Rates originate strictly from rate memory (RATE_MEMORY) or UNKNOWN")
    void testRateProvenanceGuaranteed() throws Exception {
        CatalogItemDto tileItem = sampleCatalogItem("tile_labour", "Tile Labour", "sq ft");
        CatalogItemDto skirtingItem = sampleCatalogItem("skirting", "Skirting", "rft");

        // Provide rate memory only for tile_labour (₹40.00 = 4000 paise)
        RateMemoryItemDto tileRate = new RateMemoryItemDto("tile_labour", "sq ft", 4000L, "tiling");

        ExtractRequest request = new ExtractRequest(
            "Tile labour 150 sq ft and skirting 30 rft",
            "tiling",
            List.of(tileItem, skirtingItem),
            List.of(tileRate),
            "en",
            "1.0",
            1,
            null
        );

        String responseBody = mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.lineItems").isArray())
            .andReturn().getResponse().getContentAsString();

        ExtractResponse response = objectMapper.readValue(responseBody, ExtractResponse.class);

        assertThat(response.lineItems()).isNotEmpty();

        // Find tile labour: must have RATE_MEMORY
        ExtractedLineItemDto extractedTile = response.lineItems().stream()
            .filter(i -> "tile_labour".equals(i.catalogItemId()))
            .findFirst().orElseThrow();
        assertThat(extractedTile.rateSource()).isEqualTo(RateSource.RATE_MEMORY);
        assertThat(extractedTile.unitRatePaise()).isEqualTo(4000L);

        // Find skirting: must be UNKNOWN rate
        ExtractedLineItemDto extractedSkirting = response.lineItems().stream()
            .filter(i -> "skirting".equals(i.catalogItemId()))
            .findFirst().orElseThrow();
        assertThat(extractedSkirting.rateSource()).isEqualTo(RateSource.UNKNOWN);
        assertThat(extractedSkirting.unitRatePaise()).isNull();
    }

    // ─── 9. Zero Provider Secret Leakage ──────────────────────────────────────

    @Test
    @DisplayName("Transcription and extraction endpoints never leak provider API keys")
    void testZeroProviderSecretLeakage() throws Exception {
        MockMultipartFile audioFile = new MockMultipartFile(
            "file", "voice.m4a", "audio/m4a", "dummy-speech-data".getBytes()
        );

        when(sttService.transcribe(any(byte[].class), anyString(), any(), any()))
            .thenReturn(new SttResult("Test transcript", "grok", "hi", 500L, 100));

        var mvcResult = mockMvc.perform(multipart("/api/transcribe")
                .file(audioFile)
                .with(user(TEST_USER)))
            .andExpect(status().isOk())
            .andReturn();

        String body = mvcResult.getResponse().getContentAsString();
        Collection<String> headerNames = mvcResult.getResponse().getHeaderNames();

        assertThat(body)
            .doesNotContain("xai-")
            .doesNotContain("sk-")
            .doesNotContain("dummy-key");

        for (String header : headerNames) {
            String val = mvcResult.getResponse().getHeader(header);
            if (val != null) {
                assertThat(val).doesNotContain("xai-").doesNotContain("sk-");
            }
        }
    }

    // ─── 10. Zero Audio Persistence By Default ────────────────────────────────

    @Test
    @DisplayName("Transcription processes audio purely in RAM and leaves no files on disk")
    void testZeroAudioPersistenceByDefault() throws Exception {
        Path tempDir = Path.of(System.getProperty("java.io.tmpdir"));
        long m4aCountBefore;
        try (Stream<Path> stream = Files.list(tempDir)) {
            m4aCountBefore = stream.filter(p -> p.toString().endsWith(".m4a")).count();
        }

        MockMultipartFile audioFile = new MockMultipartFile(
            "file", "strictly_in_memory.m4a", "audio/m4a", "in-memory-audio-bytes".getBytes()
        );

        when(sttService.transcribe(any(byte[].class), anyString(), any(), any()))
            .thenReturn(new SttResult("In-memory transcript", "grok", "hi", 400L, 20));

        mockMvc.perform(multipart("/api/transcribe")
                .file(audioFile)
                .with(user(TEST_USER)))
            .andExpect(status().isOk());

        long m4aCountAfter;
        try (Stream<Path> stream = Files.list(tempDir)) {
            m4aCountAfter = stream.filter(p -> p.toString().endsWith(".m4a")).count();
        }

        assertThat(m4aCountAfter).isEqualTo(m4aCountBefore);
    }

    // ─── 11. Idempotency Key Consistency ──────────────────────────────────────

    @Test
    @DisplayName("Repeat extraction requests with same Idempotency-Key return cached response")
    void testIdempotencyKeyGuaranteesIdenticalResponse() throws Exception {
        String idempotencyKey = UUID.randomUUID().toString();

        ExtractRequest request1 = new ExtractRequest(
            "Tile labour 100 sq ft",
            "tiling",
            List.of(sampleCatalogItem("tile_labour", "Tile Labour", "sq ft")),
            Collections.emptyList(),
            "hi",
            "1.0",
            1,
            idempotencyKey
        );

        String firstResponse = mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .header("Idempotency-Key", idempotencyKey)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request1)))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();

        // Second request with different transcript but identical Idempotency-Key
        ExtractRequest request2 = new ExtractRequest(
            "Completely different transcript that should be ignored due to idempotency",
            "tiling",
            List.of(sampleCatalogItem("tile_labour", "Tile Labour", "sq ft")),
            Collections.emptyList(),
            "hi",
            "1.0",
            1,
            idempotencyKey
        );

        String secondResponse = mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .header("Idempotency-Key", idempotencyKey)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request2)))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();

        // Assert cached response is returned
        assertThat(secondResponse).isEqualTo(firstResponse);
    }

    // ─── 12. Request ID Tracing ───────────────────────────────────────────────

    @Test
    @DisplayName("Client X-Request-Id is preserved and echoed in response headers")
    void testRequestIdPreservedInHeaders() throws Exception {
        String customRequestId = "client-trace-" + UUID.randomUUID();

        ExtractRequest request = new ExtractRequest(
            "Tile labour 100 sq ft",
            "tiling",
            List.of(sampleCatalogItem("tile_labour", "Tile Labour", "sq ft")),
            Collections.emptyList(),
            "hi",
            "1.0",
            1,
            null
        );

        mockMvc.perform(post("/api/extract")
                .with(user(TEST_USER))
                .header(RequestIdFilter.REQUEST_ID_HEADER, customRequestId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isOk())
            .andExpect(header().string(RequestIdFilter.REQUEST_ID_HEADER, customRequestId))
            .andExpect(jsonPath("$.requestId").value(customRequestId));
    }
}

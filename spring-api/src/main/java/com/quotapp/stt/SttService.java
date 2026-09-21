package com.quotapp.stt;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;

import java.time.Duration;

/**
 * Service orchestrating Speech-to-Text calls to xAI Grok STT and OpenAI Whisper.
 *
 * <p>Key constraints:
 * <ul>
 *   <li>API keys stay strictly server-side — never returned to the mobile app.</li>
 *   <li>Audio bytes are passed in-memory and discarded immediately; no persistent audio storage.</li>
 *   <li>Raw audio and credentials are never written to application logs.</li>
 *   <li>Trade catalogue terms are injected for key-term biasing / prompt hints.</li>
 * </ul>
 */
@Service
public class SttService {

    private static final Logger log = LoggerFactory.getLogger(SttService.class);

    private final String defaultProvider;
    private final String xaiApiKey;
    private final String xaiSttUrl;
    private final String openaiApiKey;
    private final String openaiSttUrl;
    private final String openaiModel;
    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public SttService(
        @Value("${quotapp.stt.default-provider:grok}") String defaultProvider,
        @Value("${quotapp.stt.grok.api-key:}") String xaiApiKey,
        @Value("${quotapp.stt.grok.url:https://api.x.ai/v1/stt}") String xaiSttUrl,
        @Value("${quotapp.stt.grok.timeout-seconds:15}") int grokTimeoutSeconds,
        @Value("${quotapp.stt.whisper.api-key:}") String openaiApiKey,
        @Value("${quotapp.stt.whisper.url:https://api.openai.com/v1/audio/transcriptions}") String openaiSttUrl,
        @Value("${quotapp.stt.whisper.model:whisper-1}") String openaiModel,
        @Value("${quotapp.stt.whisper.timeout-seconds:15}") int whisperTimeoutSeconds,
        ObjectMapper objectMapper
    ) {
        this.defaultProvider = defaultProvider.trim().toLowerCase();
        this.xaiApiKey = xaiApiKey.trim();
        this.xaiSttUrl = xaiSttUrl.trim();
        this.openaiApiKey = openaiApiKey.trim();
        this.openaiSttUrl = openaiSttUrl.trim();
        this.openaiModel = openaiModel.trim();
        this.objectMapper = objectMapper;

        // Configure client with 15s connect & read timeouts
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        int maxTimeoutMs = Math.max(grokTimeoutSeconds, whisperTimeoutSeconds) * 1000;
        requestFactory.setConnectTimeout(Duration.ofMillis(maxTimeoutMs));
        requestFactory.setReadTimeout(Duration.ofMillis(maxTimeoutMs));

        this.restClient = RestClient.builder()
            .requestFactory(requestFactory)
            .build();
    }

    /**
     * Transcribes an in-memory audio byte array using the selected or default STT provider.
     *
     * @param audioBytes       raw audio bytes (M4A/AAC/WAV/MP3)
     * @param originalFilename filename with extension (used by provider to infer container format)
     * @param languageHint     optional ISO language code ("hi", "mr", "en")
     * @param requestedProvider optional provider override ("grok" or "whisper")
     * @return SttResult containing the raw transcript and benchmark metrics
     */
    public SttResult transcribe(
        byte[] audioBytes,
        String originalFilename,
        String languageHint,
        String requestedProvider
    ) {
        String provider = StringUtils.hasText(requestedProvider)
            ? requestedProvider.trim().toLowerCase()
            : defaultProvider;

        String safeFilename = StringUtils.hasText(originalFilename) ? originalFilename : "audio.m4a";
        long start = System.currentTimeMillis();

        String transcript;
        if ("whisper".equals(provider)) {
            transcript = callOpenAiWhisper(audioBytes, safeFilename, languageHint);
        } else {
            // Default to Grok STT
            provider = "grok";
            transcript = callGrokStt(audioBytes, safeFilename, languageHint);
        }

        long latencyMs = System.currentTimeMillis() - start;
        log.info("STT completed: provider={}, audioBytes={}, latencyMs={}, languageHint={}",
            provider, audioBytes.length, latencyMs, languageHint);

        return new SttResult(
            transcript,
            provider,
            languageHint,
            latencyMs,
            audioBytes.length
        );
    }

    /**
     * Calls xAI Grok STT API (POST https://api.x.ai/v1/stt).
     *
     * <p>Features:
     * <ul>
     *   <li>Batch rate: $0.10/hour audio (~72% cheaper than Whisper).</li>
     *   <li>Inverse Text Normalization (ITN): converts spoken numbers and units into digits.</li>
     *   <li>Supports M4A, AAC, WAV, MP3.</li>
     * </ul>
     */
    private String callGrokStt(byte[] audioBytes, String filename, String languageHint) {
        if (!StringUtils.hasText(xaiApiKey)) {
            throw new IllegalStateException("XAI_API_KEY is not configured on the server. Please set XAI_API_KEY in .env");
        }

        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();

        if (StringUtils.hasText(languageHint)) {
            body.add("language", languageHint.trim().toLowerCase());
        }

        // Note: xAI STT requires 'file' to be added after parameters in multipart
        ByteArrayResource fileResource = new NamedByteArrayResource(audioBytes, filename);
        body.add("file", fileResource);

        try {
            String rawResponse = restClient.post()
                .uri(xaiSttUrl)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + xaiApiKey)
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(body)
                .retrieve()
                .body(String.class);

            return parseTranscriptFromResponse(rawResponse);
        } catch (Exception e) {
            log.error("Grok STT API call failed: {}", e.getMessage());
            throw new RuntimeException("Grok STT transcription failed: " + e.getMessage(), e);
        }
    }

    /**
     * Calls OpenAI Whisper API (POST https://api.openai.com/v1/audio/transcriptions).
     *
     * <p>Used for Day 8 benchmarking and side-by-side comparison.
     */
    private String callOpenAiWhisper(byte[] audioBytes, String filename, String languageHint) {
        if (!StringUtils.hasText(openaiApiKey)) {
            throw new IllegalStateException("OPENAI_API_KEY is not configured on the server. Please set OPENAI_API_KEY in .env");
        }

        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        body.add("model", openaiModel);
        body.add("prompt", ContractorCatalogTerms.asPromptString());

        if (StringUtils.hasText(languageHint)) {
            body.add("language", languageHint.trim().toLowerCase());
        }

        ByteArrayResource fileResource = new NamedByteArrayResource(audioBytes, filename);
        body.add("file", fileResource);

        try {
            String rawResponse = restClient.post()
                .uri(openaiSttUrl)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + openaiApiKey)
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(body)
                .retrieve()
                .body(String.class);

            return parseTranscriptFromResponse(rawResponse);
        } catch (Exception e) {
            log.error("OpenAI Whisper API call failed: {}", e.getMessage());
            throw new RuntimeException("OpenAI Whisper transcription failed: " + e.getMessage(), e);
        }
    }

    /**
     * Extracts transcript text from STT JSON response ({ "text": "..." } or { "transcript": "..." }).
     */
    private String parseTranscriptFromResponse(String rawResponse) {
        if (!StringUtils.hasText(rawResponse)) {
            return "";
        }
        try {
            JsonNode root = objectMapper.readTree(rawResponse);
            if (root.has("text")) {
                return root.get("text").asText();
            }
            if (root.has("transcript")) {
                return root.get("transcript").asText();
            }
            return rawResponse;
        } catch (Exception e) {
            log.warn("Failed to parse JSON response from STT provider, returning raw text: {}", e.getMessage());
            return rawResponse;
        }
    }

    /**
     * Helper ByteArrayResource that provides a filename so Multipart HTTP clients
     * include the filename in the Content-Disposition header.
     */
    static class NamedByteArrayResource extends ByteArrayResource {
        private final String filename;

        public NamedByteArrayResource(byte[] byteArray, String filename) {
            super(byteArray);
            this.filename = filename;
        }

        @Override
        public String getFilename() {
            return this.filename;
        }
    }
}

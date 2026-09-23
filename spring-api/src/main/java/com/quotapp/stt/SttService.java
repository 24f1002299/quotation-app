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
 * Service orchestrating Speech-to-Text calls to xAI Grok STT and OpenAI
 * Whisper.
 *
 * <p>
 * Key constraints:
 * <ul>
 * <li>API keys stay strictly server-side — never returned to the mobile
 * app.</li>
 * <li>Audio bytes are passed in-memory and discarded immediately; no persistent
 * audio storage.</li>
 * <li>Raw audio and credentials are never written to application logs.</li>
 * <li>Trade catalogue terms are injected for key-term biasing / prompt
 * hints.</li>
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
    private final boolean devMockEnabled;
    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public SttService(
            @Value("${quotapp.stt.default-provider:whisper}") String defaultProvider,
            @Value("${quotapp.stt.grok.api-key:}") String xaiApiKey,
            @Value("${quotapp.stt.grok.url:https://api.x.ai/v1/stt}") String xaiSttUrl,
            @Value("${quotapp.stt.grok.timeout-seconds:15}") int grokTimeoutSeconds,
            @Value("${quotapp.stt.whisper.api-key:}") String openaiApiKey,
            @Value("${quotapp.stt.whisper.url:https://api.openai.com/v1/audio/transcriptions}") String openaiSttUrl,
            @Value("${quotapp.stt.whisper.model:whisper-1}") String openaiModel,
            @Value("${quotapp.stt.whisper.timeout-seconds:15}") int whisperTimeoutSeconds,
            @Value("${quotapp.stt.dev-mock-enabled:false}") boolean devMockEnabled,
            ObjectMapper objectMapper) {
        this.defaultProvider = defaultProvider.trim().toLowerCase();
        this.xaiApiKey = xaiApiKey.trim();
        this.xaiSttUrl = xaiSttUrl.trim();
        this.openaiApiKey = openaiApiKey.trim();
        this.openaiSttUrl = openaiSttUrl.trim();
        this.openaiModel = openaiModel.trim();
        this.devMockEnabled = devMockEnabled;
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
     * Transcribes an in-memory audio byte array using the selected or default STT
     * provider.
     *
     * @param audioBytes        raw audio bytes (M4A/AAC/WAV/MP3)
     * @param originalFilename  filename with extension (used by provider to infer
     *                          container format)
     * @param languageHint      optional ISO language code ("hi", "mr", "en")
     * @param requestedProvider optional provider override ("grok" or "whisper")
     * @return SttResult containing the raw transcript and benchmark metrics
     */
    @Value("${spring.profiles.active:}")
    private String activeProfile;

    public SttResult transcribe(
            byte[] audioBytes,
            String originalFilename,
            String languageHint,
            String requestedProvider) {        String provider = StringUtils.hasText(requestedProvider)
                ? requestedProvider.trim().toLowerCase()
                : defaultProvider;

        // Normalize aliases: "groq", "groq-whisper", "openai", "whisper-1" all mean
        // the Whisper-compatible endpoint (Groq whisper-large-v3-turbo in this project).
        // "grok"/"xai" means xAI Grok STT (requires XAI_API_KEY).
        if (provider.equals("groq") || provider.equals("groq-whisper")
                || provider.equals("openai") || provider.equals("whisper-1")
                || provider.equals("whisper-large-v3-turbo")) {
            provider = "whisper";
        }

        String safeFilename = StringUtils.hasText(originalFilename) ? originalFilename : "audio.m4a";
        long start = System.currentTimeMillis();

        String transcript;
        String detectedLanguage = null;
        double confidence = 0.9;
        try {
            if ("whisper".equals(provider)) {
                VerboseParse parsed = callOpenAiWhisper(audioBytes, safeFilename, languageHint);
                transcript = parsed.text();
                detectedLanguage = parsed.language();
                confidence = parsed.confidence();
            } else if ("grok".equals(provider) || "xai".equals(provider)) {
                // Explicit Grok request but no Groq alternative confusion:
                // if no XAI key is configured, route straight to Groq Whisper
                // instead of failing with "Incorrect API key".
                if (!StringUtils.hasText(xaiApiKey) && StringUtils.hasText(openaiApiKey)) {
                    log.warn("Grok requested but XAI_API_KEY is empty; using Groq Whisper instead");
                    provider = "whisper-fallback";
                    VerboseParse fallback = callOpenAiWhisper(audioBytes, safeFilename, languageHint);
                    transcript = fallback.text();
                    detectedLanguage = fallback.language();
                    confidence = fallback.confidence();
                } else {
                    // Default to Grok STT
                    provider = "grok";
                    try {
                        transcript = callGrokStt(audioBytes, safeFilename, languageHint);
                    } catch (Exception grokEx) {
                        // Automatic fallback: if Grok fails (bad key, quota, 400/401/403)
                        // and a Whisper-compatible key is configured (OpenAI or Groq),
                        // retry with Whisper instead of surfacing a raw provider error.
                        if (StringUtils.hasText(openaiApiKey)) {
                            log.warn("Grok STT failed ({}), falling back to whisper", grokEx.getMessage());
                            VerboseParse fallback = callOpenAiWhisper(audioBytes, safeFilename, languageHint);
                            transcript = fallback.text();
                            detectedLanguage = fallback.language();
                            confidence = fallback.confidence();
                            provider = "whisper-fallback";
                        } else {
                            throw grokEx;
                        }
                    }
                }
            } else {
                // Unknown provider string: default to Groq Whisper (this project uses Groq).
                log.warn("Unknown STT provider '{}', defaulting to whisper (Groq)", provider);
                provider = "whisper";
                VerboseParse fallback = callOpenAiWhisper(audioBytes, safeFilename, languageHint);
                transcript = fallback.text();
                detectedLanguage = fallback.language();
                confidence = fallback.confidence();
            }
        } catch (Exception ex) {
            boolean isDev = activeProfile != null && activeProfile.toLowerCase().contains("dev");
            String msg = ex.getMessage() != null ? ex.getMessage() : "";
            String lowerMsg = msg.toLowerCase();
            // NOTE: deliberately narrow — generic "400"/"invalid"/"bad request"
            // must NOT trigger the mock, otherwise real client bugs (e.g. Groq
            // invalid_prompt when prompt > 896 chars) get masked by the same
            // canned transcript and every sample "looks like it doesn't update".
            boolean isAuthLike = lowerMsg.contains("403") || lowerMsg.contains("401")
                    || lowerMsg.contains("credits") || lowerMsg.contains("licenses")
                    || lowerMsg.contains("not configured")
                    || lowerMsg.contains("incorrect api key") || lowerMsg.contains("invalid_api_key")
                    || lowerMsg.contains("invalid api key")
                    || lowerMsg.contains("unauthorized") || lowerMsg.contains("forbidden");
            // Dev mock must be opt-in (STT_DEV_MOCK_ENABLED=true) or when keys are placeholders/unconfigured.
            boolean noKeysConfigured = isPlaceholderKey(openaiApiKey) && isPlaceholderKey(xaiApiKey);
            if (isDev && isAuthLike && (devMockEnabled || noKeysConfigured
                    || lowerMsg.contains("not configured"))) {
                log.warn(
                        "STT provider '{}' failed with credit/auth error: {}. Dev fallback: returning sample contractor transcript.",
                        provider, msg);
                transcript = getDevFallbackTranscript(languageHint);
                provider = provider + "-dev-mock";
            } else {
                throw ex;
            }
        }

        long latencyMs = System.currentTimeMillis() - start;
        log.info("STT completed: provider={}, audioBytes={}, latencyMs={}, languageHint={}",
                provider, audioBytes.length, latencyMs, languageHint);
        // Dev-only transcript preview so a wrong/empty transcript can be diagnosed
        // without dumping full audio. Never log API keys here.
        if (transcript != null && !transcript.isBlank()) {
            String preview = transcript.length() > 160 ? transcript.substring(0, 160) + "…" : transcript;
            log.info("STT transcript preview ({} chars): {}", transcript.length(), preview);
        } else {
            log.warn("STT returned empty transcript for provider={}, audioBytes={}", provider, audioBytes.length);
        }

        return new SttResult(
                transcript,
                provider,
                languageHint,
                latencyMs,
                audioBytes.length,
                detectedLanguage,
                confidence);
    }

    private String getDevFallbackTranscript(String languageHint) {
        String lang = languageHint != null ? languageHint.toLowerCase() : "auto";
        if ("mr".equals(lang)) {
            return "किचन भिंतीवरील टाइल्स 120 चौरस फूट, बाथरूम फरशी 80 चौरस फूट";
        } else if ("hi".equals(lang)) {
            return "किचन की दीवार की टाइलें 120 वर्ग फुट, बाथरूम फर्श 80 वर्ग फुट";
        } else {
            return "Kitchen wall tiles 120 sq ft, floor tiles 80 sq ft, border 20 rft";
        }
    }

    /**
     * Calls xAI Grok STT API (POST https://api.x.ai/v1/stt).
     *
     * <p>
     * Features:
     * <ul>
     * <li>Batch rate: $0.10/hour audio (~72% cheaper than Whisper).</li>
     * <li>Inverse Text Normalization (ITN): converts spoken numbers and units into
     * digits.</li>
     * <li>Supports M4A, AAC, WAV, MP3.</li>
     * </ul>
     */
    private boolean isPlaceholderKey(String key) {
        if (!StringUtils.hasText(key)) return true;
        String k = key.trim().toLowerCase();
        return k.contains("replace") || k.contains("your_key") || k.contains("xai-replace") || k.contains("gsk-replace");
    }

    private String callGrokStt(byte[] audioBytes, String filename, String languageHint) {
        if (isPlaceholderKey(xaiApiKey)) {
            throw new IllegalStateException(
                    "XAI_API_KEY is missing or unconfigured in spring-api/.env. Set XAI_API_KEY or set DEFAULT_STT_PROVIDER=whisper.");
        }

        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();

        // Enable ITN formatting (numbers/units as digits) per xAI docs (-F format=true).
        body.add("format", "true");

        String normalizedLang = normalizeLanguageHint(languageHint);
        if (normalizedLang != null) {
            body.add("language", normalizedLang);
        }

        // Domain key-terms for contractor vocabulary (xAI uses repeated 'keyterm' fields).
        for (String term : ContractorCatalogTerms.TERMS) {
            if (term != null && !term.isBlank()) {
                body.add("keyterm", term);
                if (body.get("keyterm").size() >= 100) {
                    break; // xAI supports up to 100 key-terms
                }
            }
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
     * Calls Whisper-compatible STT API (Groq in this project:
     * https://api.groq.com/openai/v1/audio/transcriptions with
     * model whisper-large-v3-turbo; OpenAI-compatible shape).
     *
     * <p>Requests {@code verbose_json} so we get the provider-detected language
     * plus per-segment {@code no_speech_prob}/{@code avg_logprob}. Those let us
     * distinguish "contractor spoke Hindi, transcribed with low accuracy" from
     * "mic captured unintelligible noise and Whisper hallucinated fluent text
     * in an unrelated language (e.g. Icelandic)" — the latter must surface as
     * a mic/clarity warning, never as the contractor's words.
     */
    private VerboseParse callOpenAiWhisper(byte[] audioBytes, String filename, String languageHint) {
        if (isPlaceholderKey(openaiApiKey)) {
            throw new IllegalStateException(
                    "OPENAI_API_KEY is missing or unconfigured in spring-api/.env. " +
                    "Set a valid Groq Whisper key (gsk-...) from https://console.groq.com in spring-api/.env, " +
                    "or set STT_DEV_MOCK_ENABLED=true in .env for mock testing.");
        }

        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        body.add("model", openaiModel);
        body.add("prompt", ContractorCatalogTerms.asPromptString(languageHint));
        body.add("response_format", "verbose_json");
        body.add("temperature", "0");

        String normalizedLang = normalizeLanguageHint(languageHint);
        if (normalizedLang != null) {
            body.add("language", normalizedLang);
        }

        ByteArrayResource fileResource = new NamedByteArrayResource(audioBytes, filename);
        body.add("file", fileResource);

        try {
            String rawResponse = postTranscription(body);
            return parseVerboseTranscript(rawResponse);
        } catch (Exception e) {
            String msg = e.getMessage() != null ? e.getMessage() : "";
            String lower = msg.toLowerCase();
            // Provider doesn't accept verbose_json/temperature (model or proxy
            // difference)? Retry once with the plain OpenAI shape so a param
            // incompatibility never takes transcription fully offline.
            if (lower.contains("response_format") || lower.contains("verbose_json")
                    || lower.contains("temperature")) {
                log.warn("Verbose STT params rejected ({}), retrying with plain json", msg);
                try {
                    MultiValueMap<String, Object> plainBody = new LinkedMultiValueMap<>();
                    plainBody.add("model", openaiModel);
                    plainBody.add("prompt", ContractorCatalogTerms.asPromptString(languageHint));
                    if (normalizedLang != null) {
                        plainBody.add("language", normalizedLang);
                    }
                    plainBody.add("file", new NamedByteArrayResource(audioBytes, filename));
                    String rawResponse = postTranscription(plainBody);
                    String text = parseTranscriptFromResponse(rawResponse);
                    return new VerboseParse(text, null, 0.9);
                } catch (Exception retryEx) {
                    log.error("OpenAI Whisper API call failed: {}", retryEx.getMessage());
                    throw new RuntimeException("OpenAI Whisper transcription failed: " + retryEx.getMessage(), retryEx);
                }
            }
            log.error("OpenAI Whisper API call failed: {}", e.getMessage());
            throw new RuntimeException("OpenAI Whisper transcription failed: " + e.getMessage(), e);
        }
    }

    private String postTranscription(MultiValueMap<String, Object> body) {
        return restClient.post()
                .uri(openaiSttUrl)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + openaiApiKey)
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(body)
                .retrieve()
                .body(String.class);
    }

    /**
     * Extracts transcript text from STT JSON response ({ "text": "..." } or {
     * "transcript": "..." }).
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
     * Parses a verbose_json transcription response into text, detected language
     * (normalized to ISO code) and a 0.0-1.0 speech confidence. Falls back to
     * plain text parsing when the provider returns simple json.
     */
    private VerboseParse parseVerboseTranscript(String rawResponse) {
        String text = parseTranscriptFromResponse(rawResponse);
        if (!StringUtils.hasText(rawResponse)) {
            return new VerboseParse(text, null, 0.0);
        }
        try {
            JsonNode root = objectMapper.readTree(rawResponse);
            String detected = null;
            if (root.has("language")) {
                detected = normalizeDetectedLanguage(root.get("language").asText());
            }
            double confidence = 0.9;
            JsonNode segments = root.get("segments");
            if (segments != null && segments.isArray() && !segments.isEmpty()) {
                double noSpeechSum = 0.0;
                double logprobSum = 0.0;
                int n = 0;
                for (JsonNode seg : segments) {
                    double noSpeech = seg.has("no_speech_prob") ? seg.get("no_speech_prob").asDouble(0.0) : 0.0;
                    double avgLogprob = seg.has("avg_logprob") ? seg.get("avg_logprob").asDouble(-0.3) : -0.3;
                    noSpeechSum += Math.min(1.0, Math.max(0.0, noSpeech));
                    // avg_logprob is <= 0 (0 = perfect). Clamp pathological values.
                    logprobSum += Math.min(0.0, Math.max(-5.0, avgLogprob));
                    n++;
                }
                double avgNoSpeech = noSpeechSum / n;
                double avgLogprob = logprobSum / n;
                confidence = (1.0 - avgNoSpeech) * 0.7 + Math.exp(avgLogprob) * 0.3;
                confidence = Math.min(1.0, Math.max(0.0, confidence));
                log.info("STT quality: detectedLanguage={}, segments={}, avgNoSpeechProb={}, avgLogprob={}, confidence={}",
                        detected, n, String.format("%.3f", avgNoSpeech), String.format("%.3f", avgLogprob), String.format("%.3f", confidence));
            }
            return new VerboseParse(text, detected, confidence);
        } catch (Exception e) {
            log.warn("Failed to parse verbose_json, using plain text: {}", e.getMessage());
            return new VerboseParse(text, null, 0.9);
        }
    }

    /**
     * Normalizes provider-detected language labels to ISO codes. Groq/OpenAI
     * verbose_json returns full English names ("english", "hindi", "marathi",
     * "icelandic"); explicit codes pass through untouched.
     */
    private String normalizeDetectedLanguage(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String lang = raw.trim().toLowerCase();
        return switch (lang) {
            case "english" -> "en";
            case "hindi" -> "hi";
            case "marathi" -> "mr";
            default -> lang.length() > 2 ? lang : lang;
        };
    }

    /** Parsed verbose_json transcription: text, detected ISO language, confidence. */
    record VerboseParse(String text, String language, double confidence) {}

    /**
     * Normalizes UI language hints to provider codes.
     * In Auto / Hinglish mode, returns null so the provider auto-detects the
     * language instead of being locked to English. Locking auto speech to 'en'
     * mistranscribes Hindi/Marathi-dominant audio and makes every re-record
     * look "wrong". Explicit hi/mr/en codes are passed through untouched.
     */
    private String normalizeLanguageHint(String languageHint) {
        if (!StringUtils.hasText(languageHint)) {
            return null;
        }
        String lang = languageHint.trim().toLowerCase();
        if (lang.equals("auto") || lang.equals("und") || lang.equals("default") || lang.equals("hinglish")) {
            return null;
        }
        return lang;
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

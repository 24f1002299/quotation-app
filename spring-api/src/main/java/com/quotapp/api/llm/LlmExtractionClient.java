package com.quotapp.api.llm;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.quotapp.api.dto.CatalogItemDto;
import com.quotapp.api.dto.RateMemoryItemDto;
import com.quotapp.api.resilience.ExtractionCircuitBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.util.*;

/**
 * Constrained LLM client interacting with xAI Grok (or OpenAI) chat completions.
 *
 * <p>Enforces:
 * <ul>
 *   <li>Strict trade catalog boundaries in prompt.</li>
 *   <li>Strict JSON output format with zero model-computed arithmetic totals.</li>
 *   <li>Circuit breaker and bounded retries for transient failure.</li>
 *   <li>Redacted structured logs (never logs full transcripts or API secrets).</li>
 * </ul>
 */
@Component
public class LlmExtractionClient {

    private static final Logger log = LoggerFactory.getLogger(LlmExtractionClient.class);

    private final String provider;
    private final String grokApiKey;
    private final String grokUrl;
    private final String grokModel;
    private final String openaiApiKey;
    private final String openaiUrl;
    private final String openaiModel;
    private final int maxRetries;
    private final ObjectMapper objectMapper;
    private final ExtractionCircuitBreaker circuitBreaker;
    private final RestClient restClient;

    public LlmExtractionClient(
        @Value("${quotapp.llm.provider:grok}") String provider,
        @Value("${quotapp.llm.grok.api-key:}") String grokApiKey,
        @Value("${quotapp.llm.grok.url:https://api.x.ai/v1/chat/completions}") String grokUrl,
        @Value("${quotapp.llm.grok.model:grok-2-mini}") String grokModel,
        @Value("${quotapp.llm.openai.api-key:}") String openaiApiKey,
        @Value("${quotapp.llm.openai.url:https://api.openai.com/v1/chat/completions}") String openaiUrl,
        @Value("${quotapp.llm.openai.model:gpt-4o-mini}") String openaiModel,
        @Value("${quotapp.llm.grok.timeout-seconds:10}") int timeoutSeconds,
        @Value("${quotapp.llm.max-retries:2}") int maxRetries,
        ObjectMapper objectMapper,
        ExtractionCircuitBreaker circuitBreaker
    ) {
        this.provider = provider.trim().toLowerCase();
        this.grokApiKey = grokApiKey != null ? grokApiKey.trim() : "";
        this.grokUrl = grokUrl.trim();
        this.grokModel = grokModel.trim();
        this.openaiApiKey = openaiApiKey != null ? openaiApiKey.trim() : "";
        this.openaiUrl = openaiUrl.trim();
        this.openaiModel = openaiModel.trim();
        this.maxRetries = Math.max(0, maxRetries);
        this.objectMapper = objectMapper;
        this.circuitBreaker = circuitBreaker;

        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(timeoutSeconds));
        requestFactory.setReadTimeout(Duration.ofSeconds(timeoutSeconds));

        this.restClient = RestClient.builder()
            .requestFactory(requestFactory)
            .build();
    }

    public record RawExtractedItem(
        String catalogItemId,
        Double quantity,
        String unit,
        String sourceSpan
    ) {}

    public record RawUnknownItem(
        String sourceSpan,
        String suspectedTerm,
        String reason
    ) {}

    public record RawExtractionResult(
        List<RawExtractedItem> items,
        List<RawUnknownItem> unknowns
    ) {}

    /**
     * Executes constrained extraction against the upstream LLM with retries and circuit breaker protection.
     */
    public RawExtractionResult extract(
        String transcript,
        String trade,
        List<CatalogItemDto> catalogEntries,
        List<RateMemoryItemDto> rateMemory,
        String language
    ) {
        if (!circuitBreaker.canExecute()) {
            throw new IllegalStateException("Extraction provider circuit breaker is OPEN. Upstream service temporarily unavailable.");
        }

        String activeApiKey = "openai".equals(provider) ? openaiApiKey : grokApiKey;
        String activeUrl = "openai".equals(provider) ? openaiUrl : grokUrl;
        String activeModel = "openai".equals(provider) ? openaiModel : grokModel;

        if (!StringUtils.hasText(activeApiKey)) {
            log.warn("LLM API key not configured for provider={}. Falling back to rule-based catalog matcher.", provider);
            return fallbackExtract(transcript, catalogEntries);
        }

        String systemPrompt = buildSystemPrompt(trade, catalogEntries, rateMemory);
        String userPrompt = "Contractor Transcript: \"" + transcript + "\"";

        Map<String, Object> requestPayload = Map.of(
            "model", activeModel,
            "temperature", 0.0,
            "response_format", Map.of("type", "json_object"),
            "messages", List.of(
                Map.of("role", "system", "content", systemPrompt),
                Map.of("role", "user", "content", userPrompt)
            )
        );

        String redactedSnippet = sanitizeForLogs(transcript);
        log.info("Sending constrained LLM request: provider={}, model={}, trade={}, snippet='{}'",
            provider, activeModel, trade, redactedSnippet);

        int attempts = 0;
        Exception lastException = null;

        while (attempts <= maxRetries) {
            attempts++;
            try {
                String responseBody = restClient.post()
                    .uri(activeUrl)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + activeApiKey)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(requestPayload)
                    .retrieve()
                    .body(String.class);

                circuitBreaker.recordSuccess();
                return parseLlmResponse(responseBody, catalogEntries);

            } catch (Exception ex) {
                lastException = ex;
                log.warn("LLM extraction call attempt {} failed for trade={}, error={}", attempts, trade, ex.getMessage());
                if (attempts <= maxRetries) {
                    try {
                        Thread.sleep(200L * attempts); // Exponential backoff
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
        }

        circuitBreaker.recordFailure();
        log.error("All {} LLM extraction attempts failed for trade={}", attempts, trade);
        throw new RuntimeException("LLM extraction failed: " + (lastException != null ? lastException.getMessage() : "Unknown error"), lastException);
    }

    private String buildSystemPrompt(String trade, List<CatalogItemDto> catalogEntries, List<RateMemoryItemDto> rateMemory) {
        StringBuilder sb = new StringBuilder();
        sb.append("You are an expert quotation extraction engine for Indian contractors (tiling, painting).\n");
        sb.append("Your task is to parse spoken transcripts in Hindi, Marathi, Hinglish, or English into structured line items.\n\n");
        sb.append("### STRICT RULES:\n");
        sb.append("1. Extract ONLY items from the allowed catalog below for trade: '").append(trade).append("'.\n");
        sb.append("2. Match every item strictly to one of the catalog item IDs.\n");
        sb.append("3. DO NOT calculate amounts, subtotals, grand totals, or GST under any circumstances. Never output 'amount' or 'total'.\n");
        sb.append("4. If the transcript mentions work, trades, or materials outside this catalog, or ambiguous requests, put them in 'unknowns'. DO NOT guess or hallucinate.\n");
        sb.append("5. Output ONLY valid JSON matching this schema:\n");
        sb.append("{\n  \"items\": [\n    {\"catalogItemId\": \"id_from_catalog\", \"quantity\": 120.0, \"unit\": \"sq ft\", \"sourceSpan\": \"exact words\"}\n  ],\n");
        sb.append("  \"unknowns\": [\n    {\"sourceSpan\": \"exact words\", \"suspectedTerm\": \"optional guess\", \"reason\": \"explanation\"}\n  ]\n}\n\n");

        sb.append("### ALLOWED CATALOG ITEMS FOR ").append(trade.toUpperCase(Locale.ROOT)).append(":\n");
        for (CatalogItemDto item : catalogEntries) {
            sb.append("- ID: ").append(item.id())
              .append(", Name: ").append(item.displayName())
              .append(", DefaultUnit: ").append(item.defaultUnit());
            if (item.synonyms() != null && !item.synonyms().isEmpty()) {
                sb.append(", Synonyms: ").append(String.join(", ", item.synonyms()));
            }
            sb.append("\n");
        }

        return sb.toString();
    }

    private RawExtractionResult parseLlmResponse(String rawJson, List<CatalogItemDto> catalogEntries) {
        List<RawExtractedItem> items = new ArrayList<>();
        List<RawUnknownItem> unknowns = new ArrayList<>();

        try {
            JsonNode root = objectMapper.readTree(rawJson);
            // Handle chat completion format { "choices": [ { "message": { "content": "{...}" } } ] }
            JsonNode contentNode = root;
            if (root.has("choices") && root.get("choices").isArray() && !root.get("choices").isEmpty()) {
                JsonNode choice = root.get("choices").get(0);
                if (choice.has("message") && choice.get("message").has("content")) {
                    String textContent = choice.get("message").get("content").asText();
                    contentNode = objectMapper.readTree(textContent);
                }
            }

            // Extract items
            if (contentNode.has("items") && contentNode.get("items").isArray()) {
                for (JsonNode itemNode : contentNode.get("items")) {
                    String catalogId = itemNode.has("catalogItemId") ? itemNode.get("catalogItemId").asText() : "";
                    double qty = itemNode.has("quantity") ? itemNode.get("quantity").asDouble() : 1.0;
                    String unit = itemNode.has("unit") ? itemNode.get("unit").asText() : "sq ft";
                    String span = itemNode.has("sourceSpan") ? itemNode.get("sourceSpan").asText() : "";

                    // Verify catalogId belongs to allowed catalog
                    boolean allowed = catalogEntries.stream().anyMatch(c -> c.id().equalsIgnoreCase(catalogId));
                    if (allowed) {
                        items.add(new RawExtractedItem(catalogId, qty, unit, span));
                    } else if (!catalogId.isBlank()) {
                        unknowns.add(new RawUnknownItem(span.isEmpty() ? catalogId : span, catalogId, "Item not in allowed catalog"));
                    }
                }
            }

            // Extract unknowns
            if (contentNode.has("unknowns") && contentNode.get("unknowns").isArray()) {
                for (JsonNode unkNode : contentNode.get("unknowns")) {
                    String span = unkNode.has("sourceSpan") ? unkNode.get("sourceSpan").asText() : "unknown";
                    String suspected = unkNode.has("suspectedTerm") ? unkNode.get("suspectedTerm").asText() : null;
                    String reason = unkNode.has("reason") ? unkNode.get("reason").asText() : "Unrecognized item";
                    unknowns.add(new RawUnknownItem(span, suspected, reason));
                }
            }

        } catch (Exception e) {
            log.warn("Failed to parse LLM structured output JSON: {}", e.getMessage());
            unknowns.add(new RawUnknownItem("transcript", null, "Could not parse model output: " + e.getMessage()));
        }

        return new RawExtractionResult(items, unknowns);
    }

    /**
     * Fallback catalog matcher when LLM is unavailable or unconfigured (offline / local dev).
     */
    public RawExtractionResult fallbackExtract(String transcript, List<CatalogItemDto> catalogEntries) {
        List<RawExtractedItem> items = new ArrayList<>();
        List<RawUnknownItem> unknowns = new ArrayList<>();

        java.util.regex.Pattern numPattern = java.util.regex.Pattern.compile("(\\d+(\\.\\d+)?)");

        for (CatalogItemDto catalogItem : catalogEntries) {
            List<String> keywords = new ArrayList<>();
            keywords.add(catalogItem.id());
            keywords.add(catalogItem.displayName());
            if (catalogItem.synonyms() != null) {
                keywords.addAll(catalogItem.synonyms());
            }

            for (String kw : keywords) {
                if (kw == null || kw.isBlank()) continue;
                int idx = transcript.toLowerCase(Locale.ROOT).indexOf(kw.toLowerCase(Locale.ROOT));
                if (idx >= 0) {
                    int searchStart = Math.max(0, idx - 30);
                    int searchEnd = Math.min(transcript.length(), idx + kw.length() + 30);
                    String window = transcript.substring(searchStart, searchEnd);

                    java.util.regex.Matcher m = numPattern.matcher(window);
                    double qty = 1.0;
                    if (m.find()) {
                        try {
                            qty = Double.parseDouble(m.group(1));
                        } catch (NumberFormatException ignored) {}
                    }
                    items.add(new RawExtractedItem(catalogItem.id(), qty, catalogItem.defaultUnit(), transcript.substring(idx, Math.min(transcript.length(), idx + kw.length()))));
                    break;
                }
            }
        }

        if (items.isEmpty()) {
            unknowns.add(new RawUnknownItem(transcript.length() > 35 ? transcript.substring(0, 35) + "..." : transcript, null, "No matching catalog items found"));
        }

        return new RawExtractionResult(items, unknowns);
    }

    private static String sanitizeForLogs(String transcript) {
        if (transcript == null || transcript.isBlank()) return "";
        String clean = transcript.trim().replaceAll("\\s+", " ");
        return clean.length() <= 30 ? clean : clean.substring(0, 27) + "...";
    }
}

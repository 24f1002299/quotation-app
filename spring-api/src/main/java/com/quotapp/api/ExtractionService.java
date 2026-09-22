package com.quotapp.api;

import com.quotapp.api.dto.*;
import com.quotapp.api.llm.LlmExtractionClient;
import com.quotapp.api.llm.LlmExtractionClient.RawExtractedItem;
import com.quotapp.api.llm.LlmExtractionClient.RawExtractionResult;
import com.quotapp.api.llm.LlmExtractionClient.RawUnknownItem;
import com.quotapp.api.repository.ExtractionJobRepository;
import com.quotapp.security.RequestIdFilter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.*;

/**
 * Service that orchestrates constrained LLM extraction, enforces domain invariants,
 * manages rate memory provenance, and handles asynchronous job execution.
 */
@Service
public class ExtractionService {

    private static final Logger log = LoggerFactory.getLogger(ExtractionService.class);

    private final LlmExtractionClient llmClient;
    private final ExtractionJobRepository jobRepository;
    private final long latencyBudgetMs;

    public ExtractionService(
        LlmExtractionClient llmClient,
        ExtractionJobRepository jobRepository,
        @Value("${quotapp.llm.latency-budget-ms:5000}") long latencyBudgetMs
    ) {
        this.llmClient = llmClient;
        this.jobRepository = jobRepository;
        this.latencyBudgetMs = latencyBudgetMs;
    }

    /**
     * Executes synchronous or bounded extraction.
     */
    public ExtractResponse extract(ExtractRequest request) {
        RawExtractionResult rawResult = llmClient.extract(
            request.transcript(),
            request.trade(),
            request.catalogEntries(),
            request.rateMemory(),
            request.language()
        );

        return mapToExtractResponse(request, rawResult);
    }

    /**
     * Creates and records a minimal extraction job.
     */
    public ExtractionJob createJob(String userId, ExtractRequest request) {
        String jobId = UUID.randomUUID().toString();
        ExtractionJob job = ExtractionJob.createPending(jobId, userId, request.trade(), request.transcript());
        jobRepository.save(job);
        return job;
    }

    /**
     * Retrieves an extraction job with strict user ownership scoping.
     */
    public Optional<ExtractionJob> getJob(String jobId, String userId) {
        return jobRepository.findByIdAndUserId(jobId, userId);
    }

    /**
     * Completes or updates an extraction job.
     */
    public void recordJobCompletion(ExtractionJob job, ExtractResponse response) {
        ExtractionJob completed = job.complete(response);
        jobRepository.save(completed);
    }

    /**
     * Records a job failure.
     */
    public void recordJobFailure(ExtractionJob job, String errorMessage) {
        ExtractionJob failed = job.fail(errorMessage);
        jobRepository.save(failed);
    }

    /**
     * Maps raw LLM extraction output to validated contract response.
     * Enforces strict rate provenance and absolute exclusion of arithmetic totals.
     */
    public ExtractResponse mapToExtractResponse(ExtractRequest request, RawExtractionResult rawResult) {
        List<ExtractedLineItemDto> lineItems = new ArrayList<>();
        List<ExplicitUnknownDto> unknowns = new ArrayList<>();

        // Map rate memory by catalogItemId + ":" + normalizedUnit
        Map<String, Long> rateMemoryMap = new HashMap<>();
        if (request.rateMemory() != null) {
            for (RateMemoryItemDto rm : request.rateMemory()) {
                String normUnit = ContractorUnit.normalize(rm.unit());
                rateMemoryMap.put(rm.catalogItemId().toLowerCase(Locale.ROOT) + ":" + normUnit, rm.unitRatePaise());
            }
        }

        // Map catalog items by ID for O(1) lookup
        Map<String, CatalogItemDto> catalogMap = new HashMap<>();
        for (CatalogItemDto item : request.catalogEntries()) {
            catalogMap.put(item.id().toLowerCase(Locale.ROOT), item);
        }

        // Process raw items
        if (rawResult.items() != null) {
            for (RawExtractedItem rawItem : rawResult.items()) {
                String catId = rawItem.catalogItemId() != null ? rawItem.catalogItemId().toLowerCase(Locale.ROOT) : "";
                CatalogItemDto catalogItem = catalogMap.get(catId);

                if (catalogItem == null) {
                    // Item ID not found in chosen trade catalog -> isolate into explicit unknowns
                    unknowns.add(new ExplicitUnknownDto(
                        rawItem.sourceSpan() != null ? rawItem.sourceSpan() : catId,
                        catId,
                        "Item not found in " + request.trade() + " catalog",
                        0.2
                    ));
                    continue;
                }

                String unit = rawItem.unit() != null && ContractorUnit.isRecognized(rawItem.unit())
                    ? ContractorUnit.normalize(rawItem.unit())
                    : catalogItem.defaultUnit();

                String rateKey = catalogItem.id().toLowerCase(Locale.ROOT) + ":" + ContractorUnit.normalize(unit);
                Long ratePaise = rateMemoryMap.get(rateKey);
                RateSource rateSource = ratePaise != null ? RateSource.RATE_MEMORY : RateSource.UNKNOWN;

                SourceSpan span = new SourceSpan(rawItem.sourceSpan() != null ? rawItem.sourceSpan() : catalogItem.displayName());

                ExtractedLineItemDto item = new ExtractedLineItemDto(
                    catalogItem.id(),
                    catalogItem.displayName(),
                    rawItem.quantity() != null && rawItem.quantity() > 0 ? rawItem.quantity() : 1.0,
                    unit,
                    ratePaise,
                    rateSource,
                    0.95,
                    span,
                    null
                );
                lineItems.add(item);
            }
        }

        // Process raw unknowns
        if (rawResult.unknowns() != null) {
            for (RawUnknownItem unk : rawResult.unknowns()) {
                unknowns.add(new ExplicitUnknownDto(
                    unk.sourceSpan() != null ? unk.sourceSpan() : "unknown",
                    unk.suspectedTerm(),
                    unk.reason() != null ? unk.reason() : "Unrecognized item",
                    0.1
                ));
            }
        }

        // Check if completely empty
        if (lineItems.isEmpty() && unknowns.isEmpty()) {
            unknowns.add(new ExplicitUnknownDto(
                request.transcript().length() > 40 ? request.transcript().substring(0, 37) + "..." : request.transcript(),
                null,
                "No line items or recognized work identified",
                0.0
            ));
        }

        boolean isUncertain = lineItems.isEmpty() || !unknowns.isEmpty();
        Map<String, Object> uncertaintyMetadata = Map.of(
            "isUncertain", isUncertain,
            "lineItemCount", lineItems.size(),
            "unknownCount", unknowns.size(),
            "requiresReview", true
        );

        return new ExtractResponse(
            request.schemaVersion() != null ? request.schemaVersion() : "1.0",
            request.trade(),
            lineItems,
            unknowns,
            uncertaintyMetadata,
            request.version() != null ? request.version() : 1,
            true,
            RequestIdFilter.getCurrentRequestId()
        );
    }

    public long getLatencyBudgetMs() {
        return latencyBudgetMs;
    }
}

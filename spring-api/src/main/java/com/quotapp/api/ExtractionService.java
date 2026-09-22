package com.quotapp.api;

import com.quotapp.api.dto.*;
import com.quotapp.security.RequestIdFilter;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Service that extracts structured quotation line items, unknowns, and uncertainties
 * according to the contract.
 *
 * <p>Invariant:
 * <ul>
 *   <li>Rates come strictly from {@link RateMemoryItemDto} (marked {@link RateSource#RATE_MEMORY})
 *       or are flagged {@link RateSource#UNKNOWN}.</li>
 *   <li>Calculated totals (amount, subtotal, grandTotal) are strictly excluded from output.</li>
 * </ul>
 */
@Service
public class ExtractionService {

    private static final Pattern NUMBER_PATTERN = Pattern.compile("(\\d+(\\.\\d+)?)");

    /**
     * Extracts line items and explicit unknowns from the request transcript.
     */
    public ExtractResponse extract(ExtractRequest request) {
        String transcript = request.transcript();
        List<ExtractedLineItemDto> lineItems = new ArrayList<>();
        List<ExplicitUnknownDto> unknowns = new ArrayList<>();

        // Map rate memory by catalogItemId + ":" + normalizedUnit
        Map<String, Long> rateMemoryMap = new HashMap<>();
        if (request.rateMemory() != null) {
            for (RateMemoryItemDto rm : request.rateMemory()) {
                String normUnit = ContractorUnit.normalize(rm.unit());
                rateMemoryMap.put(rm.catalogItemId() + ":" + normUnit, rm.unitRatePaise());
            }
        }

        // Iterate through catalog entries and detect matching phrases in transcript
        for (CatalogItemDto catalogItem : request.catalogEntries()) {
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
                    // Found a candidate entity. Look for numbers nearby (within next 40 chars or prior 40 chars)
                    int searchStart = Math.max(0, idx - 40);
                    int searchEnd = Math.min(transcript.length(), idx + kw.length() + 40);
                    String contextWindow = transcript.substring(searchStart, searchEnd);

                    Matcher numMatcher = NUMBER_PATTERN.matcher(contextWindow);
                    double quantity = 1.0;
                    if (numMatcher.find()) {
                        try {
                            quantity = Double.parseDouble(numMatcher.group(1));
                        } catch (NumberFormatException ignored) {}
                    }

                    String unit = catalogItem.defaultUnit();
                    // Detect unit in context window if available
                    for (ContractorUnit u : ContractorUnit.values()) {
                        if (contextWindow.toLowerCase(Locale.ROOT).contains(u.getCanonical())) {
                            unit = u.getCanonical();
                            break;
                        }
                    }

                    String rateKey = catalogItem.id() + ":" + ContractorUnit.normalize(unit);
                    Long ratePaise = rateMemoryMap.get(rateKey);
                    RateSource rateSource = ratePaise != null ? RateSource.RATE_MEMORY : RateSource.UNKNOWN;

                    SourceSpan span = new SourceSpan(idx, idx + kw.length(), transcript.substring(idx, Math.min(transcript.length(), idx + kw.length() + 15)));

                    ExtractedLineItemDto item = new ExtractedLineItemDto(
                        catalogItem.id(),
                        catalogItem.displayName(),
                        quantity,
                        unit,
                        ratePaise,
                        rateSource,
                        0.95,
                        span,
                        null
                    );
                    lineItems.add(item);
                    break; // Matched this catalog item once
                }
            }
        }

        // Check if there are explicit unknown signals (e.g. unknown keywords or phrases with numbers)
        if (lineItems.isEmpty()) {
            unknowns.add(new ExplicitUnknownDto(
                transcript.length() > 50 ? transcript.substring(0, 50) + "..." : transcript,
                null,
                "No matching items found in " + request.trade() + " catalog",
                0.2
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
}

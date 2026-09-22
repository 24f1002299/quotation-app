package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.dto.ExtractRequest;
import com.quotapp.api.dto.ExtractResponse;
import com.quotapp.security.IdempotencyService;
import com.quotapp.security.UserContext;
import com.quotapp.security.UserRateLimiter;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Controller exposing the structured quotation extraction endpoint.
 *
 * <p>Enforces:
 * <ul>
 *   <li>Supabase JWT verification via {@link UserContext}.</li>
 *   <li>User-scoped rate limiting.</li>
 *   <li>Idempotency key de-duplication.</li>
 *   <li>Contract validation (unit restrictions, size ceilings, required fields).</li>
 *   <li>Exclusion of model-generated arithmetic totals.</li>
 * </ul>
 */
@RestController
@RequestMapping("/api")
public class ExtractionController {

    private static final Logger log = LoggerFactory.getLogger(ExtractionController.class);

    private final ExtractionService extractionService;
    private final IdempotencyService idempotencyService;
    private final UserRateLimiter rateLimiter;

    @org.springframework.beans.factory.annotation.Autowired
    public ExtractionController(
        ExtractionService extractionService,
        IdempotencyService idempotencyService,
        UserRateLimiter rateLimiter
    ) {
        this.extractionService = extractionService;
        this.idempotencyService = idempotencyService;
        this.rateLimiter = rateLimiter;
    }

    /** Constructor for testing without rateLimiter */
    public ExtractionController(ExtractionService extractionService, IdempotencyService idempotencyService) {
        this(extractionService, idempotencyService, new UserRateLimiter(30));
    }

    @PostMapping(value = "/extract", consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> extract(
        @Valid @RequestBody ExtractRequest request,
        @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKeyHeader
    ) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        // Rate limit check
        if (rateLimiter != null && !rateLimiter.tryAcquire(userId)) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .body(new ErrorResponse("RATE_LIMIT_EXCEEDED", "Rate limit exceeded. Please wait a moment before trying again."));
        }

        // Determine idempotency key
        String idempotencyKey = (idempotencyKeyHeader != null && !idempotencyKeyHeader.isBlank())
            ? idempotencyKeyHeader.trim()
            : request.idempotencyKey();

        // Check for cached idempotent response
        if (idempotencyKey != null && !idempotencyKey.isBlank()) {
            Object cached = idempotencyService.get(userId, idempotencyKey);
            if (cached instanceof ExtractResponse cachedResponse) {
                log.info("Returning cached extraction response for user={}, idempotencyKey={}", userId, idempotencyKey);
                return ResponseEntity.ok(cachedResponse);
            }
        }

        log.info("Processing extraction for user={}, trade={}, transcriptLength={}, catalogCount={}",
            userId, request.trade(), request.transcript().length(), request.catalogEntries().size());

        ExtractResponse response = extractionService.extract(request);

        // Save to idempotency cache
        if (idempotencyKey != null && !idempotencyKey.isBlank()) {
            idempotencyService.put(userId, idempotencyKey, response);
        }

        return ResponseEntity.ok(response);
    }
}

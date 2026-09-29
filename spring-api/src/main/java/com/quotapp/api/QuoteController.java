package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.dto.QuoteDto;
import com.quotapp.api.exception.OwnershipViolationException;
import com.quotapp.api.repository.FeedbackRepository;
import com.quotapp.api.repository.QuoteRepository;
import com.quotapp.security.UserContext;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * Controller exposing quotation synchronization and management.
 * Day 15: Assigns human-readable display numbers on first sync while maintaining
 * the client-generated UUID as the immutable idempotency anchor.
 */
@RestController
@RequestMapping("/api/quotes")
public class QuoteController {

    private static final Logger log = LoggerFactory.getLogger(QuoteController.class);

    private final QuoteRepository quoteRepository;
    private final FeedbackRepository feedbackRepository;

    @Autowired
    public QuoteController(QuoteRepository quoteRepository, FeedbackRepository feedbackRepository) {
        this.quoteRepository = quoteRepository;
        this.feedbackRepository = feedbackRepository;
    }

    @PostMapping(value = {"", "/sync"}, consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> syncQuote(
        @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKeyHeader,
        @Valid @RequestBody QuoteDto quote
    ) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        String effectiveIdempotencyKey = (idempotencyKeyHeader != null && !idempotencyKeyHeader.isBlank())
            ? idempotencyKeyHeader.trim()
            : quote.idempotencyKey();

        QuoteDto quoteToSave = quote;
        if (effectiveIdempotencyKey != null && !effectiveIdempotencyKey.isBlank()) {
            quoteToSave = new QuoteDto(
                quote.id() != null ? quote.id() : effectiveIdempotencyKey,
                effectiveIdempotencyKey,
                quote.displayNumber(),
                quote.status(),
                quote.trade(),
                quote.clientName(),
                quote.clientPhone(),
                quote.siteAddress(),
                quote.gstPercent(),
                quote.subtotalPaise(),
                quote.gstPaise(),
                quote.grandTotalPaise(),
                quote.quoteDate(),
                quote.validityDays(),
                quote.advancePercent(),
                quote.advanceText(),
                quote.notes(),
                quote.terms(),
                quote.lineItems(),
                quote.version(),
                quote.createdAt(),
                quote.updatedAt()
            );
        }

        QuoteDto saved = quoteRepository.save(userId, quoteToSave);
        return ResponseEntity.ok(saved);
    }

    @GetMapping
    public ResponseEntity<?> listMyQuotes(
        @RequestParam(value = "page", defaultValue = "0") int page,
        @RequestParam(value = "size", defaultValue = "10") int size,
        @RequestParam(value = "client", required = false) String client,
        @RequestParam(value = "status", required = false) String status,
        @RequestParam(value = "date", required = false) String date
    ) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        var pageResult = quoteRepository.searchQuotes(userId, page, size, client, status, date);
        return ResponseEntity.ok(pageResult);
    }

    @GetMapping("/{quoteId}")
    public ResponseEntity<?> getQuote(@PathVariable("quoteId") String quoteId) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (quoteRepository.existsForOtherUser(userId, quoteId)) {
            log.warn("Cross-user quote access attempt: requester={}, quoteId={}", userId, quoteId);
            throw new OwnershipViolationException("Access denied: cannot view quote of another contractor");
        }

        return quoteRepository.findById(userId, quoteId)
            .map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).build());
    }

    @GetMapping("/{quoteId}/items")
    public ResponseEntity<?> getQuoteItems(@PathVariable("quoteId") String quoteId) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (quoteRepository.existsForOtherUser(userId, quoteId)) {
            log.warn("Cross-user quote line items access attempt: requester={}, quoteId={}", userId, quoteId);
            throw new OwnershipViolationException("Access denied: cannot view line items of another contractor");
        }

        return quoteRepository.findById(userId, quoteId)
            .map(q -> ResponseEntity.ok(q.lineItems()))
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).build());
    }

    @PatchMapping(value = "/{quoteId}", consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> patchQuote(@PathVariable("quoteId") String quoteId, @RequestBody QuoteDto patch) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (quoteRepository.existsForOtherUser(userId, quoteId)) {
            log.warn("Cross-user quote patch attempt: requester={}, quoteId={}", userId, quoteId);
            throw new OwnershipViolationException("Access denied: cannot update quote of another contractor");
        }

        return quoteRepository.findById(userId, quoteId)
            .map(existing -> {
                QuoteDto updated = quoteRepository.save(userId, patch);
                return ResponseEntity.ok(updated);
            })
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND).build());
    }

    @DeleteMapping("/{quoteId}")
    public ResponseEntity<?> deleteQuote(@PathVariable("quoteId") String quoteId) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (quoteRepository.existsForOtherUser(userId, quoteId)) {
            log.warn("Cross-user quote delete attempt: requester={}, quoteId={}", userId, quoteId);
            throw new OwnershipViolationException("Access denied: cannot delete quote of another contractor");
        }

        boolean deleted = quoteRepository.delete(userId, quoteId);
        if (deleted) {
            // Day 21 policy: deleting a quote removes its correction feedback.
            // Feedback rows are keyed by SHA-256(quoteId), never the raw ID.
            try {
                String quoteHash = FeedbackHash.sha256Hex(quoteId);
                int removed = feedbackRepository.deleteByQuoteHash(userId, quoteHash);
                log.info("Quote deleted with feedback cleanup: quoteId={} feedbackRemoved={}", quoteId, removed);
            } catch (Exception e) {
                log.warn("Feedback cleanup failed for deleted quote {}", quoteId);
            }
            return ResponseEntity.noContent().build();
        }
        return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
}

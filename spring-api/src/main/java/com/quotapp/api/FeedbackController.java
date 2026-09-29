package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.dto.FeedbackDto;
import com.quotapp.api.repository.FeedbackRepository;
import com.quotapp.security.UserContext;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Day 21 — Correction-feedback boundary.
 * Accepts only the minimal privacy-scoped fields; rejects audio/transcript
 * payloads by design (no such fields exist on {@link FeedbackDto}).
 */
@RestController
@RequestMapping("/api/feedback")
public class FeedbackController {

    private static final Logger log = LoggerFactory.getLogger(FeedbackController.class);

    private final FeedbackRepository feedbackRepository;

    @Autowired
    public FeedbackController(FeedbackRepository feedbackRepository) {
        this.feedbackRepository = feedbackRepository;
    }

    @PostMapping(consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> submitFeedback(@Valid @RequestBody FeedbackDto feedback) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        // Defensive: never accept raw audio / transcript even if a client sends extras.
        // Unknown JSON properties are ignored by Jackson; the DTO has no such fields.
        FeedbackDto saved = feedbackRepository.save(userId, feedback);
        return ResponseEntity.ok(saved);
    }

    @GetMapping(produces = "application/json")
    public ResponseEntity<?> listMyFeedback() {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        List<FeedbackDto> items = feedbackRepository.findByUser(userId);
        return ResponseEntity.ok(Map.of("content", items, "totalElements", items.size()));
    }

    @DeleteMapping("/by-quote/{quoteHash}")
    public ResponseEntity<?> deleteByQuoteHash(@PathVariable("quoteHash") String quoteHash) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        if (quoteHash == null || !quoteHash.matches("^[0-9a-fA-F]{64}$")) {
            return ResponseEntity.badRequest()
                .body(new ErrorResponse("VALIDATION_ERROR", "quoteHash must be SHA-256 hex"));
        }
        int removed = feedbackRepository.deleteByQuoteHash(userId, quoteHash.toLowerCase());
        return ResponseEntity.ok(Map.of("removed", removed, "quoteIdHash", quoteHash.toLowerCase()));
    }
}

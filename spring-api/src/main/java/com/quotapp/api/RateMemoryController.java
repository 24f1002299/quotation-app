package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.dto.RateMemoryItemDto;
import com.quotapp.api.exception.OwnershipViolationException;
import com.quotapp.api.repository.RateMemoryRepository;
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
 * Controller exposing contractor rate memory operations with strict user scoping.
 */
@RestController
@RequestMapping("/api/rates")
public class RateMemoryController {

    private static final Logger log = LoggerFactory.getLogger(RateMemoryController.class);

    private final RateMemoryRepository rateMemoryRepository;

    @Autowired
    public RateMemoryController(RateMemoryRepository rateMemoryRepository) {
        this.rateMemoryRepository = rateMemoryRepository;
    }

    @GetMapping("/me")
    public ResponseEntity<?> getMyRates() {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        return getRates(userId);
    }

    @PutMapping(value = "/me", consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> updateMyRates(@Valid @RequestBody List<RateMemoryItemDto> items) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        return updateRates(userId, items);
    }

    @GetMapping("/{userId}")
    public ResponseEntity<?> getRates(@PathVariable("userId") String userId) {
        String currentUserId = UserContext.getUserId();
        if (currentUserId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (!currentUserId.equals(userId)) {
            log.warn("Cross-user rate memory access attempt: requester={}, target={}", currentUserId, userId);
            throw new OwnershipViolationException("Access denied: cannot view rate memory of another contractor");
        }

        List<RateMemoryItemDto> rates = rateMemoryRepository.findByUserId(userId);
        return ResponseEntity.ok(rates);
    }

    @PutMapping(value = "/{userId}", consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> updateRates(
        @PathVariable("userId") String userId,
        @Valid @RequestBody List<RateMemoryItemDto> items
    ) {
        String currentUserId = UserContext.getUserId();
        if (currentUserId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (!currentUserId.equals(userId)) {
            log.warn("Cross-user rate memory update attempt: requester={}, target={}", currentUserId, userId);
            throw new OwnershipViolationException("Access denied: cannot update rate memory of another contractor");
        }

        List<RateMemoryItemDto> updated = rateMemoryRepository.saveAll(userId, items);
        return ResponseEntity.ok(updated);
    }
}

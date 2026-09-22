package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.dto.ProfileDto;
import com.quotapp.api.exception.OwnershipViolationException;
import com.quotapp.api.repository.ProfileRepository;
import com.quotapp.security.UserContext;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Controller exposing contractor profile operations with strict user scoping.
 */
@RestController
@RequestMapping("/api/profiles")
public class ProfileController {

    private static final Logger log = LoggerFactory.getLogger(ProfileController.class);

    private final ProfileRepository profileRepository;

    @Autowired
    public ProfileController(ProfileRepository profileRepository) {
        this.profileRepository = profileRepository;
    }

    @GetMapping("/me")
    public ResponseEntity<?> getMyProfile() {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        return getProfile(userId);
    }

    @PutMapping(value = "/me", consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> updateMyProfile(@Valid @RequestBody ProfileDto profile) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }
        return updateProfile(userId, profile);
    }

    @GetMapping("/{userId}")
    public ResponseEntity<?> getProfile(@PathVariable("userId") String userId) {
        String currentUserId = UserContext.getUserId();
        if (currentUserId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (!currentUserId.equals(userId)) {
            log.warn("Cross-user profile access attempt: requester={}, target={}", currentUserId, userId);
            throw new OwnershipViolationException("Access denied: cannot view profile of another contractor");
        }

        return profileRepository.findByUserId(userId)
            .map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(null));
    }

    @PutMapping(value = "/{userId}", consumes = "application/json", produces = "application/json")
    public ResponseEntity<?> updateProfile(@PathVariable("userId") String userId, @Valid @RequestBody ProfileDto profile) {
        String currentUserId = UserContext.getUserId();
        if (currentUserId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (!currentUserId.equals(userId)) {
            log.warn("Cross-user profile update attempt: requester={}, target={}", currentUserId, userId);
            throw new OwnershipViolationException("Access denied: cannot update profile of another contractor");
        }

        ProfileDto updated = profileRepository.save(userId, profile);
        return ResponseEntity.ok(updated);
    }
}

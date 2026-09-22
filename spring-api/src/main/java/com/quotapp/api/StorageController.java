package com.quotapp.api;

import com.quotapp.api.dto.ErrorResponse;
import com.quotapp.api.exception.OwnershipViolationException;
import com.quotapp.security.UserContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/**
 * Controller exposing signed URL generation for user-scoped storage objects.
 * Enforces strict user prefix scoping: User A cannot get a signed URL for User B's files.
 */
@RestController
@RequestMapping("/api/storage")
public class StorageController {

    private static final Logger log = LoggerFactory.getLogger(StorageController.class);

    private final String supabaseUrl;

    public StorageController(@Value("${supabase.project-url:http://localhost:54321}") String supabaseUrl) {
        this.supabaseUrl = supabaseUrl;
    }

    @GetMapping("/signed-url")
    public ResponseEntity<?> getSignedUrl(@RequestParam("path") String path) {
        String userId = UserContext.getUserId();
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("UNAUTHORIZED", "Authentication required"));
        }

        if (path == null || path.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse("INVALID_PATH", "Storage path cannot be empty"));
        }

        String normalizedPath = path.trim().replace("\\", "/");
        if (normalizedPath.startsWith("/")) {
            normalizedPath = normalizedPath.substring(1);
        }

        // Storage paths must start with {userId}/
        String expectedPrefix = userId + "/";
        if (!normalizedPath.startsWith(expectedPrefix)) {
            log.warn("Storage cross-user access violation attempt: user={}, requestedPath={}", userId, path);
            throw new OwnershipViolationException("Access denied: cannot access storage files of another contractor");
        }

        // Generate signed URL (simulated / ephemeral URL anchored to private user-files bucket)
        String encodedPath = URLEncoder.encode(normalizedPath, StandardCharsets.UTF_8);
        String signedUrl = supabaseUrl + "/storage/v1/object/sign/user-files/" + encodedPath + "?expiresIn=3600";

        return ResponseEntity.ok(Map.of(
            "path", normalizedPath,
            "signedUrl", signedUrl,
            "expiresIn", 3600
        ));
    }
}

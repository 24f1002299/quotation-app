package com.quotapp.api.repository;

import com.quotapp.api.dto.ProfileDto;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Repository for contractor profiles.
 * Thread-safe and scoped by user ID.
 */
@Repository
public class ProfileRepository {

    private final ConcurrentHashMap<String, ProfileDto> profiles = new ConcurrentHashMap<>();

    public Optional<ProfileDto> findByUserId(String userId) {
        if (userId == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(profiles.get(userId));
    }

    public ProfileDto save(String userId, ProfileDto profile) {
        if (userId == null || profile == null) {
            throw new IllegalArgumentException("userId and profile cannot be null");
        }
        int nextVersion = profile.version() != null ? profile.version() : 1;
        ProfileDto existing = profiles.get(userId);
        if (existing != null && existing.version() != null) {
            nextVersion = existing.version() + 1;
        }

        ProfileDto updated = new ProfileDto(
            profile.id() != null ? profile.id() : userId,
            userId,
            profile.name() != null ? profile.name() : (existing != null ? existing.name() : ""),
            profile.businessName() != null ? profile.businessName() : (existing != null ? existing.businessName() : ""),
            profile.trade() != null ? profile.trade() : (existing != null ? existing.trade() : "tiling"),
            profile.city() != null ? profile.city() : (existing != null ? existing.city() : ""),
            profile.phone() != null ? profile.phone() : (existing != null ? existing.phone() : ""),
            profile.gstin() != null ? profile.gstin() : (existing != null ? existing.gstin() : null),
            profile.logoPath() != null ? profile.logoPath() : (existing != null ? existing.logoPath() : null),
            profile.quoteTerms() != null ? profile.quoteTerms() : (existing != null ? existing.quoteTerms() : ""),
            profile.schemaVersion() != null ? profile.schemaVersion() : 1,
            nextVersion,
            Instant.now()
        );
        profiles.put(userId, updated);
        return updated;
    }
}

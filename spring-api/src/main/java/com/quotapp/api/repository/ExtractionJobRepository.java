package com.quotapp.api.repository;

import com.quotapp.api.dto.ExtractionJob;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Repository for minimal extraction job records.
 *
 * <p>Enforces strict user scoping: jobs belonging to User A cannot be accessed by User B.
 */
@Repository
public class ExtractionJobRepository {

    private final ConcurrentHashMap<String, ExtractionJob> jobs = new ConcurrentHashMap<>();

    public void save(ExtractionJob job) {
        if (job != null && job.jobId() != null) {
            jobs.put(job.jobId(), job);
        }
    }

    public Optional<ExtractionJob> findById(String jobId) {
        if (jobId == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(jobs.get(jobId));
    }

    public Optional<ExtractionJob> findByIdAndUserId(String jobId, String userId) {
        if (jobId == null || userId == null) {
            return Optional.empty();
        }
        ExtractionJob job = jobs.get(jobId);
        if (job != null && userId.equals(job.userId())) {
            return Optional.of(job);
        }
        return Optional.empty();
    }
}

package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import java.time.Instant;

/**
 * Privacy-minimal correction feedback for ANY business domain.
 *
 * <p>Only business type, service item / model result, final value, changed
 * field, and hashed quote ID. No audio, transcript, or customer PII fields
 * exist on purpose — adding one must go through privacy review.
 *
 * <p>Canonical names are {@code businessType} and {@code serviceItemId}
 * (free-text business slug such as {@code pest_control} or
 * {@code catering}). Legacy wire names {@code trade} and
 * {@code catalogItemId} are still accepted on input.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record FeedbackDto(
    String id,
    @NotBlank(message = "quoteIdHash is required")
    @Pattern(regexp = "^[0-9a-f]{64}$", message = "quoteIdHash must be SHA-256 hex (64 lowercase hex chars)")
    String quoteIdHash,
    @NotBlank(message = "businessType is required")
    @JsonAlias({"trade", "business_type"})
    String businessType,
    @JsonAlias({"catalogItemId", "catalog_item_id", "service_item_id"})
    String serviceItemId,
    String modelResult,
    String finalValue,
    @NotBlank(message = "changedField is required")
    @Pattern(regexp = "^(description|quantity|unit|rate)$", message = "changedField must be description, quantity, unit, or rate")
    String changedField,
    Instant createdAt
) {}

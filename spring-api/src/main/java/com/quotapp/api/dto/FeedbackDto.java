package com.quotapp.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

import java.time.Instant;

/**
 * Day 21 — Privacy-minimal correction feedback.
 * Only trade, catalog item / model result, final value, changed field,
 * and hashed quote ID. No audio, transcript, or customer PII fields exist
 * on purpose — adding one must go through privacy review.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record FeedbackDto(
    String id,
    @NotBlank(message = "quoteIdHash is required")
    @Pattern(regexp = "^[0-9a-f]{64}$", message = "quoteIdHash must be SHA-256 hex (64 lowercase hex chars)")
    String quoteIdHash,
    @NotBlank(message = "trade is required")
    @Pattern(regexp = "^(tiling|painting)$", message = "trade must be tiling or painting")
    String trade,
    String catalogItemId,
    String modelResult,
    String finalValue,
    @NotBlank(message = "changedField is required")
    @Pattern(regexp = "^(description|quantity|unit|rate)$", message = "changedField must be description, quantity, unit, or rate")
    String changedField,
    Instant createdAt
) {}

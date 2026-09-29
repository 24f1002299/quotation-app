package com.quotapp.api;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * Day 21 — SHA-256 hex helper. Must match the Flutter
 * {@code hashQuoteId()} so quote deletion cleans up the same rows.
 */
public final class FeedbackHash {

    private FeedbackHash() {}

    public static String sha256Hex(String quoteId) {
        if (quoteId == null) throw new IllegalArgumentException("quoteId cannot be null");
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(quoteId.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(64);
            for (byte b : hash) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}

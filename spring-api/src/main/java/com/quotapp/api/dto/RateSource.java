package com.quotapp.api.dto;

/**
 * Provenance of unit rates attached to extracted line items.
 *
 * <p>Invariant: The model cannot invent arbitrary unvetted rates. Rates may come only from
 * contractor rate memory ({@code RATE_MEMORY}), a flagged catalog benchmark suggestion ({@code SUGGESTED}),
 * or be left explicitly unassigned ({@code UNKNOWN}).
 */
public enum RateSource {
    RATE_MEMORY,
    SUGGESTED,
    UNKNOWN
}

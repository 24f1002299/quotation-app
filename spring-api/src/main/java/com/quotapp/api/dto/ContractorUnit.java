package com.quotapp.api.dto;

import java.util.Arrays;
import java.util.Locale;
import java.util.Set;

/**
 * Recognized trade units supported in contractor speech, catalogs, and quotes.
 *
 * <p>Enforces strict domain validation against unrecognized units (e.g. unknown metric or arbitrary units).
 */
public enum ContractorUnit {
    SQ_FT("sq ft", Set.of("sq ft", "sqft", "square feet", "sq.ft", "चौरस फूट", "स्क्वेअर फूट", "फूट")),
    RFT("rft", Set.of("rft", "running feet", "running foot", "रनिंग फूट", "रनिंग")),
    BRASS("brass", Set.of("brass", "ब्रास")),
    NOS("nos", Set.of("nos", "no", "nug", "piece", "pieces", "नग")),
    LUMPSUM("lumpsum", Set.of("lumpsum", "lump sum", "ls", "लम्पसम")),
    BAGS("bags", Set.of("bags", "bag", "बोरी", "बॅग")),
    POINT("point", Set.of("point", "points", "पॉइंट"));

    private final String canonical;
    private final Set<String> aliases;

    ContractorUnit(String canonical, Set<String> aliases) {
        this.canonical = canonical;
        this.aliases = aliases;
    }

    public String getCanonical() {
        return canonical;
    }

    /**
     * Checks if a raw unit string is recognized as a valid contractor unit.
     */
    public static boolean isRecognized(String rawUnit) {
        return fromString(rawUnit) != null;
    }

    /**
     * Parses and normalizes a raw unit string to its canonical representation.
     */
    public static ContractorUnit fromString(String rawUnit) {
        if (rawUnit == null || rawUnit.isBlank()) {
            return null;
        }
        String normalized = rawUnit.trim().toLowerCase(Locale.ROOT);
        for (ContractorUnit unit : values()) {
            if (unit.canonical.equalsIgnoreCase(normalized) || unit.aliases.contains(normalized)) {
                return unit;
            }
        }
        return null;
    }

    /**
     * Normalizes a raw unit string to canonical name, or returns the original if not found.
     */
    public static String normalize(String rawUnit) {
        ContractorUnit unit = fromString(rawUnit);
        return unit != null ? unit.canonical : rawUnit;
    }
}

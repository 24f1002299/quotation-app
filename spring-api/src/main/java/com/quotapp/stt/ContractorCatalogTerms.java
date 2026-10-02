package com.quotapp.stt;

import java.util.List;

/**
 * Domain vocabulary for contractor speech across ALL business types.
 *
 * <p>The list seeds tiling/painting terms first (largest user base) then one
 * or two anchor terms per other domain, so the STT prompt stays useful for
 * pest control, catering, electrical, plumbing, cleaning and beyond without
 * exceeding the Groq 896-byte prompt limit.
 *
 * <p>Never treat STT transcription results as trusted line-item data; all speech results
 * remain candidates requiring contractor review before saving a quote.
 */
public final class ContractorCatalogTerms {

    private ContractorCatalogTerms() {}

    /**
     * Common trade terms, units, and Hindi/Marathi phrases for tiling and painting.
     */
    public static final List<String> TERMS = List.of(
        // Tiling catalogue items & synonyms
        "tile labour", "टाइल मजदूरी", "टाइल लेबर", "floor tiles", "wall tiles",
        "tiles lagana", "टाइल लगाना", "फर्श टाइल", "दीवार टाइल",
        "skirting", "स्कर्टिंग", "border tile", "skirt",
        "waterproofing", "वॉटरप्रूफिंग", "पाणी रोखणे", "waterproof", "leakage proofing",

        // Painting catalogue items & synonyms
        "wall putty", "वॉल पुट्टी", "putty work", "पट्टी", "patti kaam", "white cement putty",
        "primer", "प्राइमर", "prime coat", "priming", "first coat",
        "painting", "पेंटिंग", "रंगाई", "rangai", "wall painting", "emulsion", "distemper",

        // Other domains: one anchor term each so any business transcribes cleanly
        "cockroach", "pest control", "pipe fitting", "switch board", "wiring",
        "wooden door", "false ceiling", "sofa repair", "catering", "khana",

        // Units and measurements in contractor speech
        "sq ft", "square feet", "स्क्वेअर फूट", "चौरस फूट", "फूट",
        "rft", "running feet", "रनिंग फूट", "रनिंग",
        "brass", "ब्रास",
        "nug", "नग", "piece", "pieces",

        // Commercial and money terms
        "rate", "दर", "भाव", "रुपये", "rupees", "advance", "कोटेशन", "quotation"
    );

    /**
     * Formats catalogue terms as prompt hint for Whisper based on language mode.
     *
     * <p>Phase 1 (Hinglish-first): every variant is written in <b>Roman
     * script</b>. Whisper's {@code prompt} strongly biases the script of the
     * output, and forcing Devanagari here is what made Hindi-picked recordings
     * come back in Devanagari even though the app's catalog, parser, and
     * review flow work best with Hinglish. The per-mode variants below differ
     * only in vocabulary bias (Hindi vs Marathi nouns), never in script.
     * The Whisper {@code language} parameter is intentionally <b>not</b> sent
     * (see {@code SttService.callOpenAiWhisper}) so code-switched speech is
     * auto-detected instead of being locked to one language.
     */
    public static String asPromptString(String languageHint) {
        String lang = languageHint != null ? languageHint.trim().toLowerCase() : "auto";
        if ("hi".equals(lang)) {
            return "Contractor quotation in Hinglish, Roman script only: kitchen deewar tiles 120 sq ft, wall putty 1200 sq ft, dar 35 rupaye prati sq ft, skirting 45 rft, cockroach treatment 2 room, switch board 4 point.";
        } else if ("mr".equals(lang)) {
            return "Contractor quotation in Hinglish, Roman script only: kitchen bhint tiles 120 chauras ft, wall putty, dar 40 rupaye, skirting, pipe fitting 1 point, j1 khana 100 plate.";
        } else {
            // Auto / Hinglish mode — forces Whisper to transcribe speech in Hinglish (Roman script)
            return "Contractor quotation in Hinglish (Roman script): kitchen wall tiles 120 sq ft, wall putty 1200 sq ft, rate 35 rupees per sq ft, skirting 45 rft, pest treatment 2 rooms, wiring 4 points.";
        }
    }

    public static String asPromptString() {
        return asPromptString("auto");
    }
}

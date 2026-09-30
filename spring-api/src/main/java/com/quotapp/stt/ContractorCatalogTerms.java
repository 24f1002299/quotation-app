package com.quotapp.stt;

import java.util.List;

/**
 * Domain-specific vocabulary from the Day 4 & Day 6 tiling and painting catalogues.
 *
 * <p>Used for:
 * <ul>
 *   <li>Key-term biasing in Grok STT (up to 100 domain terms).</li>
 *   <li>Prompt hint in OpenAI Whisper-1 to bias token probabilities towards contractor terms.</li>
 * </ul>
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
            return "Contractor quotation in Hinglish, Roman script only: kitchen deewar tiles 120 sq ft, bathroom farsh tiles 80 sq ft, wall putty 1200 sq ft, dar 35 rupaye prati sq ft, skirting 45 rft, waterproofing, primer, painting emulsion.";
        } else if ("mr".equals(lang)) {
            return "Contractor quotation in Hinglish, Roman script only: kitchen bhint tiles 120 chauras ft, bathroom farshi 80 chauras ft, wall putty, dar 40 rupaye, skirting, waterproofing, terrace plaster, primer.";
        } else {
            // Auto / Hinglish mode — forces Whisper to transcribe speech in Hinglish (Roman script)
            return "Contractor quotation in Hinglish (Roman script): kitchen wall tiles 120 sq ft, wall putty 1200 sq ft, floor tiles 80 sq ft, rate 35 rupees per sq ft, skirting 45 rft, waterproofing 60 sq ft, primer, painting emulsion.";
        }
    }

    public static String asPromptString() {
        return asPromptString("auto");
    }
}

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
     * In Auto / Hinglish mode, instructs Whisper to transcribe speech into Roman script (Hinglish).
     */
    public static String asPromptString(String languageHint) {
        String lang = languageHint != null ? languageHint.trim().toLowerCase() : "auto";
        if ("hi".equals(lang)) {
            return "ठेकेदार कोटेशन: किचन की दीवार की टाइलें 120 वर्ग फुट, वॉल पुट्टी 1200 वर्ग फुट, दर 35 रुपये प्रति फुट, वॉटरप्रूफिंग, प्राइमर, पेंटिंग";
        } else if ("mr".equals(lang)) {
            return "कॉन्ट्रॅक्टर कोटेशन: किचन भिंतीवरील टाइल्स 120 चौरस फूट, वॉल पुट्टी, बाथरूम फरशी 80 चौरस फूट, दर 40 रुपये, स्कर्टिंग, वॉटरप्रूफिंग";
        } else {
            // Auto / Hinglish mode — forces Whisper to transcribe speech in Hinglish (Roman script)
            return "Contractor quotation in Hinglish (Roman script): kitchen wall tiles 120 sq ft, wall putty 1200 sq ft, floor tiles 80 sq ft, rate 35 rupees per sq ft, skirting 45 rft, waterproofing 60 sq ft, primer, painting emulsion.";
        }
    }

    public static String asPromptString() {
        return asPromptString("auto");
    }
}

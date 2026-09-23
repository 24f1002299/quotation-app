package com.quotapp.stt;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Guards the Groq Whisper {@code prompt} limit (896): the prompt must stay
 * under it in UTF-8 bytes, otherwise every transcription fails with 400
 * invalid_prompt and the UI looks stuck on one transcript.
 */
class ContractorCatalogTermsTest {

    @Test
    @DisplayName("Default prompt fits Groq 896-byte limit with margin")
    void defaultPromptFitsGroqLimit() {
        String prompt = ContractorCatalogTerms.asPromptString();
        assertThat(prompt.getBytes(StandardCharsets.UTF_8).length)
                .isLessThanOrEqualTo(896);
        assertThat(prompt).isNotEmpty();
    }
}

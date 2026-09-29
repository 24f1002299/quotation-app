package com.quotapp.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quotapp.api.dto.FeedbackDto;
import com.quotapp.api.repository.FeedbackRepository;
import com.quotapp.api.repository.QuoteRepository;
import com.quotapp.api.dto.QuoteDto;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
    "supabase.jwks-url=http://localhost:0/test-jwks",
    "spring.datasource.url=jdbc:h2:mem:testdb;MODE=PostgreSQL",
    "spring.datasource.driver-class-name=org.h2.Driver",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "database.app-role.password=test"
})
class FeedbackControllerTest {

    private static final String TEST_USER = "00000000-0000-0000-0000-000000000099";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private FeedbackRepository feedbackRepository;

    @Autowired
    private QuoteRepository quoteRepository;

    private FeedbackDto validFeedback(String quoteHash) {
        return new FeedbackDto(
            UUID.randomUUID().toString(),
            quoteHash,
            "tiling",
            "tiling_floor_tile",
            "Floor tiles",
            "Kitchen wall tiles",
            "description",
            Instant.now()
        );
    }

    @Test
    @DisplayName("Day 21: editing an item creates one correctly scoped feedback record")
    void testSubmitFeedbackCreatesScopedRecord() throws Exception {
        String quoteId = UUID.randomUUID().toString();
        String quoteHash = FeedbackHash.sha256Hex(quoteId);

        MvcResult result = mockMvc.perform(
            post("/api/feedback")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(validFeedback(quoteHash)))
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.quoteIdHash").value(quoteHash))
            .andExpect(jsonPath("$.changedField").value("description"))
            .andReturn();

        FeedbackDto saved = objectMapper.readValue(result.getResponse().getContentAsString(), FeedbackDto.class);
        assertThat(saved.quoteIdHash()).isEqualTo(quoteHash);

        // Scoped: repository lookup by hash finds it.
        assertThat(feedbackRepository.findByQuoteHash(TEST_USER, quoteHash)).hasSizeGreaterThanOrEqualTo(1);
        assertThat(feedbackRepository.findByQuoteHash(TEST_USER, FeedbackHash.sha256Hex(UUID.randomUUID().toString()))).isEmpty();
    }

    @Test
    @DisplayName("Day 21: feedback rejects invalid trade/field and non-hash quote id")
    void testFeedbackValidation() throws Exception {
        String quoteHash = FeedbackHash.sha256Hex(UUID.randomUUID().toString());

        // Bad trade.
        FeedbackDto badTrade = new FeedbackDto(null, quoteHash, "plumbing", null, "a", "b", "description", null);
        mockMvc.perform(post("/api/feedback").with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(badTrade)))
            .andExpect(status().isBadRequest());

        // Bad changedField.
        FeedbackDto badField = new FeedbackDto(null, quoteHash, "tiling", null, "a", "b", "audio", null);
        mockMvc.perform(post("/api/feedback").with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(badField)))
            .andExpect(status().isBadRequest());

        // Raw quote id instead of hash.
        FeedbackDto rawId = new FeedbackDto(null, "quote-uuid-1", "tiling", null, "a", "b", "rate", null);
        mockMvc.perform(post("/api/feedback").with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(rawId)))
            .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Day 21: deleting a quote removes its feedback (documented policy)")
    void testDeleteQuoteRemovesFeedback() throws Exception {
        String quoteId = UUID.randomUUID().toString();
        String idemp = "fb_del_" + UUID.randomUUID();
        String quoteHash = FeedbackHash.sha256Hex(quoteId);

        // Seed a quote owned by TEST_USER.
        quoteRepository.save(TEST_USER, new QuoteDto(
            quoteId, idemp, null, "ready", "tiling", "Feedback Client",
            null, null, null, 1000L, 0L, 1000L, "2026-09-25", 15,
            null, null, null, List.of(), List.of(), 1, null, null
        ));

        // Seed feedback for that quote.
        feedbackRepository.save(TEST_USER, validFeedback(quoteHash));
        assertThat(feedbackRepository.findByQuoteHash(TEST_USER, quoteHash)).isNotEmpty();

        // Delete via the API — must cascade to feedback.
        mockMvc.perform(delete("/api/quotes/" + quoteId).with(user(TEST_USER)))
            .andExpect(status().isNoContent());

        assertThat(feedbackRepository.findByQuoteHash(TEST_USER, quoteHash)).isEmpty();
    }
}

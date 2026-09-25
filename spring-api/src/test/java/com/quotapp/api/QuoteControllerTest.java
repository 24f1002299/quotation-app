package com.quotapp.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quotapp.api.dto.QuoteDto;
import com.quotapp.api.dto.QuoteLineItemDto;
import com.quotapp.api.repository.QuoteRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
class QuoteControllerTest {

    private static final String TEST_USER = "00000000-0000-0000-0000-000000000001";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private QuoteRepository quoteRepository;

    @Test
    @DisplayName("Day 15: First successful sync assigns a human-readable display number while anchoring to idempotencyKey")
    void testFirstSyncAssignsDisplayNumber() throws Exception {
        String idempotencyKey = UUID.randomUUID().toString();
        QuoteDto request = new QuoteDto(
            idempotencyKey,
            idempotencyKey,
            null,
            "ready",
            "tiling",
            "Sharma Ji",
            null,
            null,
            null,
            1200000L,
            0L,
            1200000L,
            "2026-09-25",
            15,
            null,
            null,
            null,
            List.of(),
            List.of(new QuoteLineItemDto("Floor tiles", 120, "sq ft", 8500L, 1020000L, 1.0, null, null, false, false, true)),
            1,
            null,
            null
        );

        MvcResult result = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request))
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.idempotencyKey").value(idempotencyKey))
            .andExpect(jsonPath("$.clientName").value("Sharma Ji"))
            .andReturn();

        QuoteDto response = objectMapper.readValue(result.getResponse().getContentAsString(), QuoteDto.class);
        assertThat(response.displayNumber()).isNotBlank();
        assertThat(response.displayNumber()).startsWith("Q-");
    }

    @Test
    @DisplayName("Day 15: Repeat sync with identical idempotencyKey returns cached quote with same display number")
    void testRepeatSyncIdempotency() throws Exception {
        String idempotencyKey = UUID.randomUUID().toString();
        QuoteDto request1 = new QuoteDto(
            idempotencyKey,
            idempotencyKey,
            null,
            "ready",
            "tiling",
            "Patil Residence",
            "9876543210",
            "Site 42, Pune",
            18,
            100000L,
            18000L,
            118000L,
            "2026-09-25",
            15,
            50,
            "50% advance",
            "Special notes",
            List.of("Term 1", "Term 2"),
            List.of(),
            1,
            null,
            null
        );

        MvcResult result1 = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request1))
        )
            .andExpect(status().isOk())
            .andReturn();

        QuoteDto response1 = objectMapper.readValue(result1.getResponse().getContentAsString(), QuoteDto.class);

        // Second request with different client name but SAME idempotencyKey
        QuoteDto request2 = new QuoteDto(
            idempotencyKey,
            idempotencyKey,
            null,
            "ready",
            "tiling",
            "Completely Different Name",
            null,
            null,
            null,
            500000L,
            0L,
            500000L,
            "2026-09-25",
            15,
            null,
            null,
            null,
            List.of(),
            List.of(),
            1,
            null,
            null
        );

        MvcResult result2 = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request2))
        )
            .andExpect(status().isOk())
            .andReturn();

        QuoteDto response2 = objectMapper.readValue(result2.getResponse().getContentAsString(), QuoteDto.class);

        // Idempotency: response2 must equal response1
        assertThat(response2.displayNumber()).isEqualTo(response1.displayNumber());
        assertThat(response2.clientName()).isEqualTo("Patil Residence");
    }

    @Test
    @DisplayName("Day 15: Complete quotation can be made with only client name plus line items")
    void testCompleteQuotationWithMinimalFields() throws Exception {
        String idempotencyKey = UUID.randomUUID().toString();
        QuoteDto minimalQuote = new QuoteDto(
            idempotencyKey,
            idempotencyKey,
            null,
            "ready",
            "tiling",
            "Minimal Client",
            null, // no phone
            null, // no site
            null, // no GST
            50000L,
            0L,
            50000L,
            null, // no date
            null, // no validity
            null, // no advance
            null, // no advance text
            null, // no notes
            null, // no custom terms
            List.of(new QuoteLineItemDto("Labour", 10, "sq ft", 5000L, 50000L, null, null, null, false, false, true)),
            1,
            null,
            null
        );

        mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(minimalQuote))
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.clientName").value("Minimal Client"))
            .andExpect(jsonPath("$.displayNumber").isNotEmpty())
            .andExpect(jsonPath("$.idempotencyKey").value(idempotencyKey));
    }
}

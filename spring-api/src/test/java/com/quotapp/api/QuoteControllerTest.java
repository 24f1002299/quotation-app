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

    @Test
    @DisplayName("Day 16: Repeat requests and simulated network drop after server acceptance do not create an extra quote")
    void testSimulatedNetworkDropIdempotency() throws Exception {
        String quoteId = UUID.randomUUID().toString();
        String idempotencyKey = "op_" + quoteId;

        QuoteDto quote = new QuoteDto(
            quoteId,
            idempotencyKey,
            null,
            "ready",
            "tiling",
            "Ramesh Contractor",
            null, null, null,
            75000L, 0L, 75000L,
            "2026-09-25",
            15, null, null, null,
            List.of(), List.of(),
            1, null, null
        );

        // First attempt (server accepts and generates display number)
        MvcResult firstResult = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(quote))
        )
            .andExpect(status().isOk())
            .andReturn();

        QuoteDto firstResponse = objectMapper.readValue(firstResult.getResponse().getContentAsString(), QuoteDto.class);

        // Simulated network drop on client after server accepted: client resends exact same request
        MvcResult secondResult = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(quote))
        )
            .andExpect(status().isOk())
            .andReturn();

        QuoteDto secondResponse = objectMapper.readValue(secondResult.getResponse().getContentAsString(), QuoteDto.class);

        // Must be the exact same quote, identical display number, no extra quote created
        assertThat(secondResponse.id()).isEqualTo(firstResponse.id());
        assertThat(secondResponse.displayNumber()).isEqualTo(firstResponse.displayNumber());
        assertThat(secondResponse.version()).isEqualTo(firstResponse.version());
    }

    @Test
    @DisplayName("Day 16: Same-quote, two-device edit exposes a recoverable version conflict (HTTP 409)")
    void testTwoDeviceEditExposesRecoverableConflict() throws Exception {
        String quoteId = UUID.randomUUID().toString();
        String baseIdemp = "base_" + quoteId;

        // Device 1 creates initial quote at version 1
        QuoteDto initialQuote = new QuoteDto(
            quoteId,
            baseIdemp,
            null,
            "draft",
            "tiling",
            "Conflict Test Client",
            null, null, null,
            50000L, 0L, 50000L,
            "2026-09-25",
            15, null, null, null,
            List.of(), List.of(),
            1, null, null
        );

        MvcResult createResult = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(initialQuote))
        )
            .andExpect(status().isOk())
            .andReturn();

        QuoteDto created = objectMapper.readValue(createResult.getResponse().getContentAsString(), QuoteDto.class);
        assertThat(created.version()).isEqualTo(1);

        // Device 1 updates the quote: sends version 1, gets updated to version 2
        QuoteDto device1Update = new QuoteDto(
            quoteId,
            "dev1_edit_" + UUID.randomUUID(),
            created.displayNumber(),
            "ready",
            "tiling",
            "Client Modified by Device 1",
            null, null, null,
            60000L, 0L, 60000L,
            "2026-09-25",
            15, null, null, null,
            List.of(), List.of(),
            1, null, null
        );

        MvcResult dev1Result = mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(device1Update))
        )
            .andExpect(status().isOk())
            .andReturn();

        QuoteDto dev1Updated = objectMapper.readValue(dev1Result.getResponse().getContentAsString(), QuoteDto.class);
        assertThat(dev1Updated.version()).isEqualTo(2);
        assertThat(dev1Updated.clientName()).isEqualTo("Client Modified by Device 1");

        // Device 2 was offline and also edited the quote starting from version 1
        QuoteDto device2ConcurrentEdit = new QuoteDto(
            quoteId,
            "dev2_edit_" + UUID.randomUUID(),
            created.displayNumber(),
            "ready",
            "tiling",
            "Client Modified by Device 2 (Conflicting)",
            null, null, null,
            70000L, 0L, 70000L,
            "2026-09-25",
            15, null, null, null,
            List.of(), List.of(),
            1, // device 2 still thinks it's editing version 1
            null, null
        );

        // Server detects that version 1 < current server version 2 -> returns 409 Conflict
        mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(device2ConcurrentEdit))
        )
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("VERSION_CONFLICT"))
            .andExpect(jsonPath("$.serverQuote.version").value(2))
            .andExpect(jsonPath("$.serverQuote.clientName").value("Client Modified by Device 1"));

        // Recoverable: Device 2 chooses to keep its edit by rebasing onto version 2 and syncing
        QuoteDto device2ResolvedEdit = new QuoteDto(
            quoteId,
            "dev2_resolved_" + UUID.randomUUID(),
            created.displayNumber(),
            "ready",
            "tiling",
            "Client Modified by Device 2 (Resolved)",
            null, null, null,
            70000L, 0L, 70000L,
            "2026-09-25",
            15, null, null, null,
            List.of(), List.of(),
            2, // rebased onto server version 2
            null, null
        );

        mockMvc.perform(
            post("/api/quotes/sync")
                .with(user(TEST_USER))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(device2ResolvedEdit))
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.version").value(3))
            .andExpect(jsonPath("$.clientName").value("Client Modified by Device 2 (Resolved)"));
    }

    @Test
    @DisplayName("Day 16: Paginated quote history list with server-side search by client, status, and date")
    void testPaginatedQuoteHistoryAndSearch() throws Exception {
        String uniqueSuffix = UUID.randomUUID().toString().substring(0, 8);
        String clientA = "Aarav_" + uniqueSuffix;
        String clientB = "Ananya_" + uniqueSuffix;
        String clientC = "Deepak_" + uniqueSuffix;

        // Seed 3 quotes for test user
        quoteRepository.save(TEST_USER, new QuoteDto(
            UUID.randomUUID().toString(), "idemp_a_" + uniqueSuffix, null, "draft", "tiling",
            clientA, null, null, null, 1000L, 0L, 1000L, "2026-09-10", 15, null, null, null,
            List.of(), List.of(), 1, null, null
        ));

        quoteRepository.save(TEST_USER, new QuoteDto(
            UUID.randomUUID().toString(), "idemp_b_" + uniqueSuffix, null, "ready", "painting",
            clientB, null, null, null, 2000L, 0L, 2000L, "2026-09-20", 15, null, null, null,
            List.of(), List.of(), 1, null, null
        ));

        quoteRepository.save(TEST_USER, new QuoteDto(
            UUID.randomUUID().toString(), "idemp_c_" + uniqueSuffix, null, "shared", "tiling",
            clientC, null, null, null, 3000L, 0L, 3000L, "2026-09-25", 15, null, null, null,
            List.of(), List.of(), 1, null, null
        ));

        // 1. Search by client substring (Aarav)
        mockMvc.perform(
            get("/api/quotes")
                .with(user(TEST_USER))
                .param("client", "Aarav")
                .param("page", "0")
                .param("size", "10")
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.content[0].clientName").value(clientA))
            .andExpect(jsonPath("$.totalElements").value(1));

        // 2. Search by status (ready)
        mockMvc.perform(
            get("/api/quotes")
                .with(user(TEST_USER))
                .param("status", "ready")
                .param("client", uniqueSuffix) // scope to this test's records
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.content[0].clientName").value(clientB))
            .andExpect(jsonPath("$.totalElements").value(1));

        // 3. Search by date (2026-09-25)
        mockMvc.perform(
            get("/api/quotes")
                .with(user(TEST_USER))
                .param("date", "2026-09-25")
                .param("client", uniqueSuffix)
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.content[0].clientName").value(clientC))
            .andExpect(jsonPath("$.totalElements").value(1));

        // 4. Pagination (page size 1)
        mockMvc.perform(
            get("/api/quotes")
                .with(user(TEST_USER))
                .param("client", uniqueSuffix)
                .param("page", "0")
                .param("size", "1")
        )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.content.length()").value(1))
            .andExpect(jsonPath("$.totalElements").value(3))
            .andExpect(jsonPath("$.totalPages").value(3))
            .andExpect(jsonPath("$.isLast").value(false));
    }
}

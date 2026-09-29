# Day 21 — Correction Feedback Privacy Policy

## What we collect (and only this)

When a contractor edits a line that came from voice extraction, the app stores
one minimal record **per changed field**:

| Field | Example | Why |
|---|---|---|
| `trade` | `tiling` | Learn which trade's words fail |
| `catalog_item_id` | `tiling_floor_tile` | Which catalog entry the model picked |
| `model_result` | `Floor tiles` | What extraction produced |
| `final_value` | `Kitchen wall tiles` | What the contractor kept |
| `changed_field` | `description` / `quantity` / `unit` / `rate` | Which value was wrong |
| `quote_id_hash` | SHA-256 hex of the quote UUID | Scope feedback without storing the raw quote ID |

## What we never collect by default

- **No raw audio.** The microphone stream goes only to the transcription
  endpoint and the temp file is deleted after transcription/cancellation.
- **No diagnostic transcript copy** unless the user opts in (see below).
- **No customer PII** (name, phone, address) in feedback rows.

## Consent setting (off by default)

Profile → Privacy / गोपनीयता → **"Help improve with diagnostic notes"**.

- Default: **OFF**.
- When OFF: only the functional quote transcript (needed to build the quote,
  stored with the quote) exists. No extra diagnostic copy is kept.
- When ON: the app may keep an extra typed-transcript copy for troubleshooting
  extraction quality. Audio is still never kept.
- A second toggle, **"Back up PDFs to cloud"**, is also OFF by default.

## Deletion / anonymisation policy (verified)

- Feedback rows are **append-only** from the client (Supabase RLS: no
  UPDATE/DELETE policies on `edit_feedback`).
- **Deleting a quote removes its feedback:**
  - Flutter: `QuoteRepository.deleteQuote()` → `FeedbackRepository.deleteForQuoteId()`
    deletes local rows (matched by `SHA-256(quoteId)`) and enqueues a
    `feedback/delete` outbox marker.
  - Spring: `QuoteController.deleteQuote()` → `FeedbackRepository.deleteByQuoteHash()`.
  - Supabase: `delete_feedback_for_quote(hash)` (migration 006) deletes the
    caller's rows server-side.
- **Anonymisation alternative:** `anonymize_feedback_for_quote(hash)` redacts
  `model_result`/`final_value` to `[redacted]` and nulls `catalog_item_id`,
  keeping only `trade` + `changed_field` counts. Use for exports/retention
  where hard-delete is unavailable.

## Verify (Day 21 acceptance)

1. Edit an extracted item → exactly one feedback record per changed field,
   scoped to `SHA-256(quoteId)`, containing no audio/transcript/PII.
2. Delete the quote → its feedback rows are gone (or anonymised) on device,
   API, and database per the policy above.
3. Fresh install → both privacy toggles read OFF.

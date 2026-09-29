# Data Retention — Contractor Quote App (pilot)

| Data | Where | Kept until | How deleted |
|---|---|---|---|
| Business profile | Phone + `profiles` table | Until account/data deletion | App: Profile → Privacy → Delete; Server: per-user row delete on account deletion |
| Saved rates | Phone + `rate_memory` | Until changed/deleted | Rate Card edit; wiped with account deletion |
| Quotes + line items | Phone + `quotes` / `quote_line_items` | Until user deletes the quote | History delete → local + API `DELETE /api/quotes/{id}` (RLS-scoped) |
| Quote transcripts (functional copy with the quote) | Phone + `quotes.original_transcript` | Lives and dies with its quote | Same as quote delete |
| Correction feedback | Phone + `edit_feedback` | Dies with its quote | `FeedbackRepository.deleteForQuoteId` → API cascade in `QuoteController.deleteQuote` → `delete_feedback_for_quote()`; or `anonymize_feedback_for_quote()` for exports |
| Diagnostic transcript copy | Phone only, only when opted in | Until opt-out or data delete | Toggle OFF stops future copies; Delete clears past ones |
| Raw audio | Temp file on phone + in-memory on server | **Deleted immediately** after transcription/cancellation/failure | `TranscriptionService.deleteTemporaryAudio` (all paths); server never writes to disk/DB |
| PDFs (local) | App-scoped `quotations/` dir | Until quote deleted or Delete-my-data | File delete with quote; Delete-my-data wipes dir |
| PDFs (cloud backup, opt-in only) | `user-files/<userId>/quote-pdfs/` | Until quote deleted or account deletion | Quote delete removes object; account deletion removes prefix |
| Logos | `user-files/<userId>/…` | Until replaced or account deletion | Overwrite on change; prefix delete on account deletion |
| Server logs | Log aggregator | 30 days, lengths/counts only (no transcripts/audio/keys) | Rolling expiry |
| Backups | Supabase plan PITR window | Per plan (see runbook) | Expire with backup window; account deletion honored on restore-check |

Rules:
- No silent retention extension. Any change needs a new dated entry here.
- Restores from backup must re-apply deletion requests issued before the
  backup timestamp (see `docs/backup-restore-runbook.md`).
- The service-role key is never used by the app; RLS always applies.

# Privacy Notice — Contractor Quote App (pilot)

Short version for contractors. The in-app screen (Profile → Privacy notice)
shows the same content in Hindi-first plain language.

## 1. What we collect

- **Business profile & rates:** name, business name, phone, city, trade,
  GSTIN (optional), logo (optional), saved item rates.
- **Quotations:** client name, optional phone/site, line items, totals,
  terms, and the typed transcript needed to build the quote.
- **Correction notes (opt-out-able by deletion):** trade, catalog item,
  model result, final value, changed field, hashed quote ID. No audio,
  no customer details. Deleted automatically when its quote is deleted
  (see `docs/feedback-privacy.md`).
- **Diagnostic transcript copy:** ONLY if you turn on
  Profile → Privacy → “Help improve with diagnostic notes” (OFF by default).

## 2. What we never collect by default

- Voice recordings. The mic is used only while you tap record; the temp
  file is deleted from the phone after transcription/cancellation, and the
  server streams audio in memory without writing it to disk or database.
- Provider API keys never reach the phone. The app calls only our
  authenticated server, which holds the keys as environment variables.

## 3. How your data is protected

- Every contractor sees only their own data (Supabase Row Level Security
  on all tables + user-scoped Storage paths + server ownership checks).
- All API calls except health/docs require your login token (Supabase JWT,
  verified via JWKS). No shared passwords.
- Logs contain sizes/counts, never transcript content, audio, or keys.
- Browser cross-origin access is denied by default (restrictive CORS).

## 4. How long we keep data (retention)

See `docs/data-retention.md`. In short: quotes and profiles until you
delete them; correction notes die with their quote; temp audio dies
immediately; backups follow the Supabase plan's point-in-time window.

## 5. Your rights: export & delete

- **In the app:** Profile → Privacy → “Export my data” (JSON copy, no audio)
  or “Delete my data” (wipes this phone after confirmation).
- **Cloud copy:** while signed in, deleting each quote in History deletes
  its server record, line items, feedback, and (if backed up) its PDF.
  For full account deletion, contact support (address in the app Help link)
  with your registered phone number; we delete database rows, Storage
  objects, and retained diagnostics within 30 days and confirm in writing.

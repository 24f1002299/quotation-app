# Day 22 — Security & Privacy Checklist (manual, pilot gate)

Resolve every HIGH before pilot. Evidence commands/tests in brackets.

## Access control — HIGH
- [x] RLS enabled on all 5 tables; policies scoped to `auth.uid()`
      [`002_rls_policies.sql`; `supabase/tests/rls_isolation_test.sql`
      — executed 2026-09-29 on quotapp-dev: 19/19 pass]
- [x] Storage bucket private; object paths forced to `{userId}/…`
      [`002_rls_policies.sql`; `supabase/tests/storage_isolation_test.sql`
      — executed 2026-09-29 on quotapp-dev: 6/6 pass (also caught and
      fixed a missing `user-files` bucket row)]
- [x] Spring ownership checks on every user-owned endpoint; cross-user → 403/404
      [`CrossUserIsolationTest`, `SecurityHardeningTest`]
- [x] Unauthenticated requests → 401 on all `/api/**` except health/docs
      [`JwtValidationTest`, `SecurityHardeningTest`]
- [x] Dev JWT bypass requires dev profile AND explicit flag (default OFF)
      [`SupabaseJwtFilter`, `application.yml`, `SecurityHardeningTest`]
- [x] Least-privilege `app_role` (DML only, no DDL, no `auth.*`)
      [`003_app_role.sql`]

## Input & transport — HIGH
- [x] Audio: allow-listed MIME types, 10 MB cap, 60 s app auto-stop / 120 s
      server cap, per-user rate limit (10/min), multipart caps in `application.yml`
      [`TranscriptionController`, `TranscriptionService`, `UserRateLimiter`]
- [x] Extraction: transcript/input limits, strict JSON, idempotency keys,
      version conflicts → 409 [`ExtractionContractTest`, `QuoteControllerTest`]
- [x] CORS deny-by-default; allow-list via `CORS_ALLOWED_ORIGINS` only
      [`SecurityConfig`]
- [x] TLS: `usesCleartextTraffic=false`; cleartext only for emulator
      loopback via `network_security_config.xml`; prod uses HTTPS base URL

## Secrets — HIGH
- [x] `spring-api/.env` + `contractor_quote_poc/.env` are git-ignored;
      `git status` clean; `.env.example` documents vars without values
- [x] OpenAI/Groq keys live only in server env (`OPENAI_API_KEY`,
      `XAI_API_KEY`); never in the app, logs, or error responses
      [`api_config.dart` comment, `SttService`, `LlmExtractionClient`]
- [x] Key rotation: replace value in server env → restart API → verify
      `/api/health` + one test transcription; old key revoked at provider
      console. No app release needed.

## Logging — HIGH
- [x] No transcript content, audio bytes, filenames, or keys in logs —
      lengths/counts/extensions only
      [`SttService`, `LlmExtractionClient`, `TranscriptionController`]
- [x] Structured errors carry `requestId`, never stack traces or secrets
      [`GlobalExceptionHandler`, `ErrorResponse`]

## Audio privacy — HIGH
- [x] Mic only while recording (explicit start/stop, permission gate,
      no background use); purpose disclosed on the capture screen
      [`voice_screen.dart`, `AndroidManifest.xml` (foreground-only `RECORD_AUDIO`)]
- [x] Temp audio deleted on success/cancel/failure/dispose; server streams
      in memory, never persists audio [`TranscriptionService`,
      `TranscriptionController` javadoc]
- [x] Diagnostic audio consent: no collection path exists; the gate reads
      always-false [`DiagnosticConsent.isAudioOptedIn`]
- [x] Diagnostic transcript copy: visible toggle, OFF by default
      [`DiagnosticConsent`, Profile → Privacy]

## Data lifecycle — HIGH
- [x] Privacy notice in-app (`/privacy`) + `docs/privacy-notice.md`
- [x] Export (JSON, no audio) + Delete-my-data (confirm) in Profile → Privacy
      [`DataDeletionService`, `day22_security_privacy_test.dart`]
- [x] Retention table: transcripts, customer data, PDFs, feedback
      [`docs/data-retention.md`]
- [x] Quote delete removes/anonymizes feedback (device + API + DB function)
      [`FeedbackRepository`, `QuoteController`, `006_feedback_lifecycle.sql`]
- [x] Deletion covers Storage + DB; backup restore drill documented
      [`docs/backup-restore-runbook.md`]

## Dependencies & perms — MEDIUM
- [x] `flutter pub outdated` reviewed; no permission beyond
      `RECORD_AUDIO` + `INTERNET` in the manifest
- [x] Spring pool bounded (max 10), stateless instances, health endpoint
      without details [`application.yml`]

## Residual / manual before pilot
- [ ] Fill backup-runbook blanks (project ref, plan/PITR window, contacts)
      and run the restore drill on staging.
- [ ] Supabase Dashboard → Auth → JWT JWKS URL matches server env;
      confirm no service-role key in any client config.
- [ ] Play Console data-safety form matches `docs/privacy-notice.md`.

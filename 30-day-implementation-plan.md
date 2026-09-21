# 30-Day Implementation Plan — Voice-First Quotation App

## Outcome on day 30

An Android MVP for **tiling and painting contractors in Maharashtra**. A contractor can set up their business, select a trade, dictate a job in Hindi, Marathi, or Hinglish, correct the extracted line items, generate a branded PDF quotation, and share it through the Android share sheet (including WhatsApp). Quotes and rate memory survive app restarts and unreliable connectivity.

This is deliberately not an invoicing, payments, multi-user, dealer, referral, or WhatsApp-bot build. Those are valid later products, but they weaken the first release. The MVP’s job is to prove one loop: **speak → review → PDF → share** in under a minute.

## Architecture guardrails

Use Flutter for the Android app, Supabase Authentication (phone OTP), Postgres, and Storage. Keep a small, stateless Spring Boot API as the sole business-data and AI boundary: it verifies Supabase JWTs, authorizes every user-owned operation, performs schema validation, and keeps provider keys off the phone. Supabase is the managed data platform, not a replacement for domain authorization in the API. Record audio in the app and send it only to an authenticated Spring Boot transcription endpoint; that endpoint calls OpenAI’s Audio Transcriptions API with `whisper-1`. The OpenAI API key never reaches the device. Keep the client behind a `SpeechTranscriber` interface so the provider can be benchmarked or changed later without changing the quote flow. Generate PDFs on-device and use Android’s native share sheet.

```text
Flutter Android app
  ├─ encrypted local draft store + durable sync outbox + bundled trade catalog
  ├─ Android recorder ──> Spring Boot transcription endpoint ──> OpenAI Whisper (`whisper-1`) ──> transcript
  ├─ Spring Boot API ──> authenticated domain API + extraction jobs
  ├─ Supabase Auth ──> phone OTP and JWTs
  ├─ Supabase Postgres ──> profiles, rates, quotes, feedback, job records
  ├─ Supabase Storage ──> optional logo and opt-in PDF backup
  └─ PDF renderer + Android share sheet
```

Keep three layers in the app only: screens/widgets, feature services/controllers, and repositories. Put calculation and validation in pure Dart functions. The LLM may suggest items; it must never calculate totals or silently invent a rate. The edit screen is the source of truth. Use database migrations, explicit indexes, pagination, and UUID/ULID primary IDs from the first release. Every write sent from the app must include an idempotency key; every mutable server record must have a version for conflict detection.

Do **not** add a generic microservice layer, event bus, clean-architecture ceremony, vector database, fine-tuning pipeline, or real-time collaboration. The local outbox is the minimum required sync mechanism with Supabase; it is not a general-purpose sync engine. Start extraction synchronously only while it meets the latency target; use a small durable job table and worker path for slow or overloaded provider calls. Add other components only when a stated verification step exposes a real need.

## Definition of done for the MVP

- A new user can create and share a tiling or painting quotation without a developer’s help.
- All monetary calculations, taxes, and rounding are deterministic and covered by tests.
- Missing/uncertain speech or AI values are visibly flagged for confirmation; nothing is sent automatically.
- A saved quote can be reopened, edited, regenerated, and shared.
- The app remains usable for review and PDF generation when temporarily offline; online-only actions explain their state and can retry.
- Test devices cover at least one Hindi and one Marathi voice note captured in a realistically noisy environment.

## 30-day delivery schedule

### Day 1 — Freeze the MVP

**Goal:** Establish the smallest product boundary and success measures.

**Tasks:** Turn the brief into one user journey and a one-page scope statement. Write acceptance criteria for setup, capture, review, PDF, sharing, saved quotes, and failure states. Record non-goals: invoices, payments, multi-site, helper logins, subscriptions, dealer tooling, referral flow, and WhatsApp bot. Define the target: first share in under 60 seconds and 90% of quoted line items editable without typing a sentence.

**Verify:** A contractor, designer, and developer can each explain the same six-screen flow and agree what is excluded.

**Commit:** `docs: define tiling and painting quotation mvp`

### Day 2 — Set product conventions and wireframes

**Goal:** Make the core flow understandable to low-English, voice-first users.

**Tasks:** Create low-fidelity wireframes for onboarding, home, record/transcript, review, PDF preview, and quote history. Choose Hindi-first labels with simple English fallback and large touch targets. Specify destructive-action confirmation, loading, empty, no-network, and extraction-failed states.

**Verify:** Five sample flows can be completed from the wireframes without an explanatory paragraph; all primary actions are reachable with one thumb.

**Commit:** `docs: add mvp flow and low fidelity wireframes`

### Day 3 — Bootstrap Android project and quality gates

**Goal:** Start from a reproducible, testable Flutter app.

**Tasks:** Create the Flutter project and Spring Boot service with Android package name, dev/staging/prod configuration, lint rules, formatter, unit-test setup, database migration tooling, and CI that runs app analysis/tests plus API tests. Add a simple environment configuration mechanism that never checks in API secrets. Set up Crashlytics or equivalent crash reporting and structured API logs with request IDs.

**Verify:** A clean checkout builds an installable debug APK and API test artifact; CI passes on deliberately small app/API smoke tests and applies migrations to an ephemeral test database.

**Commit:** `chore: bootstrap flutter android app and ci`

### Day 4 — Model the minimal domain

**Goal:** Define stable data shapes before building screens.

**Tasks:** Create Dart models and JSON serialization for `BusinessProfile`, `TradeCatalogItem`, `RateMemory`, `Quote`, `QuoteLineItem`, `QuoteTerms`, `ExtractionResult`, and `EditFeedback`. Add quote states: draft, needsReview, ready, and shared. Include schema version and IDs, but no workflow engine.

**Verify:** Model serialization round-trips and older/missing optional fields load safely in unit tests.

**Commit:** `feat: add quotation domain models`

### Day 5 — Build deterministic money and quantity logic

**Goal:** Ensure code—not AI—owns all arithmetic.

**Tasks:** Implement pure functions for quantity × rate, line discounts, subtotal, GST (off by default), rounded grand total, and Indian currency formatting. Define decimal handling in minor units/decimal-safe arithmetic; never use floating-point totals. Add validation for positive quantities, rate, unit, and sensible maximums.

**Verify:** Unit tests cover fractional quantities, zero GST, 5/12/18% GST, rounding, invalid input, and known quotation examples.

**Commit:** `feat: add tested quotation calculation engine`

### Day 6 — Create the first two trade catalogs

**Goal:** Narrow extraction to real contractor vocabulary.

**Tasks:** Build versioned JSON catalogs for tiling and painting with 50–100 items each: canonical name, Hindi/Marathi/Hinglish synonyms, default unit, allowable units, optional rate band, and display label. Have at least two contractors or a trade expert review wording and units. Bundle catalogs in the app; do not make a catalog admin panel.

**Verify:** A scripted set of 30 spoken-style phrases maps to intended catalog items or explicitly reports “unknown item.”

**Commit:** `feat: add tiling and painting trade catalogs`

### Day 7 — Set up Supabase safely

**Goal:** Give each contractor private, durable data.

**Tasks:** Configure separate Supabase dev/staging/production projects, development test sign-in, production phone authentication, Postgres, Storage, and JWT settings. Create versioned SQL migrations for all user-owned tables and storage objects. Enable Row Level Security on every exposed table; write policies scoped to `auth.uid()` and restrictive Storage policies. Configure the Spring Boot service with a least-privilege database role, verify Supabase JWTs using the published JWKS, and enforce ownership in service methods. Do not put the Supabase service-role key in the app. Add local Supabase testing or an isolated test project for integration tests.

**Verify:** Integration tests prove User A cannot read or write User B’s profile, quotes, files, feedback, or storage objects through either direct Supabase access or the Spring API. Migrations apply cleanly to an empty database.

**Commit:** `chore: configure firebase and user scoped security rules`

### Day 8 — Validate OpenAI Whisper for contractor speech

**Goal:** Verify that OpenAI Whisper is suitable for contractor speech, especially numbers and code-switching.

**Tasks:** Collect consented 20–30 second Hindi, Marathi, and Hinglish samples in quiet and site-noisy conditions. Build a throwaway authenticated Spring Boot endpoint that forwards an audio file to OpenAI Audio Transcriptions using `whisper-1`; do not call OpenAI directly from the app. Test the supported audio format produced by Android (prefer compact M4A/AAC) and score number accuracy, line-item accuracy, latency, failure rate, and rupees per quote. Include catalogue terms as a transcription prompt where supported, but never treat the result as trusted line-item data.

**Verify:** A short benchmark document records the `whisper-1` result and fallback behaviour based on measured samples—not marketing claims. If Whisper misses the agreed accuracy/latency bar, retain transcript editing as mandatory and schedule a provider comparison before broad release; do not silently switch providers. Raw audio is kept locally only with consent and only for the minimum diagnostic period.

**Commit:** `research: validate openai whisper transcription for contractor samples`

### Day 9 — Implement recording and transcription UX

**Goal:** Turn spoken input into a reviewable transcript.

**Tasks:** Add microphone permission handling, record/start/stop/cancel controls, elapsed time, language choice/auto-setting, and retry. Capture a short M4A/AAC recording, enforce a conservative maximum duration/file size before upload, and upload over HTTPS only to the authenticated Spring Boot endpoint. The endpoint validates media type, size, duration, and user rate limit; it streams the file to OpenAI `whisper-1` without placing it in application logs or permanent storage. Save the returned transcript and uncertainty metadata to a draft. Delete the temporary recording after successful transcription or cancellation unless the user has separately consented to diagnostic retention. Clearly communicate that transcription needs internet; never lose the typed draft on failure.

**Verify:** On a physical Android device, users can record, cancel, retry, and edit a Hindi, Marathi, and Hinglish Whisper transcript; denial of microphone permission produces a helpful recovery path. Verify that no OpenAI key, raw audio, or full transcript is emitted to mobile/API logs and that oversized or unsupported uploads are rejected safely.

**Commit:** `feat: add voice capture and transcript drafts`

### Day 10 — Build the extraction API contract

**Goal:** Define a safe boundary between the app and the model.

**Tasks:** Specify OpenAPI request/response JSON for both (1) an authenticated audio-transcription endpoint and (2) the extraction endpoint for transcript, selected trade, relevant catalog entries, rate memory, language, and schema version. The transcription endpoint accepts only documented audio formats, bounded duration/size, and a language hint; it returns transcript text plus safe uncertainty metadata. The extraction response must contain only line items, confidence, source spans, and explicit unknowns; rates may come only from rate memory or a clearly flagged suggestion. Add Spring Boot request validation, transcript/input limits, JWT verification, user ownership checks, idempotency keys, structured errors, request IDs, and a version field for mutable resources.

**Verify:** Contract tests reject malformed JSON, unauthorized requests, unsupported/oversized audio, unrecognized units, oversized transcripts, and arithmetic fields from the model. Tests prove that the transcription endpoint does not return provider secrets or persist raw audio by default.

**Commit:** `feat: define secure extraction api contract`

### Day 11 — Implement constrained LLM extraction

**Goal:** Produce reliable candidates for review, not autonomous quotations.

**Tasks:** Implement the Spring Boot extraction endpoint. Send only the chosen trade’s catalog and the contractor’s saved rates. Require strict JSON/schema output, map model item IDs back to catalog data, and preserve unknown requests rather than guessing. Add a strict provider timeout, bounded retry for transient failure, per-user/device rate limits, redacted structured logs, and a circuit breaker; never log raw audio or more transcript content than needed. Persist a minimal extraction job record. If the provider cannot respond inside the user-facing latency budget, return a job ID and poll for completion rather than holding app/API connections open.

**Verify:** A 40-case fixture suite confirms valid structured output, unknown handling, no model-provided totals, and useful error responses when the model fails.

**Commit:** `feat: add catalog constrained line item extraction`

### Day 12 — Create profile and rate memory

**Goal:** Reduce future quotes to quantities wherever possible.

**Tasks:** Build a short onboarding form for name, business name, phone, address/city, trade, optional GSTIN, logo, and quote defaults. Provide a simple editable rate list seeded by the catalog, without bulk spreadsheets. Persist it through a repository with local cache, the sync outbox, and the Spring API/Supabase database. Store logos using user-scoped Supabase Storage paths and signed URLs only.

**Verify:** A user can set a tiling rate, reinstall/sign back in, and see that rate applied to an extracted item.

**Commit:** `feat: add contractor profile and saved rates`

### Day 13 — Assemble capture-to-extraction flow

**Goal:** Move from speech to structured draft in one dependable flow.

**Tasks:** Connect transcript drafts to the extraction API, show incremental status, and create a `needsReview` quote from returned items. Include an explicit “type it instead” path. Handle timeout, server unavailable, and malformed response without discarding transcript or draft data.

**Verify:** Ten representative voice samples enter review with a visible result or recoverable error, and users can continue manually in every failure case.

**Commit:** `feat: create review drafts from voice extraction`

### Day 14 — Build the line-item review screen

**Goal:** Make correcting a quote fast and trustworthy.

**Tasks:** Implement large line-item cards showing item, quantity, unit, rate, amount, and uncertainty. Add, edit, duplicate, reorder, and delete rows; use a compact form or bottom sheet rather than gesture-only deletion. Recalculate totals immediately with the Day 5 engine. Require resolution or acknowledgement of unknown/low-confidence items before PDF generation.

**Verify:** A contractor can repair all intentionally wrong values in a five-line quote in under two minutes, with totals changing correctly after each edit.

**Commit:** `feat: add editable quotation review screen`

### Day 15 — Add customer and quote terms

**Goal:** Make the output commercially usable without bloating data entry.

**Tasks:** Add client name, phone (optional), site/address, quote number, date, validity, advance percentage/text, notes, GST toggle/rate, and a small set of editable default terms. Generate an immutable UUID/ULID quote ID locally for offline safety. On first successful sync, have the backend assign an optional human-readable display number; do not promise gap-free sequential numbering. Display both only where useful, and keep the immutable ID as the idempotency anchor.

**Verify:** A complete quotation can be made with only client name plus line items, while optional commercial fields render correctly when supplied.

**Commit:** `feat: add customer details and quotation terms`

### Day 16 — Persist drafts and history

**Goal:** Ensure site connectivity never destroys work.

**Tasks:** Add repositories for profile, rates, catalog versions, and quotes. Use an encrypted local draft store plus a durable outbox containing operation ID, idempotency key, retry count, and payload version. Sync when connectivity returns with bounded exponential backoff; send record versions and show a simple conflict choice only when the same quote changed on another device. The server must accept each idempotency key once. Provide a paginated quote history list with server-side search by client, status, and date; no analytics dashboard. Add indexes for user-scoped history and search queries before the pilot.

**Verify:** Start a quote offline, force-close the app, reopen it, finish editing, then reconnect and confirm it syncs exactly once without duplicates. Repeat requests and a simulated network drop after server acceptance do not create an extra quote. A same-quote, two-device edit exposes a recoverable version conflict.

**Commit:** `feat: save offline drafts and quotation history`

### Day 17 — Produce a professional PDF locally

**Goal:** Turn the reviewed quote into a shareable artifact.

**Tasks:** Implement one clean, A4 PDF template with business details/logo, client/site, line-item table, totals, terms, signature space, quote ID, and optional free-tier footer. Bundle a font that renders Devanagari correctly. Keep styling configurable only through logo and business name for now.

**Verify:** Generate PDFs for one-line, multi-page, Hindi, Marathi, long-business-name, and no-logo quotations; inspect them on Android and a desktop PDF reader.

**Commit:** `feat: generate branded quotation pdfs on device`

### Day 18 — Share and regenerate PDFs

**Goal:** Complete the contractor’s primary action.

**Tasks:** Save PDFs using app-scoped storage, share via Android’s native share sheet, and expose “Share PDF” as the primary completion action. Allow regeneration after editing, clearly replacing only the app-owned local file. Back up PDFs to Storage only if the user enables it or the product requires cross-device recovery.

**Verify:** Share a quote to WhatsApp and one non-WhatsApp destination on a real device; edit a value, regenerate, and confirm the new total is in the shared file.

**Commit:** `feat: share and regenerate quotation pdfs`

### Day 19 — Finish the minimal onboarding and home

**Goal:** Make the first quote easy to discover and resume.

**Tasks:** Finish phone sign-in, profile/trade/rates setup, a home screen with “New voice quote,” recent drafts, and recent sent quotes. Add an in-context one-time tutorial, not a multi-page product tour. Make Hindi the default when locale supports it, with language controls always visible.

**Verify:** A fresh tester who reads limited English can reach recording, create a draft, and return to it after restart.

**Commit:** `feat: complete onboarding and quotation home`

### Day 20 — Make uncertainty and errors safe

**Goal:** Prevent bad quotes from looking confident.

**Tasks:** Add explicit flags for unknown item, uncertain quantity, missing rate, unusual rate, missing customer, failed sync, and stale catalog. Make PDF generation block only on essential unresolved values; provide manual resolution. Add consistent retry affordances and an error-report ID for support.

**Verify:** Simulate each error condition and confirm that the app explains what happened, preserves work, and offers a concrete next action.

**Commit:** `feat: add quote validation and recoverable error states`

### Day 21 — Capture correction feedback privately

**Goal:** Learn which words and values the system gets wrong.

**Tasks:** When users alter an extracted line, record minimal feedback: trade, catalog item/model result, final item, changed field type, and hashed quote ID. Do not collect raw audio by default. Add a user-visible consent setting for diagnostic transcript storage, off by default.

**Verify:** Editing an item creates one correctly scoped feedback record; deleting a quote removes or anonymizes associated feedback according to the documented policy.

**Commit:** `feat: record privacy conscious extraction corrections`

### Day 22 — Security and privacy hardening

**Goal:** Protect contractors’ commercial data before pilot use.

**Tasks:** Review Supabase RLS/Storage policies, Spring API authorization, JWT validation, CORS, input validation, secrets, logging, database roles, and dependency permissions. Review the OpenAI audio path: API key storage/rotation, TLS, accepted media types, maximum upload size/duration, rate limits, temporary-file cleanup, redaction, and explicit diagnostic-audio consent. Add a concise privacy notice and deletion/export request path. Define data retention for transcripts, customer data, PDFs, and feedback; redact personal data from logs and delete/anonymize feedback when its quote is deleted. Ensure the microphone is used only while recording and no audio is uploaded without a disclosed purpose.

**Verify:** Run Supabase RLS/Storage integration tests, unauthenticated and cross-user API tests, dependency audit, and a manual privacy checklist; resolve every high-severity finding. Verify that a database backup restore has been documented, deletion requests cover Storage and database records, and the transcription path cleans up temporary audio and does not expose an OpenAI key.

**Commit:** `chore: harden data access and privacy controls`

### Day 23 — Build automated test coverage around risk

**Goal:** Protect the quotation path, not test every pixel.

**Tasks:** Expand unit tests for calculations, parsing/validation, repositories, idempotency, and conflict handling. Add widget tests for editing and validation. Add a small end-to-end happy path using fake transcription/extraction, OpenAPI contract tests, Supabase RLS integration tests, and migration tests. Add golden tests only for the PDF’s essential totals/header if practical. Add a small load-test scenario for authenticated history reads, quote saves, and extraction-job submission.

**Verify:** The test suite catches intentionally introduced wrong total, unresolved unknown item, malformed extraction response, duplicate write, cross-user request, and stale-version conflict. The load test provides a baseline for API/database saturation and does not exhaust the connection pool.

**Commit:** `test: cover critical quotation and extraction paths`

### Day 24 — Test on real Android constraints

**Goal:** Find failures unavailable in simulators.

**Tasks:** Test on at least one lower-memory Android device and one current device, with poor network, denied permissions, screen rotation, interrupted call, app backgrounding during transcription, and low storage. Measure first-launch time, transcription latency, extraction latency, PDF render time, and APK size.

**Verify:** Publish a device test matrix with every blocker fixed or explicitly deferred with a user-safe fallback.

**Commit:** `test: validate app behavior on physical android devices`

### Day 25 — Run internal dogfood

**Goal:** Validate the full loop with people outside the build team.

**Tasks:** Distribute an internal APK to 5–10 testers. Give them five realistic scripts and ask them to make/send quotes unaided. Collect task completion time, extraction corrections, crashes, confusing labels, and screenshots of output PDFs.

**Verify:** At least 80% of testers can share a valid PDF unaided; triage all failed tasks into fix-now or explicitly deferred issues.

**Commit:** `docs: record internal dogfood findings and triage`

### Day 26 — Pilot with contractors and refine catalogs

**Goal:** Test the product with the intended users, not proxies.

**Tasks:** Conduct an assisted pilot with 5–10 tiling/painting contractors, using consented real or recreated jobs. Observe rather than lead. Compare transcript/extraction output to their corrections, add confirmed synonyms/units to the two bundled catalogs, and simplify the top three points of confusion.

**Verify:** Record first-quote completion, time to share, lines corrected, and whether each participant says they would use it next week; confirm catalog updates with a regression fixture.

**Commit:** `feat: refine catalogs from contractor pilot feedback`

### Day 27 — Prepare release operations

**Goal:** Make the MVP supportable after installation.

**Tasks:** Configure release signing, separate production environment, versioning, Crashlytics alerts, API budget/rate alerts, uptime checks, and a support contact. Deploy the stateless Spring API with at least two instances behind a health-checked load balancer and a bounded database connection pool. Configure Supabase backups/point-in-time recovery appropriate to the chosen plan, alerting for API p95 latency, error rate, job backlog, database connections, failed syncs, and provider spend. Write a short runbook for failed extraction, unavailable speech, PDF/share issues, data deletion, migration rollback, backup restore, and incident rollback.

**Verify:** A release candidate installs from the signed bundle; a simulated extraction outage triggers a visible alert and graceful in-app recovery; a failed instance is removed from service; and the team completes a tabletop backup-restore and migration-rollback exercise.

**Commit:** `chore: add release monitoring and support runbook`

### Day 28 — Complete Play Store readiness

**Goal:** Meet distribution requirements without claiming unsupported capabilities.

**Tasks:** Prepare store listing in simple English/Hindi, screenshots from real flows, icon, feature graphic, support URL/email, data-safety form, privacy-policy URL, content rating, and tester instructions. Review all permissions and remove any not required for the MVP.

**Verify:** Upload the signed AAB to an internal or closed testing track with no Play Console blocking errors.

**Commit:** `docs: prepare play store release assets and disclosures`

### Day 29 — Release-candidate regression and performance pass

**Goal:** Ship a stable narrow release.

**Tasks:** Run the full regression checklist: account, onboarding, rates, Hindi/Marathi/Hinglish capture, edit operations, calculation cases, offline draft recovery, duplicate-write recovery, conflict handling, paginated history, PDF variants, share sheet, and sign-out. Run the pre-production load profile representing the expected pilot peak and document the extrapolation assumptions for 10,000 registered users. Fix only release blockers, crashes, data loss, security issues, or defects that cause an incorrect quotation; log enhancements separately.

**Verify:** Two clean devices complete the full flow in staging and production configuration, with no P0/P1 defects open. Under the agreed peak profile, normal authenticated API reads/writes meet the p95 target, no duplicate quote is created during retry, and the database connection pool remains below its alert threshold.

**Commit:** `fix: resolve release candidate quotation blockers`

### Day 30 — Closed pilot release and learning loop

**Goal:** Put the MVP in contractors’ hands and decide the next build cycle from evidence.

**Tasks:** Release to a small closed cohort, assist each participant through the first quotation, and monitor crashes, API error rate, first-quote-within-24-hours, quotes per user per week, completion time, corrections per quote, and 7-day return rate. Create a two-week backlog ranked by pilot impact; do not begin invoices or payments yet.

**Verify:** At least five contractors have created and shared a quote, the metrics dashboard/event export works, and the team has a written go/no-go decision with the top five evidence-backed improvements.

**Commit:** `chore: launch closed pilot and capture mvp metrics`

## Release gates

Do not broaden the product until these gates are met in the pilot:

- Median time from tap on “New voice quote” to share is under 60 seconds for a familiar user.
- No incorrect grand total is found in tested quotes.
- At least 80% of pilot users complete a shared quotation with only normal assisted onboarding.
- Speech/extraction failures preserve the transcript and allow a manual quote.
- No cross-user data access is possible through Supabase RLS/Storage policies or the Spring API.
- Offline retries never create a duplicate quote, and a cross-device edit has a safe conflict path.
- Normal authenticated API reads/writes meet the agreed p95 latency target under the expected peak profile.

If a gate fails, use Days 26–30 findings to improve the narrow flow, catalog, or transcription choice. Do not compensate by adding invoices, payment tracking, or more trades.

## Production and 10,000-user readiness guardrails

The day-30 release is a closed pilot, not a claim that usage has already reached 10,000 users. The architecture and checks below ensure it can grow to 10,000 registered users without a redesign. Before opening beyond the pilot, convert expected daily active users, quotes per user, and provider calls per quote into an explicit peak profile and re-run the load test whenever those assumptions change.

- **Initial SLOs:** normal authenticated API reads/writes have p95 latency below 1 second; quote saves below 2 seconds when online; extraction is returned or moved to an asynchronous job within 15 seconds; API availability is at least 99.5% monthly excluding third-party speech/LLM outages; and duplicate or incorrect monetary records have a zero-tolerance release gate.
- **Capacity test:** prove the agreed peak profile against staging with production-like Supabase sizing and the Spring connection-pool limit. Measure p50/p95/p99 latency, error rate, database CPU/connections, job backlog, and third-party-provider saturation. Test the failure path as well as the happy path.
- **Horizontal API scaling:** Spring Boot instances must be stateless. Do not keep drafts, sessions, or job state in process memory. Add instances rather than enlarging a single server; preserve a bounded connection pool so horizontal scaling does not exhaust Postgres connections.
- **Data safety:** all schema changes are migrations reviewed in CI; enable and test backups/point-in-time recovery at the selected Supabase tier; keep a restore and migration-rollback runbook; and make user deletion cover Postgres, Storage, and retained diagnostics.
- **Cost and abuse controls:** apply per-user/device rate limits and input-size/duration limits before calling OpenAI Whisper or any other paid provider. Alert on provider spend, unusual request volume, transcription/extraction failure, and retry storms. Keep raw audio out of permanent storage by default.
- **Growth trigger:** if the durable extraction job table, Postgres connection pool, or load test becomes the bottleneck, introduce a managed queue/worker tier only for that bottleneck. Do not pre-emptively split the API into microservices.

## Deferred until the MVP proves repeat use

Invoices and payment reminders, advance/balance tracking, GST/e-invoice integrations, multiple sites, helper logins, subscriptions, dealer referrals, WhatsApp bot/Business API, extra trades, catalog admin tooling, payment collection, lending, and model fine-tuning. Each needs a separate problem statement, data/privacy review, and measured pilot demand.

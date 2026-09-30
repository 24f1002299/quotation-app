# Day 24 — Device Test Matrix

**Goal:** find failures unavailable in simulators.
**Build under test:** `contractor_quote_poc`, release mode (see §1).
**Status:** lab work done (audit + APK + timers below); device columns are
manual — fill one column per physical phone, then sign off §5.

## 1. Build under test (measured 2026-09-30, this machine)

| Artifact | Size | Use |
|---|---|---|
| `app-arm64-v8a-release.apk` | **20.6 MB** | 👉 install THIS on test phones (all modern Androids are arm64) |
| `app-armeabi-v7a-release.apk` | 18.6 MB | only for very old 32-bit phones |
| `app-release.apk` (universal) | 58.8 MB | do NOT distribute; 3× the download for no benefit |

> Install: `flutter install --release` with the phone on USB debugging, or
> copy the arm64 APK to the phone and tap it. This build uses default
> (local) URLs — good for size and offline/UI tests; voice-network tests need
> a staging build with `--dart-define` URLs (Day 27).

**Lab fix already applied:** the release build failed on an illegal `--`
inside an XML comment in `network_security_config.xml` (debug builds never
hit that parser path). Fixed by rewording the comment; release now builds.
Lesson for the matrix: always validate the exact artifact you ship.

## 2. Devices (fill in)

| # | Role | Model / Android | RAM | Filled by |
|---|---|---|---|---|
| D1 | Lower-memory device (≤3 GB RAM target) | ___ / Android ___ | ___ GB | ___ |
| D2 | Current device | ___ / Android ___ | ___ GB | ___ |

## 3. Scenarios — steps, expected, fallback

Run every row on D1 **and** D2. Mark ✅ / ❌ / N/A per device.

### A. Poor network (airplane-mode toggling + 2G throttle)

| Step | Expected (user-safe fallback) | D1 | D2 |
|---|---|---|---|
| 1. Start a quote offline (no SIM data/Wi-Fi) | `You're offline. This draft is saved on this phone.` + `Continue editing` | ☐ | ☐ |
| 2. Finish review → PDF offline | PDF generates fully offline (on-device renderer) | ☐ | ☐ |
| 3. Reconnect mid-draft | Draft syncs once, no duplicate quote | ☐ | ☐ |
| 4. Throttle to 2G, record 20 s Hindi note, send | Either transcribes or keeps transcript + `Try again` / `Create manually` — never loses the draft | ☐ | ☐ |

### B. Denied microphone permission

| Step | Expected | D1 | D2 |
|---|---|---|---|
| 1. Fresh install → deny mic when asked | `Microphone permission is needed to record. You can still type a quote.` + `Allow microphone`, `Type quote` | ☐ | ☐ |
| 2. `Type quote` path | Full quote completable by typing, PDF shares | ☐ | ☐ |
| 3. Re-tap record after deny (incl. "don't ask again") | Helpful recovery path, no dead end | ☐ | ☐ |

### C. Screen rotation (all core screens)

| Step | Expected | D1 | D2 |
|---|---|---|---|
| 1. Rotate during recording / transcript edit / review / PDF preview | No restart, no lost text, totals unchanged (manifest handles `orientation\|screenSize`, verified statically) | ☐ | ☐ |

### D. Interrupted call + backgrounding during transcription

| Step | Expected | D1 | D2 |
|---|---|---|---|
| 1. Call the test phone while recording | Recording stops safely; partial audio kept or clean re-record offered | ☐ | ☐ |
| 2. Press Home / switch apps during `transcribing…` | Return finds transcript or retry affordance — never a stuck spinner, never a lost draft | ☐ | ☐ |
| 3. Lock screen during extraction | Same as (2) | ☐ | ☐ |

### E. Low storage (<200 MB free)

| Step | Expected | D1 | D2 |
|---|---|---|---|
| 1. Fill storage, then Generate PDF | Error message via SnackBar, app stays alive (save path is try/caught, verified statically) | ☐ | ☐ |
| 2. Record with storage nearly full | Clear message, no crash | ☐ | ☐ |

### F. First-run + noisy-voice sanity (plan's definition of done)

| Step | Expected | D1 | D2 |
|---|---|---|---|
| 1. Fresh install → time until Home is interactive | Record in §4 | ☐ | ☐ |
| 2. Hindi voice note with background noise (fan/site) | Transcript editable; numbers checked by user | ☐ | ☐ |
| 3. Marathi voice note with background noise | Same as (2) | ☐ | ☐ |

## 4. Measurements (fill in; targets are initial SLOs)

Two ways to capture latencies: (a) phone stopwatch, (b) exact numbers from
the app's debug log — the Day-24 build prints `[perf]` lines. With the phone
on USB: `flutter logs | grep perf` (needs a **debug** build:
`flutter run`; `[perf]` lines are stripped from release builds).

| Metric | Target | D1 | D2 |
|---|---|---|---|
| First-launch to interactive Home | < 3 s | ___ s | ___ s |
| Transcription latency (20 s Hindi note, Wi-Fi) | — (record baseline) | ___ s | ___ s |
| Extraction to review screen | sync ≤ 6 s or async job ID (never a hung call) | ___ s | ___ s |
| PDF render (2-line quote) | < 2 s | ___ s | ___ s |
| PDF render (20-line quote) | < 5 s | ___ s | ___ s |
| APK installed (arm64) | 20.6 MB download | ___ MB on disk | ___ MB on disk |

## 5. Blocker log (the Verify deliverable)

Every ❌ above gets one row. Nothing ships to Day-25 testers with an open
P0/P1. A deferral is only valid with a user-safe fallback in the right column.

| ID | Device | Scenario | What happened | Severity (P0/P1/P2) | Fix or explicit fallback | Status |
|---|---|---|---|---|---|---|
| _ex_ | D1 | D-low-storage | _example: PDF save spins forever_ | P1 | _deferred: SnackBar "Storage full — free space and retry"; draft kept_ | open |
| | | | | | | |

**Sign-off:** matrix filled for D1 + D2, zero open P0/P1 → Day 25 may start.

## 6. Static audit notes (already verified in code, re-confirm on device)

- `AndroidManifest.xml`: only `RECORD_AUDIO` + `INTERNET`; no location/contacts/SMS to explain or remove. `configChanges` covers rotation → no Activity restart.
- Voice screen: permission-recovery banner, too-short-recording guard (crumbs never sent to STT), temp-audio cleanup on cancel/supersede.
- Review screen: totals recompute on every edit (Day 5 engine); PDF blocked only with the exact item/field named.
- PDF preview: save wrapped in try/catch + SnackBar; regeneration overwrites the same app-owned file.

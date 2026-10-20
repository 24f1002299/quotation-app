# QuotApp — Voice-First Quotation App for MSME Contractors


## Overview

QuotApp is a production Android application built for tiling, painting, and other MSME trade contractors in Maharashtra, India. It eliminates the friction of manual quotation writing by letting contractors dictate a job in their native language, automatically extracting structured line items via AI, and generating a PDF ready to share via WhatsApp or any other channel — all from a mobile device, even in low-connectivity conditions.

**Core loop:** Speak → Review → PDF → Share. In under a minute.

---

## Key Features

| Feature | Description |
|---|---|
| 🎙️ **Voice Capture** | Record job descriptions in Hindi, Marathi, or Hinglish on any Android device |
| 🤖 **AI Extraction** | Structured line-item extraction via OpenAI Whisper + LLM, constrained by trade catalogs |
| ✏️ **Editable Review** | Every extracted item is editable before a quote is finalized — no silent AI totals |
| 🧾 **PDF Generation** | Branded, on-device PDF generation with contractor logo, GST, and line items |
| 📤 **Native Share** | Share via Android share sheet — WhatsApp, email, Drive, and more |
| 💾 **Offline-First** | Drafts and saved quotes survive app restarts and network outages |
| 🔁 **Rate Memory** | Saved per-trade rates auto-populate future quotes |
| 🔐 **Secure Auth** | Supabase phone OTP authentication; JWT-verified API |
| 🌐 **Multi-Language UI** | Full UI in English, हिंदी, and मराठी — chosen once, remembered forever |

---

## Architecture

```
Flutter Android App
  ├── Encrypted local draft store + durable sync outbox
  ├── Android recorder ──► Spring Boot /transcribe ──► OpenAI Whisper ──► transcript
  ├── Spring Boot API ──► JWT-verified domain API + LLM extraction
  ├── Supabase Auth ──► Phone OTP + JWT issuance
  ├── Supabase Postgres ──► Profiles, rates, quotes, feedback
  ├── Supabase Storage ──► Contractor logos, optional PDF backup
  └── On-device PDF renderer + Android share sheet
```

### Security Model

- The **OpenAI API key** never reaches the device — all AI calls go through the authenticated Spring Boot API
- The **Supabase service-role key** lives only on the server; the app uses only the anon key
- **Row-Level Security** is enforced on every Supabase table — User A cannot access User B's data through any path
- Every API write includes an **idempotency key**; mutable records carry a **version** for conflict detection
- Audio recordings are deleted from the device immediately after successful transcription

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Dart) — Android |
| Backend API | Spring Boot 3 (Java 21) |
| Authentication | Supabase Auth (Phone OTP) |
| Database | Supabase Postgres (with RLS) |
| Storage | Supabase Storage |
| AI — Speech | OpenAI Whisper (`whisper-1`) via Spring Boot |
| AI — Extraction | OpenAI Chat API via Spring Boot |
| Hosting | Render (Docker) |
| PDF | `pdf` + `printing` Flutter packages (on-device) |

---

## Project Structure

```
contractor_quote_poc/         # Flutter Android app
  lib/
    config/                   # API & Supabase configuration (dart-define injected)
    models/                   # Domain models: Quote, LineItem, BusinessProfile, etc.
    screens/                  # All UI screens
    voice/                    # Audio recording, transcription service
    storage/                  # Repositories, sync outbox, local cache
    pdf/                      # PDF generation engine
    templates/                # Quote template logic
    theme/                    # App theme and design tokens
    utils/                    # Money arithmetic, formatters, validators
    parser/                   # Catalog-constrained extraction parsing

spring-api/                   # Spring Boot backend
  src/main/java/...
    auth/                     # JWT verification (Supabase JWKS)
    transcription/            # Whisper audio transcription endpoint
    extraction/               # LLM line-item extraction endpoint
    quotes/                   # Quote CRUD + sync endpoint
    profiles/                 # Contractor profile endpoint
    services/                 # Rate/service item management
    storage/                  # Signed URL generation
```

---

## Getting Started

### Prerequisites

- Flutter SDK `>=3.13.4`
- Java 21 (for the Spring Boot API)
- Android SDK (API 21+)
- A [Supabase](https://supabase.com) project
- An OpenAI API key

### 1. Clone the repository

```bash
git clone https://github.com/24f1002299/quotation-app.git
cd quotation-app
```

### 2. Configure environment files

**Flutter app** — create `contractor_quote_poc/env.prod.json` (gitignored):

```json
{
  "API_BASE_URL": "https://<your-render-service>.onrender.com/api",
  "SUPABASE_URL": "https://<your-project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<your-supabase-anon-key>"
}
```

For local development, create `contractor_quote_poc/env.dev.json`:

```json
{
  "API_BASE_URL": "http://10.0.2.2:8080/api",
  "SUPABASE_URL": "http://10.0.2.2:54321",
  "SUPABASE_ANON_KEY": "<your-local-anon-key>"
}
```

**Spring Boot API** — copy and fill `spring-api/.env.example` → `spring-api/.env` (gitignored):

```bash
cp spring-api/.env.example spring-api/.env
# Edit spring-api/.env with your keys
```

### 3. Run the Flutter app (development)

```bash
cd contractor_quote_poc
flutter pub get
flutter run --dart-define-from-file=env.dev.json
```

### 4. Run the Spring Boot API (development)

```bash
cd spring-api
./run-dev.ps1        # Windows PowerShell
# or
mvn spring-boot:run  # directly
```

---

## Building for Distribution

### Release APK

```bash
cd contractor_quote_poc
flutter build apk --release --dart-define-from-file=env.prod.json
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Distribute the APK directly. Recipients must enable **Install from unknown sources** on their Android device.

---

## Backend Deployment

The Spring Boot API is deployed to [Render](https://render.com) via Docker.

### Deploy via render.yaml (recommended)

The repository includes a `render.yaml` blueprint. In the Render dashboard:

1. Go to **Blueprints** → **New Blueprint Instance**
2. Connect your GitHub repository
3. Render will read `render.yaml` and configure the service automatically

### Manual deploy configuration

If deploying the service manually via the Render dashboard, set:

| Setting | Value |
|---|---|
| **Runtime** | Docker |
| **Dockerfile Path** | `spring-api/Dockerfile` |
| **Docker Context** | `spring-api` |
| **Health Check Path** | `/api/health` |

Set all environment variables listed in `render.yaml` under **Environment** in the Render dashboard.

> **Note:** On the free Render tier, the instance spins down after inactivity. The first request after ~15 minutes may take up to 50 seconds (cold start). Subsequent requests are fast.

---

## Environment Variables Reference

### Spring Boot API (`spring-api/.env`)

| Variable | Description |
|---|---|
| `DATABASE_URL` | Supabase Postgres connection string |
| `DATABASE_APP_ROLE_PASSWORD` | Password for the least-privilege DB role |
| `SUPABASE_JWKS_URL` | Supabase JWKS endpoint for JWT verification |
| `SUPABASE_URL` | Supabase project URL |
| `OPENAI_API_KEY` | OpenAI API key (Whisper + Chat) |
| `OPENAI_STT_URL` | Speech-to-text API endpoint |
| `OPENAI_STT_MODEL` | STT model name (e.g. `whisper-1`) |
| `OPENAI_CHAT_URL` | Chat completions API endpoint |
| `OPENAI_CHAT_MODEL` | Chat model name |
| `DEFAULT_STT_PROVIDER` | `whisper` or `xai` |
| `DEFAULT_LLM_PROVIDER` | `openai` or `xai` |
| `CORS_ALLOWED_ORIGINS` | Comma-separated allowed origins |
| `DEV_BYPASS_ENABLED` | `false` in production always |

### Flutter App (`env.prod.json` / `env.dev.json`)

| Variable | Description |
|---|---|
| `API_BASE_URL` | Full base URL of the Spring Boot API |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon (public) key — safe to ship in the app |

> ⚠️ **Never** put the Supabase `service_role` key in the Flutter app. It bypasses all Row-Level Security policies.

---

## Security Notes

- `env.prod.json`, `env.dev.json`, and `spring-api/.env` are **gitignored** and must never be committed
- The Supabase anon key is safe to include in the app — RLS policies restrict all data access to the authenticated user
- The OpenAI API key is a server-side secret — it is never transmitted to or stored on the device
- All audio is sent only to the authenticated Spring Boot endpoint over HTTPS and is not logged or stored permanently

---

## MVP Scope

This release covers:

- ✅ Phone OTP sign-in
- ✅ Contractor profile setup (name, business, trade, logo, GSTIN)
- ✅ Trade catalog selection (tiling, painting)
- ✅ Voice capture in Hindi, Marathi, and Hinglish
- ✅ AI line-item extraction constrained to trade catalogs
- ✅ Editable review screen with flagging for uncertain items
- ✅ On-device PDF generation with branding
- ✅ Share via Android share sheet (WhatsApp, email, etc.)
- ✅ Quote history with reopen and re-share
- ✅ Offline draft survival with sync outbox
- ✅ Saved rate memory per trade

**Out of scope for this release:** invoicing, payments, multi-user accounts, dealer tooling, referral flows, WhatsApp bot, web dashboard.

---

## License

Private and proprietary. All rights reserved.

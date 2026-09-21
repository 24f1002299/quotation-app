# Supabase Setup Guide — quotapp

This document contains the **manual steps** you must complete in the Supabase dashboard and terminal. All SQL migrations, Spring Boot code, and tests have been generated automatically. You only need to do the steps below once per environment.

---

## Step 1 — Create Supabase projects

> **Free tier limit:** Supabase free accounts allow **2 projects**. Use this 2-project strategy:
>
> | Project name | Used for |
> |---|---|
> | `quotapp-dev` | Local development + all integration tests. Safe to reset/wipe. |
> | `quotapp-prod` | Production pilot users. Treat with care — never run migrations untested. |
>
> **What about staging?** On the free plan, skip a separate staging project. Instead:
> - Test every migration on `quotapp-dev` first using `migration_apply_test.sh`
> - Only push to `quotapp-prod` after migrations pass on dev
> - When you upgrade to the Supabase Pro plan, add `quotapp-staging` then

### Create the 2 projects

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. Click **New project** → create `quotapp-dev`
3. Click **New project** again → create `quotapp-prod`
4. For **each project**, go to **Settings → General** and copy the **Project Reference** (looks like `abcdefghijklmnop`). You'll need it in later steps.

---

## Step 2 — Configure Authentication

> **What is Twilio and do you need it now?**
> Supabase handles authentication logic but needs a third-party SMS service to actually *deliver* the OTP text message to a contractor's phone. Twilio is that SMS delivery service.
> **You do NOT need Twilio today (Day 7).** Set it up when you build the sign-in screen on Day 19. For now, just enable Email on the dev project and you're good.

### Dev project — enable Email for testing (do this now ✅)
1. Supabase Dashboard → **Authentication** → **Providers**
2. Enable **Email** provider
3. Turn OFF **"Confirm email"** (makes test sign-in instant — no inbox needed)
4. Click **Save**

### Production project — enable Phone OTP (defer to Day 19 🕐)
You'll set this up when building the real sign-in screen. Skip for now.

When you're ready (Day 19):
1. Authentication → Providers → **Phone**
2. Choose **Twilio**
3. Enter your Twilio Account SID, Auth Token, and Twilio phone number
   - Get a Twilio number at [console.twilio.com](https://console.twilio.com) → Numbers & Senders → Buy a number
   - Trial accounts can only SMS to manually verified numbers — enough for the pilot
4. Click **Save**


---

## Step 3 — Run SQL migrations

### Option A — Supabase CLI (recommended)

Install the CLI if you haven't:
```bash
# Windows (using scoop or direct binary)
scoop install supabase
# OR download from: https://github.com/supabase/cli/releases
```

Start local Docker:
```bash
supabase start
```

Apply migrations:
```bash
# From the project root (d:\Projects\android app)
supabase db push
```

### Option B — Supabase SQL Editor (manual)

1. Go to Supabase Dashboard → **SQL Editor**
2. Open and run each file **in order**:
   - `supabase/migrations/001_initial_schema.sql`
   - `supabase/migrations/002_rls_policies.sql`
   - `supabase/migrations/003_app_role.sql`
   - `supabase/migrations/004_indexes.sql`
3. For dev only: also run `supabase/seed.sql`

---

## Step 4 — Set the app_role password

In `003_app_role.sql` there is a placeholder: `REPLACE_WITH_STRONG_PASSWORD`.

1. In the SQL Editor, run:
   ```sql
   ALTER ROLE app_role WITH PASSWORD 'choose-a-strong-password-here';
   ```
2. Save this password — you'll put it in the Spring Boot `.env` file as `DATABASE_APP_ROLE_PASSWORD`

---

## Step 5 — Get your project keys

For **each Supabase project**:

1. Dashboard → **Settings** → **API**
2. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon / public** key → `SUPABASE_ANON_KEY` (safe to put in Flutter app)
   - **JWKS URL** → `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`
   - **Direct connection** string → `DATABASE_URL` (in Spring Boot `.env`)

> ⚠️ **NEVER copy the service_role key into the Flutter app or Spring `.env.example`.** It bypasses all RLS.

---

## Step 6 — Configure Spring Boot environment

1. Copy `spring-api/.env.example` → `spring-api/.env`
2. Fill in the values for your dev project:
   ```
   DATABASE_URL=jdbc:postgresql://db.<project-ref>.supabase.co:5432/postgres
   DATABASE_APP_ROLE_PASSWORD=the-password-from-step-4
   SUPABASE_JWKS_URL=https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
   SUPABASE_URL=https://<project-ref>.supabase.co
   SPRING_PROFILES_ACTIVE=dev
   ```
3. Start Spring Boot:
   ```bash
   cd spring-api
   ./mvnw spring-boot:run
   ```

---

## Step 7 — Configure Flutter app

When running Flutter, pass the anon key via `--dart-define`:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-public-key>
```

For local dev with Supabase Docker:
```bash
flutter run \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<key-from-supabase-start-output>
```

---

## Step 8 — Create the Storage bucket

If `002_rls_policies.sql` didn't auto-create the bucket (it runs an INSERT — may need dashboard confirmation):

1. Dashboard → **Storage** → **New bucket**
2. Name: `user-files`
3. Make sure **Public bucket** is **OFF** (must be private)
4. File size limit: `5 MB`
5. Click Create

---

## Step 9 — Verify RLS is on

1. Dashboard → **Table Editor** → select each table
2. Click the **RLS** badge — it should show "RLS enabled"
3. Click **Policies** — each table should have 4 policies (SELECT / INSERT / UPDATE / DELETE scoped to auth.uid())

---

## Step 10 — Run integration tests

### RLS tests (pgTAP)
```bash
supabase test db
```

### Spring tests
```bash
cd spring-api
./mvnw test -Dtest=CrossUserIsolationTest,JwtValidationTest
```

### Migration clean-apply
```bash
bash supabase/tests/migration_apply_test.sh
```

---

## Verification checklist

- [ ] User A cannot read User B's quotes in Supabase Table Editor (switch RLS viewer user)
- [ ] Spring API returns 403/404 when authenticated as User A and requesting User B's resources
- [ ] Flutter app starts without "SUPABASE_ANON_KEY is not set" assertion error
- [ ] No `service_role` key appears anywhere in Flutter source or APK
- [ ] All 4 migrations apply cleanly to an empty database (migration_apply_test.sh exits 0)
- [ ] `supabase test db` passes all 24 assertions

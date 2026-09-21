-- Migration: 001_initial_schema
-- Creates all user-owned tables for the quotation app.
-- Every table references auth.uid() as user_id.
-- Never alter auth.* tables; Supabase manages those.

-- ─────────────────────────────────────────────
-- profiles
-- One row per authenticated user. Created on first sign-in.
-- ─────────────────────────────────────────────
create table if not exists public.profiles (
  id            uuid        primary key references auth.users(id) on delete cascade,
  user_id       uuid        not null unique references auth.users(id) on delete cascade,
  business_name text        not null default '',
  trade         text        not null default 'tiling' check (trade in ('tiling', 'painting')),
  city          text        not null default '',
  phone         text        not null default '',
  gstin         text,
  logo_path     text,                           -- relative path inside user's storage bucket folder
  quote_terms   text        not null default '',
  schema_version int        not null default 1,
  version       int         not null default 1, -- optimistic locking
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.profiles is 'One row per contractor; scoped by auth.uid() via RLS.';

-- ─────────────────────────────────────────────
-- rate_memory
-- Contractor's saved per-item rates.
-- ─────────────────────────────────────────────
create table if not exists public.rate_memory (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users(id) on delete cascade,
  catalog_item_id text        not null,   -- matches item id in bundled trade catalog JSON
  trade           text        not null check (trade in ('tiling', 'painting')),
  unit_rate_paise bigint      not null check (unit_rate_paise >= 0),
  unit            text        not null,
  schema_version  int         not null default 1,
  version         int         not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, catalog_item_id, trade)
);
comment on table public.rate_memory is 'Per-user saved rates, keyed by catalog item id.';

-- ─────────────────────────────────────────────
-- quotes
-- Master quote record. Line items are in a child table.
-- ─────────────────────────────────────────────
create table if not exists public.quotes (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users(id) on delete cascade,
  idempotency_key   text        not null,       -- client-generated UUID; server accepts each key once
  display_number    text,                       -- human-readable, assigned by server after first sync
  status            text        not null default 'draft'
                                  check (status in ('draft', 'needsReview', 'ready', 'shared')),
  trade             text        not null check (trade in ('tiling', 'painting')),
  client_name       text        not null default '',
  client_phone      text,
  site_address      text,
  gst_percent       int         check (gst_percent is null or (gst_percent >= 0 and gst_percent <= 100)),
  subtotal_paise    bigint      not null default 0 check (subtotal_paise >= 0),
  gst_paise         bigint      not null default 0 check (gst_paise >= 0),
  grand_total_paise bigint      not null default 0 check (grand_total_paise >= 0),
  quote_date        date        not null default current_date,
  valid_until       date,
  advance_text      text,
  notes             text,
  terms             text,
  original_transcript text,
  schema_version    int         not null default 1,
  version           int         not null default 1,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (user_id, idempotency_key)             -- idempotency guard
);
comment on table public.quotes is 'Top-level quote owned by one contractor. Idempotency key prevents duplicate writes.';

-- ─────────────────────────────────────────────
-- quote_line_items
-- Child rows belonging to one quote.
-- ─────────────────────────────────────────────
create table if not exists public.quote_line_items (
  id               uuid    primary key default gen_random_uuid(),
  user_id          uuid    not null references auth.users(id) on delete cascade,
  quote_id         uuid    not null references public.quotes(id) on delete cascade,
  catalog_item_id  text,                         -- null if manually typed
  description      text    not null,
  quantity_x1000   bigint  not null check (quantity_x1000 > 0),  -- quantity * 1000 (3 decimal places)
  unit             text    not null,
  unit_rate_paise  bigint  not null check (unit_rate_paise >= 0),
  amount_paise     bigint  not null check (amount_paise >= 0),
  confidence       text    check (confidence in ('high', 'medium', 'low', 'unknown')),
  sort_order       int     not null default 0,
  schema_version   int     not null default 1,
  version          int     not null default 1,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on table public.quote_line_items is 'Line items for a quote; user_id duplicated for RLS efficiency.';

-- ─────────────────────────────────────────────
-- edit_feedback
-- Privacy-minimal correction telemetry.
-- Raw audio is never stored here.
-- ─────────────────────────────────────────────
create table if not exists public.edit_feedback (
  id                uuid    primary key default gen_random_uuid(),
  user_id           uuid    not null references auth.users(id) on delete cascade,
  quote_id_hash     text    not null,            -- SHA-256 of quote UUID — not the raw ID
  trade             text    not null check (trade in ('tiling', 'painting')),
  catalog_item_id   text,
  model_result      text,
  final_value       text,
  changed_field     text    not null check (changed_field in ('description', 'quantity', 'unit', 'rate')),
  schema_version    int     not null default 1,
  created_at        timestamptz not null default now()
  -- no version column: feedback is append-only
);
comment on table public.edit_feedback is 'Privacy-minimal telemetry; no raw audio, quote ID is hashed.';

-- ─────────────────────────────────────────────
-- updated_at trigger (shared function)
-- ─────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace trigger trg_rate_memory_updated_at
  before update on public.rate_memory
  for each row execute function public.set_updated_at();

create or replace trigger trg_quotes_updated_at
  before update on public.quotes
  for each row execute function public.set_updated_at();

create or replace trigger trg_quote_line_items_updated_at
  before update on public.quote_line_items
  for each row execute function public.set_updated_at();

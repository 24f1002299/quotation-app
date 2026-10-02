-- Migration: 007_universal_business
-- Makes voice extraction work for ANY business domain, not just tiling/painting.
--
-- What changes:
--   1. profiles gains business_type (free-form slug, e.g. 'tiling', 'pest_control',
--      'catering'), backfilled from the legacy trade column. Also gains owner_name
--      and address, which the Flutter BusinessProfile already sends but the DB
--      had no columns for.
--   2. New service_items table: the user's own service list (replaces the fixed
--      bundled catalog + rate_memory keyed by catalog ids). Rate memory stays for
--      backward compatibility; service_items.rate_paise is the source of truth
--      going forward.
--   3. Legacy trade CHECK constraints (tiling|painting only) are dropped on
--      profiles, rate_memory, quotes and edit_feedback so existing rows keep
--      working and any business slug is accepted. The columns themselves are
--      kept for backward compatibility.
--
-- Rollback: drop table public.service_items; drop the added columns. The
-- dropped CHECK constraints are not restored (old clients send any slug now).

-- ─────────────────────────────────────────────
-- 1. profiles: universal business columns
-- ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists business_type text not null default 'tiling';

alter table public.profiles
  add column if not exists owner_name text not null default '';

alter table public.profiles
  add column if not exists address text not null default '';

-- Backfill the new column from the legacy trade value.
update public.profiles
set business_type = trade
where business_type = 'tiling' and trade <> 'tiling';

-- Drop the two-value CHECK so any business slug is accepted.
-- (Auto-generated name for the inline check in 001.)
alter table public.profiles
  drop constraint if exists profiles_trade_check;

comment on column public.profiles.business_type is
  'Free-form business slug (tiling, painting, pest_control, catering, ...). Source of truth; trade is legacy.';

-- ─────────────────────────────────────────────
-- 2. service_items: the user''s own service list
-- ─────────────────────────────────────────────
create table if not exists public.service_items (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users(id) on delete cascade,
  client_id       text        not null,  -- offline-safe id generated on the phone (svc_...); no default so the unique pair is never accidentally duplicated
  name            text        not null default '',
  name_hi         text,
  name_mr         text,
  unit            text        not null default 'item',
  rate_paise      bigint      not null default 0 check (rate_paise >= 0),
  business_type   text        not null default 'tiling',
  keywords        jsonb       not null default '[]'::jsonb,  -- speech synonyms
  is_active       boolean     not null default true,
  sort_order      int         not null default 0,
  notes           text        not null default '',
  schema_version  int         not null default 1,
  version         int         not null default 1,  -- optimistic locking
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, client_id)
);
comment on table public.service_items is
  'Per-user service list; the extraction context for any business domain. client_id is the phone-generated id.';

create index if not exists idx_service_items_user_business
  on public.service_items (user_id, business_type)
  where is_active = true;

-- Keep updated_at fresh (shared trigger function from 001).
drop trigger if exists trg_service_items_updated_at on public.service_items;
create trigger trg_service_items_updated_at
  before update on public.service_items
  for each row execute function public.set_updated_at();

-- RLS: owner-only, mirroring rate_memory (002).
alter table public.service_items enable row level security;

drop policy if exists "service_items: owner can select" on public.service_items;
create policy "service_items: owner can select"
  on public.service_items for select
  using (auth.uid() = user_id);

drop policy if exists "service_items: owner can insert" on public.service_items;
create policy "service_items: owner can insert"
  on public.service_items for insert
  with check (auth.uid() = user_id);

drop policy if exists "service_items: owner can update" on public.service_items;
create policy "service_items: owner can update"
  on public.service_items for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "service_items: owner can delete" on public.service_items;
create policy "service_items: owner can delete"
  on public.service_items for delete
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- 3. Relax legacy trade CHECKs (keep columns for compat)
-- ─────────────────────────────────────────────
alter table public.rate_memory
  drop constraint if exists rate_memory_trade_check;

alter table public.quotes
  drop constraint if exists quotes_trade_check;

alter table public.edit_feedback
  drop constraint if exists edit_feedback_trade_check;

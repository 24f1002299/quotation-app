-- Migration: 008_profile_defaults
-- Adds the plan's BusinessProfile preferences (default unit + currency).
-- Backward compatible: NOT NULL with safe defaults so existing rows keep working.
-- Rollback: drop columns default_unit, currency from public.profiles.

alter table public.profiles
  add column if not exists default_unit text not null default 'item';

alter table public.profiles
  add column if not exists currency text not null default 'INR';

comment on column public.profiles.default_unit is
  'Most common unit for this business (sq ft, nos, item, ...). Used as the default in add-item sheets.';
comment on column public.profiles.currency is
  'ISO currency code. INR for MVP; future multi-currency support.';

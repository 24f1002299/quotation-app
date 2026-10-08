-- Migration: 009_universal_business_completion
-- Completes the universal-MSME pivot at the DB layer, mirroring the API
-- rename (trade -> business_type, catalog_item_id -> service_item_id).
--
-- What changes:
--   1. edit_feedback gains business_type + service_item_id (canonical),
--      backfilled from the legacy trade / catalog_item_id columns.
--   2. quotes gains business_type (canonical), backfilled from trade.
--   3. Legacy columns are KEPT for backward compatibility with old clients;
--      no CHECK constraints are added, so any business slug is accepted.
--
-- Rollback: drop the added columns. Legacy columns and data are untouched.

-- ─────────────────────────────────────────────
-- 1. edit_feedback: canonical universal columns
-- ─────────────────────────────────────────────
alter table public.edit_feedback
  add column if not exists business_type text not null default '';

alter table public.edit_feedback
  add column if not exists service_item_id text;

-- Backfill canonical columns from legacy values (only where still empty).
update public.edit_feedback
set business_type = trade
where business_type = '' and trade is not null and trade <> '';

update public.edit_feedback
set service_item_id = catalog_item_id
where service_item_id is null and catalog_item_id is not null;

comment on column public.edit_feedback.business_type is
  'Free-form business slug (tiling, pest_control, catering, ...). Source of truth; trade is legacy.';
comment on column public.edit_feedback.service_item_id is
  'User service id. Source of truth; catalog_item_id is legacy.';

-- ─────────────────────────────────────────────
-- 2. quotes: canonical business_type
-- ─────────────────────────────────────────────
alter table public.quotes
  add column if not exists business_type text not null default '';

update public.quotes
set business_type = trade
where business_type = '' and trade is not null and trade <> '';

comment on column public.quotes.business_type is
  'Free-form business slug. Source of truth; trade is legacy.';

-- ─────────────────────────────────────────────
-- 3. Anonymisation keeps both old and new id columns redacted
-- ─────────────────────────────────────────────
create or replace function public.anonymize_feedback_for_quote(p_quote_hash text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int := 0;
begin
  if p_quote_hash is null or p_quote_hash !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'quote hash must be SHA-256 hex (64 hex chars)';
  end if;

  update public.edit_feedback
  set model_result = '[redacted]',
      final_value = '[redacted]',
      catalog_item_id = null,
      service_item_id = null
  where quote_id_hash = lower(p_quote_hash)
    and user_id = auth.uid();

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

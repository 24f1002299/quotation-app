-- Migration: 006_feedback_lifecycle
-- Day 21: documented deletion/anonymisation policy for correction feedback.
--
-- Policy (see docs/feedback-privacy.md):
--   * edit_feedback is append-only from the client (no UPDATE/DELETE RLS policies).
--   * Deleting a quote MUST delete its feedback rows, matched by
--     quote_id_hash = SHA-256(raw quote UUID). Raw quote IDs never appear here.
--   * Deletion runs server-side (Spring API service path or this function).
--     The client cannot delete feedback directly.
--   * Anonymisation (redact model_result/final_value, keep trade+changed_field
--     counts) is the alternative when hard-delete is not possible (exports).

-- Server-side deletion function. SECURITY DEFINER so the Spring app_role
-- (which has DML but is bound by RLS) can clean up exactly the caller's rows.
create or replace function public.delete_feedback_for_quote(p_quote_hash text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_removed int := 0;
begin
  if p_quote_hash is null or p_quote_hash !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'quote hash must be SHA-256 hex (64 hex chars)';
  end if;

  delete from public.edit_feedback
  where quote_id_hash = lower(p_quote_hash)
    and user_id = auth.uid();

  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

comment on function public.delete_feedback_for_quote(text) is
  'Day 21: deletes the caller''s feedback rows for one hashed quote id. Called when a quote is deleted.';

-- Anonymisation alternative: keeps aggregate counts, redacts values.
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
      catalog_item_id = null
  where quote_id_hash = lower(p_quote_hash)
    and user_id = auth.uid();

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

comment on function public.anonymize_feedback_for_quote(text) is
  'Day 21: redacts model/final values for one hashed quote id; use when hard-delete is unavailable.';

-- Allow the least-privilege Spring role to execute lifecycle functions.
-- (No direct DELETE grant change: clients still cannot delete feedback.)
grant execute on function public.delete_feedback_for_quote(text) to app_role;
grant execute on function public.anonymize_feedback_for_quote(text) to app_role;

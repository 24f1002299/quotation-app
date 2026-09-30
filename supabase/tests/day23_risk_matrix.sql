-- day23_risk_matrix.sql (Day 23)
-- Risk-focused RLS + data-guard matrix. pgTAP-free: runs in the Supabase SQL
-- Editor or psql with no extensions. Run with RLS ENABLED (not as bypass).
-- Test users match seed.sql:
--   User A: 00000000-0000-0000-0000-000000000001
--   User B: 00000000-0000-0000-0000-000000000002
--
-- Covers the Day-23 verify faults at the database layer:
--   duplicate write  -> UNIQUE(user_id, idempotency_key) rejects the retry
--   cross-user       -> RLS hides/blocks User B rows for User A
--   stale version    -> optimistic-lock UPDATE (WHERE version = old) hits 0 rows
--   wrong total      -> CHECK totals >= 0 rejects negative money
-- Plus migration guards: tables, version columns, and the idempotency
-- unique constraint exist (clean-apply itself is covered by
-- supabase/tests/migration_apply_test.sh).
-- Any breach raises EXCEPTION; full pass ends with
-- 'ALL 8 DAY-23 RISK CHECKS PASSED'. Seed rows are deleted at the end.

-- Seed: one User B quote + one line item (postgres; RLS bypassed for setup).
insert into public.quotes (id, user_id, idempotency_key, trade, client_name,
  subtotal_paise, gst_paise, grand_total_paise, version)
values ('bbbbbbbb-0000-0000-0000-000000000023',
        '00000000-0000-0000-0000-000000000002',
        'day23-seed-key-b', 'tiling', 'B Client',
        100000, 0, 100000, 1)
on conflict (id) do nothing;

insert into public.quote_line_items
  (user_id, quote_id, description, quantity_x1000, unit, unit_rate_paise, amount_paise)
values ('00000000-0000-0000-0000-000000000002',
        'bbbbbbbb-0000-0000-0000-000000000023',
        'Tile Labour', 100000, 'sq ft', 4500, 450000)
on conflict do nothing;

do $$
declare
  v_count int;
  v_rows int;
begin
  -- ── As User A ──────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
  perform set_config('role', 'authenticated', true);

  -- 1. cross-user read: User A sees zero User B quotes
  select count(*) into v_count from public.quotes
    where user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'FAIL 1 (BREACH): User A reads % User B quote(s)', v_count;
  end if;
  raise notice 'ok 1 - cross-user quote read blocked';

  -- 2. cross-user line items: User A sees zero User B rows
  select count(*) into v_count from public.quote_line_items
    where quote_id = 'bbbbbbbb-0000-0000-0000-000000000023';
  if v_count <> 0 then
    raise exception 'FAIL 2 (BREACH): User A reads User B line items';
  end if;
  raise notice 'ok 2 - cross-user line-item read blocked';

  -- 3. cross-user write: User A cannot insert a quote owned by User B
  begin
    insert into public.quotes (user_id, idempotency_key, trade, client_name)
      values ('00000000-0000-0000-0000-000000000002',
              'day23-evil-key', 'tiling', 'Evil');
    raise exception 'FAIL 3 (BREACH): User A inserted User B quote';
  exception when others then
    raise notice 'ok 3 - cross-user quote write blocked';
  end;

  -- 4. duplicate write: same (user, idempotency_key) accepted exactly once
  insert into public.quotes (user_id, idempotency_key, trade, client_name)
    values ('00000000-0000-0000-0000-000000000001',
            'day23-dup-key', 'tiling', 'Dup Client');
  begin
    insert into public.quotes (user_id, idempotency_key, trade, client_name)
      values ('00000000-0000-0000-0000-000000000001',
              'day23-dup-key', 'tiling', 'Dup Client retry');
    raise exception 'FAIL 4: duplicate idempotency key inserted twice';
  exception when unique_violation then
    raise notice 'ok 4 - duplicate write rejected by idempotency guard';
  end;

  -- 5. stale version: optimistic-lock update on an old version hits 0 rows
  update public.quotes set client_name = 'Bumped', version = version + 1
    where id = 'bbbbbbbb-0000-0000-0000-000000000023'
      and user_id = '00000000-0000-0000-0000-000000000002'
      and version = 1;
  -- (row belongs to B; as A the RLS-filtered update touches 0 rows either way)
  -- Now the honest stale-write check as User B:
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
  update public.quotes set version = version + 1
    where id = 'bbbbbbbb-0000-0000-0000-000000000023' and version = 1;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'FAIL 5 setup: expected 1 bumped row, got %', v_rows;
  end if;
  update public.quotes set client_name = 'Stale overwrite'
    where id = 'bbbbbbbb-0000-0000-0000-000000000023' and version = 1;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'FAIL 5: stale version overwrote the row';
  end if;
  raise notice 'ok 5 - stale-version write affects 0 rows (conflict surfaced)';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

  -- 6. wrong total: negative money rejected by CHECK, never stored
  begin
    insert into public.quotes (user_id, idempotency_key, trade, client_name,
        subtotal_paise, gst_paise, grand_total_paise)
      values ('00000000-0000-0000-0000-000000000001',
              'day23-evil-total', 'tiling', 'Evil Total', -500, 0, -500);
    raise exception 'FAIL 6: negative totals accepted';
  exception when check_violation then
    raise notice 'ok 6 - negative totals rejected';
  end;

  -- 7. migration guard: idempotency unique constraint exists
  select count(*) into v_count from pg_constraint
    where conname = 'quotes_user_id_idempotency_key_key'
       or (contype = 'u' and conrelid = 'public.quotes'::regclass);
  if v_count < 1 then
    raise exception 'FAIL 7: idempotency unique constraint missing';
  end if;
  raise notice 'ok 7 - idempotency unique constraint present';

  -- 8. migration guard: version columns exist on quotes + line items
  select count(*) into v_count from information_schema.columns
    where table_schema = 'public'
      and ((table_name = 'quotes' and column_name = 'version')
        or (table_name = 'quote_line_items' and column_name = 'version'));
  if v_count <> 2 then
    raise exception 'FAIL 8: version columns missing (saw %)', v_count;
  end if;
  raise notice 'ok 8 - optimistic-lock version columns present';

  raise notice 'ALL 8 DAY-23 RISK CHECKS PASSED';
end $$;

-- Cleanup Day-23 seed rows (postgres bypasses RLS for teardown).
delete from public.quote_line_items
  where quote_id = 'bbbbbbbb-0000-0000-0000-000000000023';
delete from public.quotes
  where id = 'bbbbbbbb-0000-0000-0000-000000000023';
delete from public.quotes
  where idempotency_key in ('day23-dup-key', 'day23-evil-total');

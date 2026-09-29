-- rls_isolation_test.sql (Day 22)
-- pgTAP-free version: runs in the Supabase SQL Editor or psql with no
-- extensions needed. Run with RLS ENABLED (not as bypass) so the policies
-- are actually exercised. Test users match seed.sql:
--   User A: 00000000-0000-0000-0000-000000000001
--   User B: 00000000-0000-0000-0000-000000000002
--
-- How it works: seeds User B rows as postgres, then impersonates each
-- contractor via the JWT claim + role (same mechanism PostgREST / the
-- Spring API uses). Any breach raises EXCEPTION and stops the script;
-- full pass ends with 'ALL 19 RLS ISOLATION CHECKS PASSED'.
-- Seed rows added by this script are deleted at the end.

-- Seed User B rows (run as postgres; RLS bypassed for setup only).
insert into public.rate_memory (user_id, catalog_item_id, trade, unit_rate_paise, unit)
values ('00000000-0000-0000-0000-000000000002', 'paint-emulsion', 'painting', 8500, 'sq_ft')
on conflict do nothing;

insert into public.quote_line_items
  (user_id, quote_id, description, quantity_x1000, unit, unit_rate_paise, amount_paise)
values (
  '00000000-0000-0000-0000-000000000002',
  'bbbbbbbb-0000-0000-0000-000000000002',
  'Emulsion Paint', 1000, 'sq_ft', 8500, 8500000
)
on conflict do nothing;

insert into public.edit_feedback
  (user_id, quote_id_hash, trade, changed_field)
values (
  '00000000-0000-0000-0000-000000000002',
  encode(digest('bbbbbbbb-0000-0000-0000-000000000002', 'sha256'), 'hex'),
  'painting', 'quantity'
)
on conflict do nothing;

do $$
declare
  v_count int;
  v_rows int;
begin
  -- ── As User A ──────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
  perform set_config('role', 'authenticated', true);

  -- 1. profiles: User A sees own profile
  select count(*) into v_count from public.profiles
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 1 then
    raise exception 'FAIL 1: User A should see 1 own profile, saw %', v_count;
  end if;
  raise notice 'ok 1 - User A can select own profile';

  -- 2. profiles: User A cannot see User B profile
  select count(*) into v_count from public.profiles
    where user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'FAIL 2 (BREACH): User A sees User B profile';
  end if;
  raise notice 'ok 2 - User A cannot see User B profile';

  -- 3. profiles: User A cannot insert a profile for User B
  begin
    insert into public.profiles (id, user_id, business_name, trade)
      values ('00000000-0000-0000-0000-000000000002',
              '00000000-0000-0000-0000-000000000002', 'Evil Corp', 'tiling');
    raise exception 'FAIL 3 (BREACH): User A inserted User B profile';
  exception when others then
    raise notice 'ok 3 - User A cannot insert User B profile';
  end;

  -- 4. quotes: User A sees own quotes
  select count(*) into v_count from public.quotes
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count < 1 then
    raise exception 'FAIL 4: User A should see own quotes, saw %', v_count;
  end if;
  raise notice 'ok 4 - User A can select own quotes';

  -- 5. quotes: User A cannot see User B quotes
  select count(*) into v_count from public.quotes
    where user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'FAIL 5 (BREACH): User A sees User B quotes';
  end if;
  raise notice 'ok 5 - User A cannot see User B quotes';

  -- 6. quotes: User A cannot insert a quote for User B
  begin
    insert into public.quotes (user_id, idempotency_key, trade, client_name)
      values ('00000000-0000-0000-0000-000000000002',
              'evil-key', 'tiling', 'Evil Client');
    raise exception 'FAIL 6 (BREACH): User A inserted quote for User B';
  exception when others then
    raise notice 'ok 6 - User A cannot insert quote for User B';
  end;

  -- 7. quotes: User A cannot update User B quote
  update public.quotes set client_name = 'Hacked'
    where user_id = '00000000-0000-0000-0000-000000000002';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'FAIL 7 (BREACH): User A updated % User B quote row(s)', v_rows;
  end if;
  raise notice 'ok 7 - User A cannot update User B quote';

  -- 8. quotes: User A cannot delete User B quote
  delete from public.quotes
    where user_id = '00000000-0000-0000-0000-000000000002';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'FAIL 8 (BREACH): User A deleted % User B quote row(s)', v_rows;
  end if;
  raise notice 'ok 8 - User A cannot delete User B quote';

  -- 9. rate_memory: User A cannot see User B rates
  select count(*) into v_count from public.rate_memory
    where user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'FAIL 9 (BREACH): User A sees User B rate_memory';
  end if;
  raise notice 'ok 9 - User A cannot see User B rate_memory';

  -- 10. rate_memory: User A cannot insert rates for User B
  begin
    insert into public.rate_memory (user_id, catalog_item_id, trade, unit_rate_paise, unit)
      values ('00000000-0000-0000-0000-000000000002', 'paint-emulsion', 'painting', 9999, 'sq_ft');
    raise exception 'FAIL 10 (BREACH): User A inserted rate_memory for User B';
  exception when others then
    raise notice 'ok 10 - User A cannot insert rate_memory for User B';
  end;

  -- 11. line items: User A cannot see User B items
  select count(*) into v_count from public.quote_line_items
    where user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'FAIL 11 (BREACH): User A sees User B line items';
  end if;
  raise notice 'ok 11 - User A cannot see User B line items';

  -- 12. line items: User A cannot insert items for User B
  begin
    insert into public.quote_line_items
        (user_id, quote_id, description, quantity_x1000, unit, unit_rate_paise, amount_paise)
      values ('00000000-0000-0000-0000-000000000002',
              'bbbbbbbb-0000-0000-0000-000000000002',
              'Hijacked item', 1000, 'sq_ft', 100, 100);
    raise exception 'FAIL 12 (BREACH): User A inserted line items for User B';
  exception when others then
    raise notice 'ok 12 - User A cannot insert line items for User B';
  end;

  -- 13. feedback: User A cannot see User B feedback
  select count(*) into v_count from public.edit_feedback
    where user_id = '00000000-0000-0000-0000-000000000002';
  if v_count <> 0 then
    raise exception 'FAIL 13 (BREACH): User A sees User B edit_feedback';
  end if;
  raise notice 'ok 13 - User A cannot see User B edit_feedback';

  -- 14. feedback: User A cannot insert feedback for User B
  begin
    insert into public.edit_feedback (user_id, quote_id_hash, trade, changed_field)
      values ('00000000-0000-0000-0000-000000000002',
              encode(digest('evil-quote', 'sha256'), 'hex'), 'painting', 'rate');
    raise exception 'FAIL 14 (BREACH): User A inserted feedback for User B';
  exception when others then
    raise notice 'ok 14 - User A cannot insert feedback for User B';
  end;

  -- ── As User B (symmetric checks) ───────────────────────────
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
  perform set_config('role', 'authenticated', true);

  -- 15. User B cannot see User A profile
  select count(*) into v_count from public.profiles
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'FAIL 15 (BREACH): User B sees User A profile';
  end if;
  raise notice 'ok 15 - User B cannot see User A profile';

  -- 16. User B cannot see User A quotes
  select count(*) into v_count from public.quotes
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'FAIL 16 (BREACH): User B sees User A quotes';
  end if;
  raise notice 'ok 16 - User B cannot see User A quotes';

  -- 17. User B cannot see User A line items
  select count(*) into v_count from public.quote_line_items
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'FAIL 17 (BREACH): User B sees User A line items';
  end if;
  raise notice 'ok 17 - User B cannot see User A line_items';

  -- 18. User B cannot see User A rates
  select count(*) into v_count from public.rate_memory
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'FAIL 18 (BREACH): User B sees User A rate_memory';
  end if;
  raise notice 'ok 18 - User B cannot see User A rate_memory';

  -- 19. User B cannot see User A feedback
  select count(*) into v_count from public.edit_feedback
    where user_id = '00000000-0000-0000-0000-000000000001';
  if v_count <> 0 then
    raise exception 'FAIL 19 (BREACH): User B sees User A edit_feedback';
  end if;
  raise notice 'ok 19 - User B cannot see User A edit_feedback';

  raise notice 'ALL 19 RLS ISOLATION CHECKS PASSED';
end;
$$;

-- Restore superuser role, then remove rows seeded by this script.
-- (seed.sql rows for profiles/quotes are left untouched.)
reset role;
delete from public.rate_memory
  where user_id = '00000000-0000-0000-0000-000000000002'
    and catalog_item_id = 'paint-emulsion' and trade = 'painting';
delete from public.quote_line_items
  where user_id = '00000000-0000-0000-0000-000000000002'
    and description = 'Emulsion Paint';
delete from public.edit_feedback
  where user_id = '00000000-0000-0000-0000-000000000002'
    and trade = 'painting' and changed_field = 'quantity';

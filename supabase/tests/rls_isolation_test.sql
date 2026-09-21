-- rls_isolation_test.sql
-- pgTAP integration tests proving User A cannot access User B's data.
--
-- Run with: supabase test db
-- Requires pgTAP extension (enabled by default in local Supabase Docker).
--
-- Test user UUIDs match seed.sql:
--   User A: 00000000-0000-0000-0000-000000000001
--   User B: 00000000-0000-0000-0000-000000000002

begin;
select plan(24);  -- total number of test assertions

-- ─────────────────────────────────────────────
-- Helper: set the RLS role to a specific user
-- ─────────────────────────────────────────────
create or replace function test.set_user(uid uuid)
returns void language plpgsql as $$
begin
  -- Mimic what the Supabase PostgREST / Spring JDBC connection does:
  -- set the JWT sub claim so auth.uid() returns the right value.
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- ─────────────────────────────────────────────
-- 1. profiles isolation
-- ─────────────────────────────────────────────

-- User A can select their own profile
select test.set_user('00000000-0000-0000-0000-000000000001');
select is(
  (select count(*) from public.profiles where user_id = '00000000-0000-0000-0000-000000000001')::int,
  1,
  'User A: can select own profile'
);

-- User A cannot see User B's profile
select is(
  (select count(*) from public.profiles where user_id = '00000000-0000-0000-0000-000000000002')::int,
  0,
  'User A: cannot see User B profile'
);

-- User A cannot insert a profile for User B
select throws_ok(
  $$insert into public.profiles (id, user_id, business_name, trade)
    values ('00000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000002', 'Evil Corp', 'tiling')$$,
  'User A: cannot insert User B profile'
);

-- ─────────────────────────────────────────────
-- 2. quotes isolation
-- ─────────────────────────────────────────────

-- User A can see their own quotes
select is(
  (select count(*) from public.quotes where user_id = '00000000-0000-0000-0000-000000000001')::int,
  1,
  'User A: can select own quotes'
);

-- User A cannot see User B's quotes
select is(
  (select count(*) from public.quotes where user_id = '00000000-0000-0000-0000-000000000002')::int,
  0,
  'User A: cannot see User B quotes'
);

-- User A cannot insert a quote for User B
select throws_ok(
  $$insert into public.quotes (user_id, idempotency_key, trade, client_name)
    values ('00000000-0000-0000-0000-000000000002',
            'evil-key', 'tiling', 'Evil Client')$$,
  'User A: cannot insert quote for User B'
);

-- User A cannot update User B's quote
select throws_ok(
  $$update public.quotes set client_name = 'Hacked'
    where user_id = '00000000-0000-0000-0000-000000000002'$$,
  'User A: cannot update User B quote'
);

-- User A cannot delete User B's quote
select is(
  (delete from public.quotes where user_id = '00000000-0000-0000-0000-000000000002' returning id)::text,
  null,
  'User A: cannot delete User B quote'
);

-- ─────────────────────────────────────────────
-- 3. rate_memory isolation
-- ─────────────────────────────────────────────

-- Seed User B rate_memory (as superuser before test)
set role postgres;
insert into public.rate_memory (user_id, catalog_item_id, trade, unit_rate_paise, unit)
values ('00000000-0000-0000-0000-000000000002', 'paint-emulsion', 'painting', 8500, 'sq_ft')
on conflict do nothing;

select test.set_user('00000000-0000-0000-0000-000000000001');

select is(
  (select count(*) from public.rate_memory where user_id = '00000000-0000-0000-0000-000000000002')::int,
  0,
  'User A: cannot see User B rate_memory'
);

select throws_ok(
  $$insert into public.rate_memory (user_id, catalog_item_id, trade, unit_rate_paise, unit)
    values ('00000000-0000-0000-0000-000000000002', 'paint-emulsion', 'painting', 9999, 'sq_ft')$$,
  'User A: cannot insert rate_memory for User B'
);

-- ─────────────────────────────────────────────
-- 4. quote_line_items isolation
-- ─────────────────────────────────────────────

set role postgres;
insert into public.quote_line_items
  (user_id, quote_id, description, quantity_x1000, unit, unit_rate_paise, amount_paise)
values (
  '00000000-0000-0000-0000-000000000002',
  'bbbbbbbb-0000-0000-0000-000000000002',
  'Emulsion Paint', 1000, 'sq_ft', 8500, 8500000
)
on conflict do nothing;

select test.set_user('00000000-0000-0000-0000-000000000001');

select is(
  (select count(*) from public.quote_line_items where user_id = '00000000-0000-0000-0000-000000000002')::int,
  0,
  'User A: cannot see User B line items'
);

select throws_ok(
  $$insert into public.quote_line_items
      (user_id, quote_id, description, quantity_x1000, unit, unit_rate_paise, amount_paise)
    values ('00000000-0000-0000-0000-000000000002',
            'bbbbbbbb-0000-0000-0000-000000000002',
            'Hijacked item', 1000, 'sq_ft', 100, 100)$$,
  'User A: cannot insert line items for User B'
);

-- ─────────────────────────────────────────────
-- 5. edit_feedback isolation
-- ─────────────────────────────────────────────

set role postgres;
insert into public.edit_feedback
  (user_id, quote_id_hash, trade, changed_field)
values (
  '00000000-0000-0000-0000-000000000002',
  sha256('bbbbbbbb-0000-0000-0000-000000000002')::text,
  'painting', 'quantity'
)
on conflict do nothing;

select test.set_user('00000000-0000-0000-0000-000000000001');

select is(
  (select count(*) from public.edit_feedback where user_id = '00000000-0000-0000-0000-000000000002')::int,
  0,
  'User A: cannot see User B edit_feedback'
);

select throws_ok(
  $$insert into public.edit_feedback (user_id, quote_id_hash, trade, changed_field)
    values ('00000000-0000-0000-0000-000000000002',
            'fakehash', 'painting', 'rate')$$,
  'User A: cannot insert feedback for User B'
);

-- ─────────────────────────────────────────────
-- 6. Symmetric check: User B cannot see User A's data
-- ─────────────────────────────────────────────

select test.set_user('00000000-0000-0000-0000-000000000002');

select is(
  (select count(*) from public.profiles where user_id = '00000000-0000-0000-0000-000000000001')::int,
  0,
  'User B: cannot see User A profile'
);

select is(
  (select count(*) from public.quotes where user_id = '00000000-0000-0000-0000-000000000001')::int,
  0,
  'User B: cannot see User A quotes'
);

select is(
  (select count(*) from public.quote_line_items where user_id = '00000000-0000-0000-0000-000000000001')::int,
  0,
  'User B: cannot see User A line_items'
);

select is(
  (select count(*) from public.rate_memory where user_id = '00000000-0000-0000-0000-000000000001')::int,
  0,
  'User B: cannot see User A rate_memory'
);

select is(
  (select count(*) from public.edit_feedback where user_id = '00000000-0000-0000-0000-000000000001')::int,
  0,
  'User B: cannot see User A edit_feedback'
);

-- ─────────────────────────────────────────────
-- Done
-- ─────────────────────────────────────────────
select * from finish();
rollback;

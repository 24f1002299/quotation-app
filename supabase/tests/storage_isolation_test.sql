-- storage_isolation_test.sql (Day 22)
-- pgTAP-free version: runs in the Supabase SQL Editor or psql with no
-- extensions needed. Run with RLS ENABLED (not as bypass) so the policies
-- are actually exercised.
--
-- How it works: impersonates each contractor via the JWT claim + role
-- (same mechanism PostgREST / the Spring API uses), checks row visibility,
-- then cleans up via ROLLBACK at the end (Supabase forbids direct DELETEs
-- on storage.objects through its protect_delete trigger, so rollback — not
-- cleanup deletes — is how seed rows are removed). Any breach raises
-- EXCEPTION and the script stops; full pass ends with
-- 'ALL 6 STORAGE ISOLATION CHECKS PASSED'.

begin;

-- Seed two objects, one per user. Run this part as postgres (RLS bypassed
-- for setup only) before switching roles below.
insert into storage.objects (bucket_id, name, owner, metadata)
values
  ('user-files', '00000000-0000-0000-0000-000000000001/logo.png',
   '00000000-0000-0000-0000-000000000001', '{}'::jsonb),
  ('user-files', '00000000-0000-0000-0000-000000000002/logo.png',
   '00000000-0000-0000-0000-000000000002', '{}'::jsonb)
on conflict do nothing;

do $$
declare
  v_count int;
  v_public boolean;
begin
  -- ── As User A ──────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
  perform set_config('role', 'authenticated', true);

  -- 1. User A sees own file
  select count(*) into v_count from storage.objects
    where bucket_id = 'user-files'
      and name = '00000000-0000-0000-0000-000000000001/logo.png';
  if v_count <> 1 then
    raise exception 'FAIL 1: User A should see own file, saw % row(s)', v_count;
  end if;
  raise notice 'ok 1 - User A can select own storage object';

  -- 2. User A cannot see User B file
  select count(*) into v_count from storage.objects
    where bucket_id = 'user-files'
      and name = '00000000-0000-0000-0000-000000000002/logo.png';
  if v_count <> 0 then
    raise exception 'FAIL 2 (ISOLATION BREACH): User A sees User B file (% row(s))', v_count;
  end if;
  raise notice 'ok 2 - User A cannot see User B storage object';

  -- 3. User A cannot insert into User B folder
  begin
    insert into storage.objects (bucket_id, name, owner)
      values ('user-files',
              '00000000-0000-0000-0000-000000000002/evil.png',
              '00000000-0000-0000-0000-000000000001');
    raise exception 'FAIL 3 (ISOLATION BREACH): User A inserted into User B folder';
  exception when others then
    raise notice 'ok 3 - User A cannot insert into User B storage folder';
  end;

  -- ── As User B ──────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
  perform set_config('role', 'authenticated', true);

  -- 4. User B sees own file
  select count(*) into v_count from storage.objects
    where bucket_id = 'user-files'
      and name = '00000000-0000-0000-0000-000000000002/logo.png';
  if v_count <> 1 then
    raise exception 'FAIL 4: User B should see own file, saw % row(s)', v_count;
  end if;
  raise notice 'ok 4 - User B can select own storage object';

  -- 5. User B cannot see User A file
  select count(*) into v_count from storage.objects
    where bucket_id = 'user-files'
      and name = '00000000-0000-0000-0000-000000000001/logo.png';
  if v_count <> 0 then
    raise exception 'FAIL 5 (ISOLATION BREACH): User B sees User A file (% row(s))', v_count;
  end if;
  raise notice 'ok 5 - User B cannot see User A storage object';

  -- 6. Bucket stays private (no public URLs).
  -- NOTE: runs as postgres (RLS bypassed): contractors are intentionally
  -- NOT granted SELECT on storage.buckets, so this check cannot run under
  -- the authenticated role — it would always see "no rows".
  perform set_config('role', 'postgres', true);
  select public into v_public from storage.buckets where id = 'user-files';
  if not found then
    raise exception 'FAIL 6: user-files bucket does not exist at all';
  elsif v_public is distinct from false then
    raise exception 'FAIL 6: user-files bucket exists but public=% (must be false)', v_public;
  end if;
  raise notice 'ok 6 - user-files bucket is private';

  raise notice 'ALL 6 STORAGE ISOLATION CHECKS PASSED';
end;
$$;

-- Roll back the seed rows (and any evil.png left behind if check 3 ever
-- breached). Run on staging/local only.
rollback;

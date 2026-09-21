-- seed.sql — DEV ONLY
-- Creates two test users with predictable UUIDs for integration tests.
-- Run ONLY against the local Supabase Docker instance or the dev project.
-- NEVER run against staging or production.
--
-- These UUIDs are also used in rls_isolation_test.sql.

-- Test user A
insert into auth.users (
  id, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, aud, role
)
values (
  '00000000-0000-0000-0000-000000000001',
  'user-a@test.local',
  -- bcrypt of 'testpasswordA' — dev only, never a real password
  crypt('testpasswordA', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{}',
  'authenticated',
  'authenticated'
)
on conflict (id) do nothing;

-- Test user B
insert into auth.users (
  id, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, aud, role
)
values (
  '00000000-0000-0000-0000-000000000002',
  'user-b@test.local',
  crypt('testpasswordB', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{}',
  'authenticated',
  'authenticated'
)
on conflict (id) do nothing;

-- Seed profile for User A
insert into public.profiles (id, user_id, business_name, trade, city)
values (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'Asha Tiles', 'tiling', 'Pune'
)
on conflict (id) do nothing;

-- Seed profile for User B
insert into public.profiles (id, user_id, business_name, trade, city)
values (
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000002',
  'Sharma Painters', 'painting', 'Mumbai'
)
on conflict (id) do nothing;

-- Seed a quote for User A
insert into public.quotes (id, user_id, idempotency_key, trade, client_name, status)
values (
  'aaaaaaaa-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'seed-idem-key-a-001',
  'tiling',
  'Patil Residence',
  'draft'
)
on conflict (user_id, idempotency_key) do nothing;

-- Seed a quote for User B
insert into public.quotes (id, user_id, idempotency_key, trade, client_name, status)
values (
  'bbbbbbbb-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000002',
  'seed-idem-key-b-001',
  'painting',
  'Sharma Office',
  'draft'
)
on conflict (user_id, idempotency_key) do nothing;

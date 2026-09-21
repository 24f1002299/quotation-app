-- Migration: 003_app_role
-- Creates a least-privilege role for the Spring Boot API.
--
-- Why a separate role?
--   The Spring Boot service must NOT use the service-role (postgres) user.
--   It gets only SELECT/INSERT/UPDATE/DELETE on the five app tables.
--   It cannot create or drop tables, access auth.* directly, or bypass RLS
--   (because it connects as a row-level user, not as a superuser).
--
-- How Spring Boot authenticates as a specific user:
--   After verifying the Supabase JWT, Spring calls:
--     SET LOCAL role TO authenticated;
--     SET LOCAL request.jwt.claim.sub TO '<user_uuid>';
--   Supabase's RLS functions (auth.uid()) read from the GUC claim.
--   This means Spring's DB connection honours the same RLS policies
--   as a direct Supabase client call.

-- Create the role if it doesn't exist.
-- In Supabase managed Postgres you run this via the SQL editor as postgres/superuser.
do $$
begin
  if not exists (select from pg_roles where rolname = 'app_role') then
    create role app_role with login password 'REPLACE_WITH_STRONG_PASSWORD';
  end if;
end;
$$;

-- Grant connect on the database
grant connect on database postgres to app_role;

-- Grant usage on the public schema
grant usage on schema public to app_role;

-- Grant DML (no DDL) on user-owned tables only
grant select, insert, update, delete on
  public.profiles,
  public.rate_memory,
  public.quotes,
  public.quote_line_items,
  public.edit_feedback
to app_role;

-- Allow Spring to use the auth.uid() helper via the RLS path
-- Spring sets the JWT sub claim via SET LOCAL before querying,
-- so no direct auth schema access is needed.

-- Allow the role to use the updated_at trigger function
grant execute on function public.set_updated_at() to app_role;

-- Revoke dangerous defaults
revoke create on schema public from public;
revoke all on schema auth from app_role;

-- Sequence usage (for gen_random_uuid() — already works; just being explicit)
grant usage on all sequences in schema public to app_role;
alter default privileges in schema public
  grant usage on sequences to app_role;

-- Migration: 002_rls_policies
-- Enables Row Level Security on every exposed table.
-- All policies are scoped to auth.uid() only.
-- The service-role key bypasses RLS — it must never reach the Flutter app.

-- ─────────────────────────────────────────────
-- Enable RLS on all user-owned tables
-- ─────────────────────────────────────────────
alter table public.profiles        enable row level security;
alter table public.rate_memory     enable row level security;
alter table public.quotes          enable row level security;
alter table public.quote_line_items enable row level security;
alter table public.edit_feedback   enable row level security;

-- ─────────────────────────────────────────────
-- profiles policies
-- Each user can only see and modify their own profile.
-- ─────────────────────────────────────────────
create policy "profiles: owner can select"
  on public.profiles for select
  using (auth.uid() = user_id);

create policy "profiles: owner can insert"
  on public.profiles for insert
  with check (auth.uid() = user_id and auth.uid() = id);

create policy "profiles: owner can update"
  on public.profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "profiles: owner can delete"
  on public.profiles for delete
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- rate_memory policies
-- ─────────────────────────────────────────────
create policy "rate_memory: owner can select"
  on public.rate_memory for select
  using (auth.uid() = user_id);

create policy "rate_memory: owner can insert"
  on public.rate_memory for insert
  with check (auth.uid() = user_id);

create policy "rate_memory: owner can update"
  on public.rate_memory for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "rate_memory: owner can delete"
  on public.rate_memory for delete
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- quotes policies
-- ─────────────────────────────────────────────
create policy "quotes: owner can select"
  on public.quotes for select
  using (auth.uid() = user_id);

create policy "quotes: owner can insert"
  on public.quotes for insert
  with check (auth.uid() = user_id);

create policy "quotes: owner can update"
  on public.quotes for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "quotes: owner can delete"
  on public.quotes for delete
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- quote_line_items policies
-- user_id is duplicated on line items so RLS can filter
-- without a join to the parent quotes table.
-- ─────────────────────────────────────────────
create policy "line_items: owner can select"
  on public.quote_line_items for select
  using (auth.uid() = user_id);

create policy "line_items: owner can insert"
  on public.quote_line_items for insert
  with check (auth.uid() = user_id);

create policy "line_items: owner can update"
  on public.quote_line_items for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "line_items: owner can delete"
  on public.quote_line_items for delete
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- edit_feedback policies
-- Append-only from the user's own session.
-- No update or delete from the client — data lifecycle managed server-side.
-- ─────────────────────────────────────────────
create policy "edit_feedback: owner can select"
  on public.edit_feedback for select
  using (auth.uid() = user_id);

create policy "edit_feedback: owner can insert"
  on public.edit_feedback for insert
  with check (auth.uid() = user_id);

-- No UPDATE or DELETE policies on edit_feedback intentionally.
-- Deletion/anonymisation is handled by a server-side function when a quote is deleted.

-- ─────────────────────────────────────────────
-- Storage: create bucket 'user-files'
-- Bucket is private (not public). Signed URLs required.
-- ─────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-files',
  'user-files',
  false,                          -- private bucket; no public URL
  5242880,                        -- 5 MB max per file (logos, PDFs)
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do nothing;

-- ─────────────────────────────────────────────
-- Storage RLS policies
-- All object paths must be: {user_id}/...
-- This prevents User A from reading User B's logos or PDFs.
-- ─────────────────────────────────────────────

-- SELECT: users can only read their own files
create policy "storage: owner can select"
  on storage.objects for select
  using (
    bucket_id = 'user-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- INSERT: users can only upload into their own folder
create policy "storage: owner can insert"
  on storage.objects for insert
  with check (
    bucket_id = 'user-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- UPDATE: users can only update their own files
create policy "storage: owner can update"
  on storage.objects for update
  using (
    bucket_id = 'user-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- DELETE: users can only delete their own files
create policy "storage: owner can delete"
  on storage.objects for delete
  using (
    bucket_id = 'user-files'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

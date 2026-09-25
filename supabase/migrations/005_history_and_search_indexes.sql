-- Migration: 005_history_and_search_indexes
-- Performance indexes for Day 16: user-scoped history and search queries.
-- Indexes support date search, status + created_at history pagination,
-- and client name search with date ordering.

-- quotes: filter by commercial quote_date
create index if not exists idx_quotes_user_id_quote_date
  on public.quotes (user_id, quote_date desc);

-- quotes: compound index for status-filtered chronological history
create index if not exists idx_quotes_user_id_status_created_at
  on public.quotes (user_id, status, created_at desc);

-- quotes: compound index for client search combined with chronological ordering
create index if not exists idx_quotes_user_id_client_date
  on public.quotes (user_id, client_name text_pattern_ops, quote_date desc);

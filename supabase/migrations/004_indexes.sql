-- Migration: 004_indexes
-- Performance indexes for all user-scoped queries.
-- Every table already has user_id; these indexes make history and search fast.

-- profiles — look up by user_id (unique, but explicit index helps query planner)
create index if not exists idx_profiles_user_id
  on public.profiles (user_id);

-- rate_memory — contractor's full rate card
create index if not exists idx_rate_memory_user_id
  on public.rate_memory (user_id);

-- rate_memory — look up a specific item rate quickly
create index if not exists idx_rate_memory_user_trade_item
  on public.rate_memory (user_id, trade, catalog_item_id);

-- quotes — paginated history list (most recent first)
create index if not exists idx_quotes_user_id_created_at
  on public.quotes (user_id, created_at desc);

-- quotes — filter by status (Draft / Ready / Shared)
create index if not exists idx_quotes_user_id_status
  on public.quotes (user_id, status);

-- quotes — server-side search by client name
create index if not exists idx_quotes_user_id_client_name
  on public.quotes (user_id, client_name text_pattern_ops);

-- quote_line_items — fetch all items for one quote
create index if not exists idx_line_items_quote_id
  on public.quote_line_items (quote_id);

-- quote_line_items — user_id for RLS scans
create index if not exists idx_line_items_user_id
  on public.quote_line_items (user_id);

-- edit_feedback — retrieve all feedback for a user (for deletion)
create index if not exists idx_edit_feedback_user_id
  on public.edit_feedback (user_id);

-- edit_feedback — look up by hashed quote id for deletion/anonymisation
create index if not exists idx_edit_feedback_quote_id_hash
  on public.edit_feedback (quote_id_hash);

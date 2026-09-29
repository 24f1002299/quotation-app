# Backup & Restore Runbook — Contractor Quote App (pilot)

## 1. What backs up what

- **Supabase Postgres (profiles, rates, quotes, line items, feedback):**
  automatic backups + point-in-time recovery (PITR) per the project plan.
  Confirm the plan tier supports PITR before the pilot; the free tier has
  limited retention — record the tier and window below.
- **Supabase Storage (`user-files/` logos, opt-in PDFs):** replicated with
  the project; versioning is NOT assumed — treat the DB as the index.
- **On-device data:** NOT backed up by us. The sync outbox replays to the
  server when online; a lost phone without sync loses unsynced drafts.

Current pilot setting (fill in at deploy):
- Supabase project ref: ______
- Plan / PITR window: ______
- Backup check date: ______

## 2. Restore drill (tabletop, required before pilot)

1. Note a deletion request timestamp T (e.g. test user deleted quote Q).
2. Restore to a staging project to time T+1h (do NOT restore prod in place).
3. Verify: restored staging contains data as of T+1h.
4. Re-apply every deletion request with timestamp ≤ restore point
   (quotes, Storage prefixes, feedback hashes) on staging; confirm counts.
5. Record results, then destroy the staging project.
6. Only after a clean drill: schedule the same steps for a real incident,
   with contractor notice before any prod restore.

## 3. Migration rollback

- Every schema change ships as a versioned file in `supabase/migrations/`.
- Rollback = apply the inverse migration (new file, never edit history)
  to staging first, verified by `bash supabase/tests/migration_apply_test.sh`.
- `006_feedback_lifecycle.sql` rollback: `drop function
  delete_feedback_for_quote(text), anonymize_feedback_for_quote(text);`

## 4. Incident contacts

- API on-call: ______
- Supabase org admin: ______
- Status page + support email shown in-app: ______

## 5. Deletion-request coverage on restore

Deletion requests cover Storage AND database records: quote rows, line
items, `edit_feedback` hashes, Storage prefixes (`<userId>/…`), and
diagnostic copies. The restore drill step 4 is the proof.

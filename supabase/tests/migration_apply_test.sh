#!/usr/bin/env bash
# migration_apply_test.sh
#
# Verifies that all migrations apply cleanly to a fresh empty database.
# Run in CI or locally after `supabase start`.
#
# Usage:
#   bash supabase/tests/migration_apply_test.sh
#
# Requirements:
#   - Supabase CLI installed (https://supabase.com/docs/guides/cli)
#   - Local Docker running (`supabase start`)
#
# Exit codes:
#   0 — all migrations applied cleanly
#   1 — one or more migrations failed

set -euo pipefail

MIGRATIONS_DIR="$(dirname "$0")/../migrations"
DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:54322/postgres}"

echo "========================================"
echo " Migration clean-apply test"
echo " DB: $DB_URL"
echo "========================================"

# Reset the database to a clean state (drops and recreates public schema).
# Only safe against local dev/test databases.
if [[ "$DB_URL" == *"localhost"* ]] || [[ "$DB_URL" == *"127.0.0.1"* ]]; then
  echo "→ Resetting public schema on local DB..."
  psql "$DB_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>&1
else
  echo "ERROR: DB_URL does not look local. Refusing to reset a remote database."
  echo "       Set DATABASE_URL to a local Supabase Docker instance."
  exit 1
fi

# Apply migrations in order
FAILED=0
for migration in "$MIGRATIONS_DIR"/[0-9]*.sql; do
  filename=$(basename "$migration")
  echo "→ Applying $filename..."
  if psql "$DB_URL" -f "$migration" 2>&1; then
    echo "  ✓ $filename applied OK"
  else
    echo "  ✗ $filename FAILED"
    FAILED=$((FAILED + 1))
  fi
done

echo "========================================"
if [[ "$FAILED" -eq 0 ]]; then
  echo " All migrations applied cleanly. ✓"
  exit 0
else
  echo " $FAILED migration(s) failed. ✗"
  exit 1
fi

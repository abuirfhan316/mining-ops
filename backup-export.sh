#!/usr/bin/env bash
#
# backup-export.sh
# Dumps Supabase tables to timestamped CSV files via the REST API.
# Requires: curl
#
# Env vars required (set as GitHub Actions secrets, or export locally before running):
#   SUPABASE_URL            e.g. https://xxxxxxxx.supabase.co
#   SUPABASE_SERVICE_KEY    your project's service_role secret key
#                           (NOT the anon key -- RLS-protected tables like
#                           import_errors need this to bypass RLS)
#
# SECURITY WARNING: the service_role key bypasses Row Level Security entirely.
# - Store it ONLY as a GitHub Actions secret (or local env var), never in code.
# - Restrict who can view/edit this repo's Actions secrets.
# - Make sure OUT_DIR (the backups/ folder) is git-ignored and stored somewhere
#   access-controlled, not committed to a public or loosely-permissioned repo.
#
# Edit TABLES below to match your schema.
set -euo pipefail
TABLES=("inventory" "audit_log" "import_errors")   # <-- edit to match your table names
OUT_DIR="backups/$(date -u +%Y-%m-%d)"
DATE_STR=$(date -u +%Y-%m-%d)

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY must be set." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

for TABLE in "${TABLES[@]}"; do
  echo "Exporting table: $TABLE"
  OUT_FILE="$OUT_DIR/${TABLE}_${DATE_STR}.csv"

  # select=* pulls all columns/rows, order=id.asc for stable ordering.
  # Accept: text/csv tells PostgREST to return CSV instead of JSON.
  HTTP_STATUS=$(curl -sS \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Accept: text/csv" \
    -w "%{http_code}" \
    "${SUPABASE_URL}/rest/v1/${TABLE}?select=*&order=id.asc" \
    -o "$OUT_FILE")

  # Validate: correct HTTP status + file isn't empty + doesn't look like an HTML/JSON error page
  if [[ "$HTTP_STATUS" -ge 400 ]]; then
    echo "ERROR: HTTP $HTTP_STATUS for table $TABLE. Check table name / RLS policy." >&2
    cat "$OUT_FILE" >&2
    exit 1
  fi

  if [[ ! -s "$OUT_FILE" ]]; then
    echo "ERROR: response for $TABLE was empty." >&2
    exit 1
  fi

  if head -c 20 "$OUT_FILE" | grep -qE '^\s*(<|{)'; then
    echo "ERROR: response for $TABLE doesn't look like CSV (looks like HTML/JSON). Check table name / RLS policy." >&2
    cat "$OUT_FILE" >&2
    exit 1
  fi

  ROW_COUNT=$(($(wc -l < "$OUT_FILE") - 1))  # subtract 1 for header row
  echo "  -> $ROW_COUNT rows saved to $OUT_FILE"
done

echo "Backup complete: $OUT_DIR"

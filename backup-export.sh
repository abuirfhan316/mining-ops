#!/usr/bin/env bash
#
# backup-export.sh
# Dumps Supabase tables to timestamped JSON files via the REST API.
# Requires: curl, jq
#
# Env vars required (set as GitHub Actions secrets, or export locally before running):
#   SUPABASE_URL        e.g. https://xxxxxxxx.supabase.co
#   SUPABASE_ANON_KEY    your project's anon/public key (read-only is fine)
#
# Edit TABLES below to match your schema.

set -euo pipefail

TABLES=("inventory" "audit_log")   # <-- edit to match your table names
OUT_DIR="backups/$(date -u +%Y-%m-%d)"
DATE_STR=$(date -u +%Y-%m-%d)

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

for TABLE in "${TABLES[@]}"; do
  echo "Exporting table: $TABLE"
  OUT_FILE="$OUT_DIR/${TABLE}_${DATE_STR}.json"

  # select=* pulls all columns/rows. Add ?order=id.asc for stable ordering.
  curl -sS \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Accept: application/json" \
    "${SUPABASE_URL}/rest/v1/${TABLE}?select=*&order=id.asc" \
    -o "$OUT_FILE"

  # Validate it's real JSON, not an HTML error page
  if ! jq empty "$OUT_FILE" 2>/dev/null; then
    echo "ERROR: response for $TABLE was not valid JSON. Check table name / RLS policy." >&2
    cat "$OUT_FILE" >&2
    exit 1
  fi

  ROW_COUNT=$(jq 'length' "$OUT_FILE")
  echo "  -> $ROW_COUNT rows saved to $OUT_FILE"
done

echo "Backup complete: $OUT_DIR"

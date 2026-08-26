#!/usr/bin/env bash
#
# backup-export.sh
# Dumps Supabase tables to timestamped CSV files via the REST API.
# Paginates using HTTP Range headers so tables with more than 1000 rows
# (Supabase/PostgREST's default page size) are fully exported.
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
PAGE_SIZE=1000   # matches PostgREST's default max rows per request

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_SERVICE_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY must be set." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

for TABLE in "${TABLES[@]}"; do
  echo "Exporting table: $TABLE"
  OUT_FILE="$OUT_DIR/${TABLE}_${DATE_STR}.csv"
  TMP_FILE=$(mktemp)
  : > "$OUT_FILE"   # truncate/create the final output file

  OFFSET=0
  PAGE_NUM=1
  TOTAL_ROWS=0

  while true; do
    RANGE_START="$OFFSET"
    RANGE_END=$((OFFSET + PAGE_SIZE - 1))

    # select=* pulls all columns, order=id.asc keeps pagination stable
    # (without a stable order, rows can shift between pages and get
    # skipped or duplicated). Range/Range-Unit headers page through results.
    # Accept: text/csv tells PostgREST to return CSV instead of JSON.
    HTTP_STATUS=$(curl -sS \
      -H "apikey: ${SUPABASE_SERVICE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
      -H "Accept: text/csv" \
      -H "Range-Unit: items" \
      -H "Range: ${RANGE_START}-${RANGE_END}" \
      -w "%{http_code}" \
      "${SUPABASE_URL}/rest/v1/${TABLE}?select=*&order=id.asc" \
      -o "$TMP_FILE")

    # 200 = full/last page returned as a complete set, 206 = partial page (more may follow)
    if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "206" ]]; then
      echo "ERROR: HTTP $HTTP_STATUS for table $TABLE (page $PAGE_NUM). Check table name / RLS policy." >&2
      cat "$TMP_FILE" >&2
      rm -f "$TMP_FILE"
      exit 1
    fi

    if [[ ! -s "$TMP_FILE" ]]; then
      echo "ERROR: response for $TABLE (page $PAGE_NUM) was empty." >&2
      rm -f "$TMP_FILE"
      exit 1
    fi

    if head -c 20 "$TMP_FILE" | grep -qE '^\s*(<|{)'; then
      echo "ERROR: response for $TABLE (page $PAGE_NUM) doesn't look like CSV (looks like HTML/JSON). Check table name / RLS policy." >&2
      cat "$TMP_FILE" >&2
      rm -f "$TMP_FILE"
      exit 1
    fi

    PAGE_ROWS=$(($(wc -l < "$TMP_FILE") - 1))   # subtract header row
    if [[ "$PAGE_ROWS" -lt 0 ]]; then
      PAGE_ROWS=0
    fi

    if [[ "$PAGE_NUM" -eq 1 ]]; then
      # first page: keep the header row
      cat "$TMP_FILE" >> "$OUT_FILE"
    else
      # later pages: drop the repeated header row before appending
      tail -n +2 "$TMP_FILE" >> "$OUT_FILE"
    fi

    TOTAL_ROWS=$((TOTAL_ROWS + PAGE_ROWS))
    echo "  page $PAGE_NUM: $PAGE_ROWS rows (offset $RANGE_START)"

    # Stop once a page comes back with fewer rows than PAGE_SIZE -- that means
    # we've reached the end of the table.
    if [[ "$PAGE_ROWS" -lt "$PAGE_SIZE" ]]; then
      break
    fi

    OFFSET=$((OFFSET + PAGE_SIZE))
    PAGE_NUM=$((PAGE_NUM + 1))
  done

  rm -f "$TMP_FILE"
  echo "  -> $TOTAL_ROWS total rows saved to $OUT_FILE"
done

echo "Backup complete: $OUT_DIR"

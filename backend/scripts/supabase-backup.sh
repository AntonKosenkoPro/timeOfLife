#!/bin/sh
# Weekly pg_dump of the hosted relay database (Supabase Free has no automated
# backups — migrate-db-to-supabase-free, backup floor).
#
# Usage (VM cron): 0 3 * * 0 /opt/timeoflife/scripts/supabase-backup.sh /var/backups/supabase
# Reads DATABASE_URL from the environment (VM: `set -a; . /opt/timeoflife/.env`).
# Writes a timestamped, checksummed dump; prunes artifacts older than $RETENTION_DAYS (default 30).
# Tool override for hosts without postgres clients (VM cron):
#   PGDUMP_BIN="docker run --rm postgres:15-alpine pg_dump"
# The tool must write the dump to STDOUT (the script redirects to $DUMP) so no
# volume mounts are needed in the docker form.
# Never prints connection strings or secrets: no `set -x`, errors are redacted to host/port only.
set -eu

: "${PGDUMP_BIN:=pg_dump}"

OUT_DIR="${1:?usage: $0 <output-dir>}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
: "${DATABASE_URL:?DATABASE_URL must be set (sourced from the deployment .env)}"

mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
DUMP="$OUT_DIR/supabase-$TS.sql"
SHA="$DUMP.sha256"

# --no-owner/--no-privileges: roles differ between Supabase and any restore target.
$PGDUMP_BIN "$DATABASE_URL" --no-owner --no-privileges > "$DUMP"
sha256sum "$DUMP" | awk '{print $1}' > "$SHA"
chmod 600 "$DUMP" "$SHA"

# Prune artifacts older than the retention window (mtime-based).
find "$OUT_DIR" -maxdepth 1 -name 'supabase-*.sql' -mtime +"$RETENTION_DAYS" -delete
find "$OUT_DIR" -maxdepth 1 -name 'supabase-*.sql.sha256' -mtime +"$RETENTION_DAYS" -delete

echo "backup complete: $(basename "$DUMP") ($(wc -c < "$DUMP") bytes, sha256 recorded)"

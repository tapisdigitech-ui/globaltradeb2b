#!/bin/bash
# LOCAL validation of supabase/migrations with the real Supabase CLI against a throw-away local Postgres (NOT hosted).
# Usage: SUPABASE_BIN=/path/to/supabase bash packaging/run_cli_chain.sh   (default: `supabase` on PATH)
# Only ever points --db-url at localhost:${PGPORT:-5544}. Refuses anything else.
set -e; cd "$(dirname "$0")/.."
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres
SB=${SUPABASE_BIN:-supabase}; D=cli_t; URL="postgresql://postgres@localhost:$PGPORT/$D?sslmode=disable"
case "$URL" in postgresql://postgres@localhost:*) ;; *) echo "refusing non-local URL"; exit 2;; esac
bash packaging/sync_cli_migrations.sh --check >/dev/null || { echo "migrations/ out of sync with migrations_draft/"; exit 1; }
psql -q -d postgres -c "drop database if exists $D" -c "create database $D" 2>/dev/null
psql -q -d $D -v ON_ERROR_STOP=1 -f baseline/local_platform.sql >/dev/null 2>&1      # stands in for the platform's own auth/storage/roles/extensions
echo "--- dry run";   $SB db push --db-url "$URL" --dry-run 2>&1 | grep -E "^ •|DRY|Would" 
echo "--- push";      $SB db push --db-url "$URL" --include-seed 2>&1 | grep -E "Applying|Seeding|ERROR|error"
echo "--- push again (must be up to date)"; $SB db push --db-url "$URL" 2>&1 | grep -E "up to date|Applying" 
echo "--- recorded history"; psql -d $D -Atc "select version||' '||name from supabase_migrations.schema_migrations order by 1"
n=$(psql -d $D -Atc "select count(*) from supabase_migrations.schema_migrations"); [ "$n" = 9 ] || { echo "FAIL expected 9 applied, got $n"; exit 1; }
echo "--- seed re-run is idempotent"; psql -q -d $D -v ON_ERROR_STOP=1 -f seed.sql >/dev/null && echo "categories=$(psql -d $D -Atc 'select count(*) from categories')"
echo "--- catalogue fingerprint: CLI-applied chain vs direct psql chain of migrations_draft"
P=cli_ref; bash baseline/load_baseline.sh $P >/dev/null 2>&1
for f in migrations_draft/000[1-8]_*.sql; do psql -q -d $P -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "ref chain failed $f"; exit 1; }; done
bash baseline/compare/local_fingerprint.sh $D > /tmp/fp_a.txt; bash baseline/compare/local_fingerprint.sh $P > /tmp/fp_b.txt
diff /tmp/fp_a.txt /tmp/fp_b.txt && echo "IDENTICAL (13 kinds)" || { echo "FINGERPRINT MISMATCH"; exit 1; }
echo "CLI CHAIN OK"

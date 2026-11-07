#!/bin/bash
# Before/after schema comparison and rollback proof on a disposable DB. Usage: tests/compare_and_rollback.sh (from supabase/)
cd "$(dirname "$0")/.." ; export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres
O=reports; DUMP="pg_dump --schema-only -n public -n storage -d t3"; clean(){ grep -v "^.\\(un\)\?restrict " ; }
tests/reset_db.sh t3 >/dev/null 2>&1 || exit 1
$DUMP | grep -v "^\\\\\(un\)\?restrict " > $O/schema_0_before.sql
for f in migrations_draft/000[1-5]_*.sql; do psql -q -d t3 -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "UP FAILED $f"; exit 1; }; done
$DUMP | grep -v "^\\\\\(un\)\?restrict " > $O/schema_1_after.sql
diff $O/schema_0_before.sql $O/schema_1_after.sql > $O/schema_diff_before_after.diff
echo "after-vs-before: $(grep -c '^>' $O/schema_diff_before_after.diff) lines added, $(grep -c '^<' $O/schema_diff_before_after.diff) lines removed/changed"
for f in 5 4 3 2 1; do psql -q -d t3 -v ON_ERROR_STOP=1 -f migrations_draft/down/000${f}_down.sql >/dev/null 2>&1 || { echo "DOWN FAILED $f"; exit 1; }; done
$DUMP | grep -v "^\\\\\(un\)\?restrict " > $O/schema_2_rolled_back.sql
if diff -q $O/schema_0_before.sql $O/schema_2_rolled_back.sql >/dev/null; then echo "ROLLBACK RESULT: schema identical to baseline (diff empty)"; else echo "ROLLBACK RESULT: DIFFERENCES"; diff $O/schema_0_before.sql $O/schema_2_rolled_back.sql | head -40; fi

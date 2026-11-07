#!/bin/bash
# Usage: tests/run_all.sh  (from supabase/). Fresh DB from reconstructed baseline -> migrations 0001..0004 -> full test suite.
cd "$(dirname "$0")/.." ; export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres
tests/reset_db.sh t2 >/dev/null 2>&1 || { echo "baseline failed"; exit 1; }
for f in migrations_draft/000[1-5]_*.sql; do psql -q -d t2 -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED: $f"; exit 1; }; done
psql -q -d t2 -f tests/0002_full_test.sql 2>&1 | grep -E "PASS|FAIL|ERROR" | sed 's/psql:tests[^ ]* NOTICE:  //'

#!/bin/bash
# Usage: run_seed.sh — LOCAL: seed tests on (a) fresh baseline+0001-0008 and (b) the supabase/migrations chain via db reset semantics is covered by run_cli_chain.sh.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
D=seed_t; bash baseline/load_baseline.sh $D >/dev/null || exit 1
for f in migrations_draft/000[1-8]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
psql -q -d $D -f tests/seed_tests.sql 2>&1 | grep -E "PASS|FAIL|ERROR|incomplete" | sed 's/^psql:[^ ]* //'

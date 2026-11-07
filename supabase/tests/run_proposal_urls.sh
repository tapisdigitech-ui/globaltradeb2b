#!/bin/bash
# Usage: run_proposal_urls.sh control|proposal — LOCAL PG16 only; never part of the standard suites.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
M=$1; D=url_$M; bash baseline/load_baseline.sh $D >/dev/null || exit 1
for f in migrations_draft/000[1-7]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
P=0; [ "$M" = proposal ] && P=1
psql -q -d $D -v prop=$P -f tests/proposals/url_validation_tests.sql 2>&1 | grep -E "NOTICE|ERROR|COMPLETED|FAIL"

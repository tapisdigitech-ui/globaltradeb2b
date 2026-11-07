#!/bin/bash
# Usage: run_real.sh pre|post6|post   — rebuilds a LOCAL replica from the staging schema extract (NOT staging) and runs the real-schema suite.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
P=$1; D=real_$P; bash ${LOADER:-baseline/load_baseline.sh} $D >/dev/null || exit 1
for f in migrations_draft/000[1-5]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
POST=0; V7=0
if [ "$P" = post ] || [ "$P" = post6 ]; then psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0006_real_schema_hardening.sql >/dev/null 2>&1 || { echo "0006 FAILED"; exit 1; }; POST=1; fi
if [ "$P" = post ]; then psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0007_function_hardening.sql 2>&1 | grep -E "ERROR" && { echo "0007 FAILED"; exit 1; }; V7=1
  psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0008_sequence_privileges.sql >/dev/null 2>&1 || { echo "0008 FAILED"; exit 1; }; fi
[ -n "$MUTATE_SQL" ] && psql -q -d $D -v ON_ERROR_STOP=1 -c "$MUTATE_SQL" >/dev/null   # mutation-control hook (Round 9.1), unused in normal runs
psql -q -d $D -v phase=$P -v post=$POST -v v7=$V7 -f tests/real_schema_tests.sql 2>&1 | grep -E "NOTICE|ERROR|COMPLETED|DETAIL|FAIL"

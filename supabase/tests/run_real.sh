#!/bin/bash
# Usage: run_real.sh pre|post   — rebuilds a LOCAL replica from the staging schema extract (NOT staging) and runs the real-schema suite.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
P=$1; D=real_$P; bash staging_schema/load_real.sh $D >/dev/null || exit 1
for f in migrations_draft/000[1-5]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
POST=0; if [ "$P" = post ]; then psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0006_real_schema_hardening.sql >/dev/null 2>&1 || { echo "0006 FAILED"; exit 1; }; POST=1; fi
psql -q -d $D -v phase=$P -v post=$POST -f tests/real_schema_tests.sql 2>&1 | grep -vE "^$|set_config|^-+$|^ pre|^ post|row\)"

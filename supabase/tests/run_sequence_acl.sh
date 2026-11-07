#!/bin/bash
# Usage: run_sequence_acl.sh [default|classic] — LOCAL. classic = Supabase-classic default ACLs (ALL on sequences to anon/authenticated/service_role) simulated.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
M=${1:-default}; L=baseline/load_baseline.sh; [ "$M" = classic ] && L=baseline/load_baseline_classic.sh
D=seqacl_$M; bash $L $D >/dev/null || exit 1
for f in migrations_draft/000[1-7]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
[ "$2" = pre0008 ] || psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0008_sequence_privileges.sql >/dev/null 2>&1 || { echo "0008 FAILED"; exit 1; }
psql -q -d $D -f tests/sequence_acl_tests.sql 2>&1 | grep -E "PASS|FAIL|ERROR" | sed 's/^psql:[^ ]* //'

#!/bin/bash
# Usage: run_proposal_admin_audit.sh control|proposal|rollback — LOCAL PG16 only. The proposal is NEVER part of run_real.sh / the standard suites.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
M=$1; D=prop_$M; bash baseline/load_baseline.sh $D >/dev/null || exit 1
for f in migrations_draft/000[1-7]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
PROP=0
case $M in
 proposal) psql -q -d $D -v ON_ERROR_STOP=1 -f proposals/0008_admin_message_audit_PROPOSAL.sql >/dev/null 2>&1 || { echo "PROPOSAL FAILED"; exit 1; }; PROP=1;;
 rollback) pg_dump -s -d $D --no-owner | grep -v -e '\\restrict' -e '\\unrestrict' > /tmp/prop_before.sql
   psql -q -d $D -v ON_ERROR_STOP=1 -f proposals/0008_admin_message_audit_PROPOSAL.sql >/dev/null 2>&1 || { echo "PROPOSAL FAILED"; exit 1; }
   psql -q -d $D -v ON_ERROR_STOP=1 -f proposals/0008_admin_message_audit_DOWN.sql >/dev/null 2>&1 || { echo "DOWN FAILED"; exit 1; }
   pg_dump -s -d $D --no-owner | grep -v -e '\\restrict' -e '\\unrestrict' > /tmp/prop_after.sql
   echo "proposal rollback: schema diff vs before = $(diff /tmp/prop_before.sql /tmp/prop_after.sql | wc -l) lines"; exit 0;;
esac
psql -q -d $D -v prop=$PROP -f tests/proposals/admin_message_audit_tests.sql 2>&1 | grep -E "NOTICE|ERROR|COMPLETED|FAIL"

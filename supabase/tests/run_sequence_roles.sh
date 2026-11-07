#!/bin/bash
# Usage: run_sequence_roles.sh [default|classic] — LOCAL. Fresh DB: baseline+0001-0008(+0009 if present)+fixtures; genuine non-owner roles with JWT claims.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
M=${1:-default}; L=baseline/load_baseline.sh; [ "$M" = classic ] && L=baseline/load_baseline_classic.sh
D=seqrole_$M; bash $L $D >/dev/null || exit 1
for f in migrations_draft/000[1-9]_*.sql; do [ -f "$f" ] || continue; psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
psql -q -d $D -v ON_ERROR_STOP=1 -f tests/jwt/fixtures.sql >/dev/null && psql -q -d $D -v ON_ERROR_STOP=1 -f tests/jwt/fixtures_evidence.sql >/dev/null && psql -q -d $D -v ON_ERROR_STOP=1 -f tests/jwt/fixtures_sequences.sql >/dev/null 2>&1 || { echo FIXTURES FAILED; exit 1; }
python3 tests/jwt/test_sequence_roles.py $D

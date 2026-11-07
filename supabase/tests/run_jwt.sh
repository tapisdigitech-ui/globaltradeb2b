#!/bin/bash
# Usage: run_jwt.sh  — fresh LOCAL DB (baseline+0001-0008+synthetic fixtures), then the PostgREST-emulated JWT claim tests. Not Supabase.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
D=jwt_t; bash baseline/load_baseline.sh $D >/dev/null || exit 1
for f in migrations_draft/000[1-8]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "MIGRATION FAILED $f"; exit 1; }; done
psql -q -d $D -v ON_ERROR_STOP=1 -f tests/jwt/fixtures.sql >/dev/null || exit 1
psql -q -d $D -v ON_ERROR_STOP=1 -f tests/jwt/fixtures_evidence.sql >/dev/null || { echo EVIDENCE FIXTURES FAILED; exit 1; }
python3 tests/jwt/test_jwt_claims.py $D | grep -v '^PASS' ; python3 tests/jwt/test_evidence_link_db.py $D | grep -v '^PASS'

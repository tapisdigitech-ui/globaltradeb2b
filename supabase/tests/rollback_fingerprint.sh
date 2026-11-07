#!/bin/bash
# Rollback / re-apply check that needs NO pg_dump (works when the client tools are older than the server, e.g. PG16 client vs PG17 server).
# Uses the 13-kind catalogue fingerprint. LOCAL only. Reports exactly what differs; 0008's known NULL->explicit identity-sequence ACL difference is reported, not hidden.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
case "$PGHOST" in /tmp/*) ;; *) echo "REFUSING"; exit 2;; esac
echo "server $(psql -d postgres -Atc 'show server_version')"
D=rbfp; bash baseline/load_baseline.sh $D >/dev/null || exit 1; bash baseline/load_baseline.sh ${D}_base >/dev/null
ap(){ psql -q -d $D -v ON_ERROR_STOP=1 -f $1 >/dev/null 2>/tmp/rbfp_err || { echo "FAILED $1"; head -3 /tmp/rbfp_err; exit 1; }; }
fp(){ for k in enum column table_flags constraint index trigger policy function_body function_acl relation_acl view_def sequence bucket; do echo "$k $(bash baseline/compare/local_fingerprint.sh $1 $k)"; done; }
fp ${D}_base > /tmp/rbfp_base.fp
for f in migrations_draft/000[1-7]_*.sql; do ap $f; done; fp $D > /tmp/rbfp_pre8.fp
ap migrations_draft/0008_sequence_privileges.sql; fp $D > /tmp/rbfp_post8.fp
echo "0008 changes the sequence/relation_acl items: $(diff /tmp/rbfp_pre8.fp /tmp/rbfp_post8.fp | grep -c '^>') fingerprint lines differ"
ap migrations_draft/down/0008_down.sql; fp $D > /tmp/rbfp_rb8.fp
echo "fingerprint diff after rolling back 0008 vs pre-0008: $(diff /tmp/rbfp_pre8.fp /tmp/rbfp_rb8.fp | grep -c '^>') items (expected: the identity-sequence ACL items only - identity sequences NULL -> explicit owner-only ACL)"; diff /tmp/rbfp_pre8.fp /tmp/rbfp_rb8.fp | grep '^>' | cut -d' ' -f2 | tr '\n' ' '; echo
ap migrations_draft/0008_sequence_privileges.sql; fp $D > /tmp/rbfp_re8.fp
echo "fingerprint diff re-applied 0008 vs first apply: $(diff /tmp/rbfp_post8.fp /tmp/rbfp_re8.fp | wc -l) lines"
ap migrations_draft/down/0008_down.sql; ap migrations_draft/down/0007_down.sql; fp $D > /tmp/rbfp_rb7.fp
psql -qc "drop database $D" -c "create database $D" >/dev/null; bash baseline/load_baseline.sh $D >/dev/null; for f in migrations_draft/000[1-6]_*.sql; do ap $f; done; fp $D > /tmp/rbfp_pre7.fp
echo "fingerprint diff after rolling back 0008+0007 vs a fresh 0001-0006 build: $(diff /tmp/rbfp_pre7.fp /tmp/rbfp_rb7.fp | grep -c '^>') items"
ap migrations_draft/down/0006_down.sql; for n in 5 4 3 2 1; do ap migrations_draft/down/000${n}_down.sql; done
fp $D > /tmp/rbfp_alldown.fp
echo "fingerprint diff after rolling back ALL (0001..0008 path) vs untouched baseline: $(diff /tmp/rbfp_base.fp /tmp/rbfp_alldown.fp | grep -c '^>') items: $(diff /tmp/rbfp_base.fp /tmp/rbfp_alldown.fp | grep '^>' | cut -d' ' -f2 | tr '\n' ' ')"
psql -qc "drop database $D" -c "drop database ${D}_base" >/dev/null

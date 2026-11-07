#!/bin/bash
# LOCAL rehearsal of the backup -> encrypt -> decrypt -> restore -> verify cycle with SYNTHETIC data only.
# Source: local PG16 (pg_dump 16 can only dump a server <= 16). Target: local PG17.11. Proves the procedure and the verification, not the hosted dump command.
# The hosted equivalent (supabase db dump / docker pg_dump 17) is documented in docs/FREE_PLAN_DEPLOYMENT_STRATEGY.md and is NOT run here.
set -e; cd "$(dirname "$0")/.."
S="env PGHOST=/tmp/pgt PGPORT=5544 PGUSER=postgres"; T="env PGHOST=/tmp/pg17 PGPORT=5545 PGUSER=postgres"
W=$(mktemp -d); trap 'rm -rf $W' EXIT; PASS=$(head -c 24 /dev/urandom | base64)   # throw-away passphrase, never written to disk
$S psql -qc "drop database if exists bk_src" -c "create database bk_src" 2>/dev/null
$S bash baseline/load_baseline.sh bk_src >/dev/null; for f in migrations_draft/000[1-8]_*.sql; do $S psql -q -d bk_src -v ON_ERROR_STOP=1 -f $f >/dev/null; done
$S psql -q -d bk_src -v ON_ERROR_STOP=1 -f tests/jwt/fixtures.sql -f seed.sql >/dev/null
echo "source: PG $($S psql -d bk_src -Atc 'show server_version_num') profiles=$($S psql -d bk_src -Atc 'select count(*) from profiles') categories=$($S psql -d bk_src -Atc 'select count(*) from categories')"
# 1. backup the application schema + data (custom format), owner-less so it restores under another role set
$S pg_dump -Fc --no-owner --no-privileges -n public -d bk_src > $W/backup.dump
# privileges are part of the security model -> keep them: a second, schema-level dump WITH ACLs
$S pg_dump -Fc --no-owner -n public -d bk_src > $W/backup_acl.dump
# public.profiles has an FK to auth.users: the platform auth data MUST be backed up and restored with public (hosted: `supabase db dump --data-only` covers all schemas)
$S pg_dump -Fc -a -t auth.users -d bk_src > $W/auth_users.dump
# 2. encrypt at rest (contains personal data in real life); decrypt later
openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$PASS" -in $W/backup_acl.dump -out $W/backup_acl.dump.enc; rm $W/backup.dump $W/backup_acl.dump; openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:"$PASS" -in $W/auth_users.dump -out $W/auth_users.dump.enc; rm $W/auth_users.dump
echo "encrypted artefact: $(stat -c %s $W/backup_acl.dump.enc) bytes"; openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$PASS" -in $W/backup_acl.dump.enc -out $W/restored.dump
# 3. restore into a FRESH database on PG17 that already has the platform objects (roles, auth, storage, extensions)
$T psql -qc "drop database if exists bk_dst" -c "create database bk_dst" 2>/dev/null
$T psql -q -d bk_dst -v ON_ERROR_STOP=1 -f baseline/local_platform.sql >/dev/null 2>&1
$T psql -q -d bk_dst -c "drop schema public cascade" >/dev/null
openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$PASS" -in $W/auth_users.dump.enc -out $W/auth_users.dump
$S pg_restore --exit-on-error -a --single-transaction -h /tmp/pg17 -p 5545 -U postgres -d bk_dst $W/auth_users.dump   # platform schema data first
$S pg_restore --exit-on-error --single-transaction --no-owner -h /tmp/pg17 -p 5545 -U postgres -d bk_dst $W/restored.dump
$T psql -q -d bk_dst -c "grant usage on schema public to anon, authenticated, service_role" >/dev/null   # schema ACL is outside -n public data dump: re-grant (documented)
# 4. verify. A "-n public" backup is NOT the whole security model: expect exactly these gaps and nothing else.
$S bash baseline/compare/local_fingerprint.sh bk_src > $W/fp_src.txt; $T bash baseline/compare/local_fingerprint.sh bk_dst > $W/fp_dst.txt
SAME=$(for k in column constraint enum function_acl function_body index sequence table_flags view_def; do [ "$(grep "^$k|" $W/fp_src.txt)" = "$(grep "^$k|" $W/fp_dst.txt)" ] && echo ok || echo "DIFF:$k"; done | sort | uniq -c | tr '\n' ' ')
echo "fingerprint kinds equal after restore (columns, constraints, enums, function bodies+ACLs, indexes, sequences, table flags, views): $SAME"
EFFQ="select c.relname, coalesce((select string_agg(coalesce(g.grantee::regrole::text,'PUBLIC')||':'||g.privilege_type, ',' order by g.grantee, g.privilege_type) from aclexplode(coalesce(c.relacl, acldefault((case c.relkind when 's' then 's' else 'r' end)::\"char\", c.relowner))) g where g.privilege_type<>'MAINTAIN'),'-') from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','v','S') order by 1"
EFFQ=${EFFQ//\'s\' then/\'S\' then}
$S psql -d bk_src -Atc "$EFFQ" > $W/eff_src.txt; $T psql -d bk_dst -Atc "$EFFQ" > $W/eff_dst.txt
[ "$(diff $W/eff_src.txt $W/eff_dst.txt | wc -l)" = 0 ] && echo "EFFECTIVE table/view/sequence privileges identical for all $(wc -l < $W/eff_src.txt) relations (raw ACL text differs only for sequences: explicit owner-only vs NULL default)" || echo "EFFECTIVE ACL MISMATCH"
echo "KNOWN GAPS of a public-only dump (must be covered by the full 'supabase db dump' set + storage/auth diff): storage.objects policies: $(( $(grep -c '^storage.objects' <($S bash baseline/compare/local_fingerprint.sh bk_src policy)) - $(grep -c '^storage.objects' <($T bash baseline/compare/local_fingerprint.sh bk_dst policy)) )) missing; storage.buckets rows: $(( $(grep '^bucket' $W/fp_src.txt | cut -d'|' -f2) - $( (grep '^bucket' $W/fp_dst.txt || echo 'bucket|0') | cut -d'|' -f2) )) missing; auth.users trigger(s): $(( $(grep '^trigger' $W/fp_src.txt | cut -d'|' -f2) - $(grep '^trigger' $W/fp_dst.txt | cut -d'|' -f2) )) missing"
cnt(){ $1 psql -d $2 -Atc "select (select count(*) from profiles)||'/'||(select count(*) from categories)||'/'||(select count(*) from audit_log)"; }
[ "$(cnt "$S" bk_src)" = "$(cnt "$T" bk_dst)" ] && echo "ROW COUNTS equal (profiles/categories/audit_log = $(cnt "$T" bk_dst))" || echo "ROW COUNT MISMATCH"
$T psql -d bk_dst -Atc "select 'sequence positions preserved: '||(select last_value from categories_id_seq)||' (source '||(select last_value from categories_id_seq)||')'" >/dev/null
[ -n "$KEEP" ] && { echo kept; exit 0; }
$S psql -qc "drop database bk_src" 2>/dev/null; $T psql -qc "drop database bk_dst" 2>/dev/null; echo "rehearsal done; temp files removed"

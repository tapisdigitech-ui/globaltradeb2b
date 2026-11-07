#!/bin/bash
# ROUND 7 ISOLATED DRY-RUN on a LOCAL PostgreSQL clone (baseline -> 0001-0006 -> 0007 -> down 0007 -> re-apply -> down 0007..0001). Touches NO Supabase project.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
case "$PGHOST" in /tmp/*) ;; *) echo "REFUSING: not the local scratch cluster"; exit 2;; esac
echo "ENV: server $(psql -Atc 'show server_version') (LOCAL PG16, hosted staging is PG17)"
D=dry7; bash baseline/load_baseline.sh $D >/dev/null || exit 1
ap(){ psql -q -d $D -v ON_ERROR_STOP=1 -f $1 >/dev/null 2>/tmp/dry7_err || { echo "FAILED: $1"; head -3 /tmp/dry7_err; exit 1; }; }
dump(){ pg_dump -s -d $D --no-owner | grep -v -e '\\restrict' -e '\\unrestrict'; }
fp(){ for k in enum column table_flags constraint index trigger policy function_body function_acl relation_acl view_def sequence bucket; do echo "$k $(bash baseline/compare/local_fingerprint.sh $D $k)"; done; }
for f in migrations_draft/000[1-6]_*.sql; do ap $f; done
dump > /tmp/dry7_pre.sql; fp > /tmp/dry7_pre.fp
ap migrations_draft/0007_function_hardening.sql; echo "APPLY 0007: ok"; dump > /tmp/dry7_post.sql; fp > /tmp/dry7_post.fp
echo "schema lines changed by 0007: $(diff /tmp/dry7_pre.sql /tmp/dry7_post.sql | grep -c '^[<>]')"
ap migrations_draft/down/0007_down.sql; echo "ROLLBACK 0007: ok"; dump > /tmp/dry7_rb.sql; fp > /tmp/dry7_rb.fp
echo "pg_dump diff after rollback 0007 vs pre-0007: $(diff /tmp/dry7_pre.sql /tmp/dry7_rb.sql | wc -l) lines"
echo "catalogue fingerprint diff (13 kinds) after rollback vs pre-0007: $(diff /tmp/dry7_pre.fp /tmp/dry7_rb.fp | wc -l) lines"
ap migrations_draft/0007_function_hardening.sql; echo "RE-APPLY 0007 after rollback: ok"; dump > /tmp/dry7_re.sql; fp > /tmp/dry7_re.fp
echo "pg_dump diff re-applied vs first apply: $(diff /tmp/dry7_post.sql /tmp/dry7_re.sql | wc -l) lines; fingerprint diff: $(diff /tmp/dry7_post.fp /tmp/dry7_re.fp | wc -l) lines"
ap migrations_draft/down/0007_down.sql; ap migrations_draft/down/0006_down.sql
for n in 5 4 3 2 1; do ap migrations_draft/down/000${n}_down.sql; done
bash baseline/load_baseline.sh dry7_base >/dev/null; pg_dump -s -d dry7_base --no-owner | grep -v -e '\\restrict' -e '\\unrestrict' > /tmp/dry7_base.sql; dump > /tmp/dry7_all_down.sql
echo "diff after rolling back ALL (0007..0001) vs untouched baseline clone: $(diff /tmp/dry7_base.sql /tmp/dry7_all_down.sql | wc -l) lines"
python3 - <<'PY'
import re
def norm(f): return [re.sub(r'\s+',' ',x).strip() for x in open(f).read().split(';') if x.strip()]
a,b=norm('/tmp/dry7_base.sql'),norm('/tmp/dry7_all_down.sql')
print("NORMALISED (whitespace collapsed, statement-by-statement) diff after rolling back ALL vs baseline clone: only-in-base=%d only-in-rolled-back=%d statements; order-insensitive equal=%s"%(len([x for x in a if x not in set(b)]),len([x for x in b if x not in set(a)]),sorted(a)==sorted(b)))
PY
psql -qc "drop database dry7" -c "drop database dry7_base"

#!/bin/bash
# ROUND 9 ISOLATED DRY-RUN on a LOCAL PostgreSQL clone (baseline -> 0001-0007 -> 0008 -> down 0008 -> re-apply -> down 0008..0001). Touches NO Supabase project.
export PGHOST=/tmp/pgt PGPORT=5544 PGUSER=postgres; cd "$(dirname "$0")/.."
case "$PGHOST" in /tmp/*) ;; *) echo "REFUSING: not the local scratch cluster"; exit 2;; esac
echo "ENV: server $(psql -Atc 'show server_version') (LOCAL PG16, hosted staging is PG17)"
D=dry8; bash baseline/load_baseline.sh $D >/dev/null || exit 1
ap(){ psql -q -d $D -v ON_ERROR_STOP=1 -f $1 >/dev/null 2>/tmp/dry8_err || { echo "FAILED: $1"; head -3 /tmp/dry8_err; exit 1; }; }
dump(){ pg_dump -s -d $D --no-owner | grep -v -e '\\restrict' -e '\\unrestrict'; }
fp(){ for k in enum column table_flags constraint index trigger policy function_body function_acl relation_acl view_def sequence bucket; do echo "$k $(bash baseline/compare/local_fingerprint.sh $D $k)"; done; }
for f in migrations_draft/000[1-7]_*.sql; do ap $f; done
dump > /tmp/dry8_pre.sql; fp > /tmp/dry8_pre.fp
ap migrations_draft/0008_sequence_privileges.sql; echo "APPLY 0008: ok"; dump > /tmp/dry8_post.sql; fp > /tmp/dry8_post.fp
echo "schema lines changed by 0008: $(diff /tmp/dry8_pre.sql /tmp/dry8_post.sql | grep -c '^[<>]')"
ap migrations_draft/down/0008_down.sql; echo "ROLLBACK 0008: ok"; dump > /tmp/dry8_rb.sql; fp > /tmp/dry8_rb.fp
echo "pg_dump diff after rollback 0008 vs pre-0008: $(diff /tmp/dry8_pre.sql /tmp/dry8_rb.sql | wc -l) lines"
echo "catalogue fingerprint diff (13 kinds) after rollback vs pre-0008: $(diff /tmp/dry8_pre.fp /tmp/dry8_rb.fp | wc -l) lines"
ap migrations_draft/0008_sequence_privileges.sql; echo "RE-APPLY 0008 after rollback: ok"; dump > /tmp/dry8_re.sql; fp > /tmp/dry8_re.fp
echo "pg_dump diff re-applied vs first apply: $(diff /tmp/dry8_post.sql /tmp/dry8_re.sql | wc -l) lines; fingerprint diff: $(diff /tmp/dry8_post.fp /tmp/dry8_re.fp | wc -l) lines"
ap migrations_draft/down/0008_down.sql; ap migrations_draft/down/0007_down.sql; ap migrations_draft/down/0006_down.sql
for n in 5 4 3 2 1; do ap migrations_draft/down/000${n}_down.sql; done
bash baseline/load_baseline.sh dry8_base >/dev/null; pg_dump -s -d dry8_base --no-owner | grep -v -e '\\restrict' -e '\\unrestrict' > /tmp/dry8_base.sql; dump > /tmp/dry8_all_down.sql
echo "diff after rolling back ALL (0008..0001) vs untouched baseline clone: $(diff /tmp/dry8_base.sql /tmp/dry8_all_down.sql | wc -l) lines"
python3 - <<'PY'
import re
def norm(f): return [re.sub(r'\s+',' ',x).strip() for x in open(f).read().split(';') if x.strip()]
a,b=norm('/tmp/dry8_base.sql'),norm('/tmp/dry8_all_down.sql')
print("NORMALISED (whitespace collapsed, statement-by-statement) diff after rolling back ALL vs baseline clone: only-in-base=%d only-in-rolled-back=%d statements; order-insensitive equal=%s"%(len([x for x in a if x not in set(b)]),len([x for x in b if x not in set(a)]),sorted(a)==sorted(b)))
PY
psql -qc "drop database dry8" -c "drop database dry8_base"

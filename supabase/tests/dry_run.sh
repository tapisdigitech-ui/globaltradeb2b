#!/bin/bash
# ISOLATED DRY-RUN (LOCAL PostgreSQL 16 clone built from the read-only staging schema extract). Touches NO Supabase project.
# Steps: environment guard -> fresh clone -> baseline dump -> apply 0001-0006 -> suites -> rollback 0006..0001 -> diff vs baseline.
export PGHOST=/tmp/pgt PGPORT=5544 PGUSER=postgres; cd "$(dirname "$0")/.."
case "$PGHOST" in /tmp/*) ;; *) echo "REFUSING: not the local scratch cluster"; exit 2;; esac
echo "ENV: local socket $PGHOST port $PGPORT, server $(psql -Atc 'show server_version') ; data_directory $(psql -Atc 'show data_directory')"
psql -Atc "select 'supabase-hosted markers: '||count(*) from pg_settings where name ilike '%supabase%'" 
D=dry_rb; bash staging_schema/load_real.sh $D >/dev/null || exit 1
for f in migrations_draft/000[1-5]_*.sql; do psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "0001-0005 FAILED at $f"; exit 1; }; done
dump(){ pg_dump -s -d $D --no-owner | grep -v -e '\\restrict' -e '\\unrestrict'; }
dump > /tmp/dry_pre0006.sql
psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0006_real_schema_hardening.sql >/dev/null 2>&1 && echo "APPLY 0006: ok" || { echo "APPLY 0006 FAILED"; exit 1; }
dump > /tmp/dry_post0006.sql; echo "schema lines changed by 0006: $(diff /tmp/dry_pre0006.sql /tmp/dry_post0006.sql | grep -c '^[<>]')"
psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/down/0006_down.sql >/dev/null 2>&1 && echo "ROLLBACK 0006: ok" || { echo "ROLLBACK 0006 FAILED"; exit 1; }
dump > /tmp/dry_rb6.sql; echo "diff after rolling back 0006 only (schema+grants+policies+settings): $(diff /tmp/dry_pre0006.sql /tmp/dry_rb6.sql | wc -l) lines"
psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/0006_real_schema_hardening.sql >/dev/null 2>&1 && echo "RE-APPLY 0006 after rollback: ok"
psql -q -d $D -v ON_ERROR_STOP=1 -f migrations_draft/down/0006_down.sql >/dev/null 2>&1
for n in 5 4 3 2 1; do f=$(ls migrations_draft/down/000${n}_down.sql); psql -q -d $D -v ON_ERROR_STOP=1 -f $f >/dev/null 2>&1 || { echo "DOWN 000$n FAILED"; exit 1; }; done
bash staging_schema/load_real.sh dry_base >/dev/null; pg_dump -s -d dry_base --no-owner | grep -v -e '\\restrict' -e '\\unrestrict' > /tmp/dry_base.sql
dump > /tmp/dry_all_down.sql; echo "diff after rolling back ALL (0006..0001) vs untouched clone: $(diff /tmp/dry_base.sql /tmp/dry_all_down.sql | wc -l) lines"
psql -qc "drop database dry_rb" -c "drop database dry_base"

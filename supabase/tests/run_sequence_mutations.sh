#!/bin/bash
# MUTATION CONTROL (Round 9.1, item 9): deliberately break privileges/ownership in throw-away copies and prove the genuine-role tests FAIL.
# A suite that cannot fail would be worthless (or would be running as the owner). LOCAL only.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
bash tests/run_sequence_roles.sh default >/tmp/seqrole_base.txt 2>&1; grep -q "0 failed" /tmp/seqrole_base.txt || { echo "baseline not green"; exit 1; }
psql -qc "drop database if exists seqmut" 2>/dev/null
m(){ # name, sql, expected-failing check prefix
  psql -qc "drop database if exists seqmut" -c "create database seqmut template seqrole_default" >/dev/null 2>&1
  psql -q -d seqmut -v ON_ERROR_STOP=1 -c "$2" >/dev/null 2>/tmp/mut_err || { echo "MUTATION SETUP FAILED $1"; head -2 /tmp/mut_err; return; }
  out=$(python3 tests/jwt/test_sequence_roles.py seqmut 2>&1); f=$(echo "$out" | grep "^FAIL" | cut -c1-60 | tr '\n' ';')
  if echo "$out" | grep -q "^FAIL: $3"; then echo "DETECTED  $1  -> $f"; else echo "MISSED    $1 (expected $3) -> $f"; fi
}
psql -qc "do \$\$ begin if not exists(select 1 from pg_roles where rolname='fn_owner_mut') then create role fn_owner_mut nologin; end if; end \$\$" 2>/dev/null
m "M1 revoke authenticated USAGE on categories_id_seq (breaks legit admin insert)" "revoke usage on sequence public.categories_id_seq from authenticated" "S3"
m "M2 grant service_role USAGE on audit_log_id_seq (over-grant)" "grant usage on sequence public.audit_log_id_seq to service_role" "S1 service_role"
m "M3 grant anon SELECT on rate_events_id_seq (info leak)" "grant select on sequence public.rate_events_id_seq to anon" "S1 anon"
m "M4 grant authenticated USAGE on audit_log_id_seq (over-grant)" "grant usage on sequence public.audit_log_id_seq to authenticated" "S1 authenticated"
m "M5 give service_role INSERT on rate_events WITHOUT sequence USAGE (invariant I1)" "grant insert on public.rate_events to service_role" "I1"
m "M6 give service_role an unneeded USAGE with no insert path (invariant I2)" "grant usage on sequence public.product_view_events_id_seq to service_role" "I2"
m "M7 check_rate owned by a role without sequence rights (ownership mismatch)" "grant usage on schema public to fn_owner_mut; grant select,insert,delete on public.rate_events to fn_owner_mut; alter function public.check_rate(text,integer,interval) owner to fn_owner_mut" "F2"
m "M8 unpinned search_path on a SECURITY DEFINER function" "alter function public.check_rate(text,integer,interval) reset search_path" "D3"
m "M9 definer function owned by authenticated" "grant usage on schema public to authenticated; alter function public.record_product_view(uuid,text) owner to authenticated" "D2"
psql -qc "drop database if exists seqmut" 2>/dev/null

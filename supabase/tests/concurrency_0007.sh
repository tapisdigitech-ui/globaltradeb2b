#!/bin/bash
# ROUND 7 concurrency checks on a LOCAL PG16 copy of the post-suite database (real_post: baseline + 0001-0007 + fixtures). Real parallel psql sessions.
# Requires: bash tests/run_real.sh post   (builds real_post)
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
case "$PGHOST" in /tmp/*) ;; *) echo "REFUSING"; exit 2;; esac
psql -qc "drop database if exists conc" -c "create database conc template real_post" >/dev/null || exit 1
Q(){ psql -d conc -Atq "$@"; }
P=0; F=0; chk(){ if [ "$2" = "$3" ]; then echo "PASS: $1 (got $2)"; P=$((P+1)); else echo "FAIL: $1 (expected $3, got $2)"; F=$((F+1)); fi; }
B1=00000000-0000-0000-0000-0000000000b1; B2=00000000-0000-0000-0000-0000000000b2; A1=00000000-0000-0000-0000-0000000000a1
as(){ echo "set role authenticated; set request.jwt.claims='{\"sub\":\"$1\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}';"; }
R1=$(Q -c "select id from enquiries where subject='Rugs 500 pcs'")
# C1: 8 parallel identical create_company_request from a fresh user -> exactly one company
U=00000000-0000-0000-0000-0000000000e1; Q -c "insert into auth.users(id,email,email_confirmed_at) values ('$U','e1@t.example',now())"
for i in 1 2 3 4 5 6 7 8; do ( psql -d conc -Atq -c "$(as $U) select public.create_company_request('Race Co','x','Pune','p')" >/dev/null 2>&1 ) & done; wait
chk "C1 F2: 8 parallel identical company requests create exactly one company" "$(Q -c "select count(*) from companies where created_by='$U' and name='Race Co'")" 1
chk "C1b F2: and exactly one Creator claim / one source" "$(Q -c "select (select count(*) from company_claims where claimant_id='$U')||'/'||(select count(*) from company_sources where recorded_by='$U')")" "1/1"
# C2: accept vs decline in parallel on one sent quote -> exactly one wins
Q -c "insert into quotations(id,enquiry_id,company_id,amount,currency,valid_until,status) values ('99900000-0000-0000-0000-000000000001','$R1','c0000000-0000-0000-0000-000000000001',100,'INR',current_date+3,'sent'),('99900000-0000-0000-0000-000000000002','$R1','c0000000-0000-0000-0000-000000000001',200,'INR',current_date+3,'accepted')"
( psql -d conc -Atq -c "$(as $B1) select public.respond_quotation('99900000-0000-0000-0000-000000000001',true)" > /tmp/c2a 2>&1 ) & ( psql -d conc -Atq -c "$(as $B1) select public.respond_quotation('99900000-0000-0000-0000-000000000001',false)" > /tmp/c2b 2>&1 ) & wait
chk "C2 F7: concurrent accept+decline -> exactly one response succeeds" "$(cat /tmp/c2a /tmp/c2b | grep -c -E '^(accepted|declined)$')" 1
chk "C2b F7: the other is refused as not open" "$(cat /tmp/c2a /tmp/c2b | grep -c 'quotation is not open')" 1
# C3: parallel create_order on one accepted quote -> exactly one order
for i in 1 2 3 4; do ( psql -d conc -Atq -c "$(as $B1) select public.create_order('99900000-0000-0000-0000-000000000002')" >/dev/null 2>&1 ) & done; wait
chk "C3 F8: 4 parallel create_order -> exactly one order" "$(Q -c "select count(*) from orders where quotation_id='99900000-0000-0000-0000-000000000002'")" 1
# C4: parallel import_apply of one validated batch -> serialised, nothing duplicated, audit row per call
Q -c "insert into company_import_batches(id,source_type,source_name,source_url,terms_checked,operator_id,status) values ('c4c40000-0000-0000-0000-000000000001','official_website','Race','https://race.example',true,'$A1','validated')" -c "insert into company_import_rows(batch_id,row_no,raw,name,dedupe_key,status) values ('c4c40000-0000-0000-0000-000000000001',1,'{}'::jsonb,'Race A','n:race a|x','approved'),('c4c40000-0000-0000-0000-000000000001',2,'{}'::jsonb,'Race B','n:race b|x','approved')"
for i in 1 2 3; do ( psql -d conc -Atq -c "$(as $A1) select public.import_apply('c4c40000-0000-0000-0000-000000000001')" >/dev/null 2>&1 ) & done; wait
chk "C4 F5: 3 parallel import_apply -> 2 companies total, no duplicates" "$(Q -c "select count(*) from companies where import_batch_id='c4c40000-0000-0000-0000-000000000001'")" 2
chk "C4b F5: 3 audit rows; inserted sums to 2 (one real apply, two idempotent)" "$(Q -c "select count(*)||'/'||sum(inserted) from company_import_audit where batch_id='c4c40000-0000-0000-0000-000000000001'")" "3/2"
# C5: rollback holds company locks; a concurrent lead-match insert must not slip past the guard (FK fails or blocks until rollback ends)
( psql -d conc -Atq -c "$(as $A1) begin; select public.import_rollback('c4c40000-0000-0000-0000-000000000001','C5'); select pg_sleep(3); commit;" > /tmp/c5a 2>&1 ) &
sleep 1
psql -d conc -Atq -c "insert into requirement_matches(enquiry_id,company_id,score,reasons,route) select '$R1', id, 40, '{}'::jsonb, 'admin' from companies where import_batch_id='c4c40000-0000-0000-0000-000000000001' and name='Race A'" > /tmp/c5b 2>&1; wait
chk "C5 F6: match inserted during rollback is rejected (no orphan, no silent loss)" "$(Q -c "select count(*) from requirement_matches rm where not exists(select 1 from companies c where c.id=rm.company_id)")" 0
chk "C5b F6: rollback completed; match insert failed with FK error" "$(grep -c 'violates foreign key' /tmp/c5b)" 1
# C6: rollback vs apply in parallel on a second batch -> serialised, final state coherent
Q -c "insert into company_import_batches(id,source_type,source_name,source_url,terms_checked,operator_id,status) values ('c6c60000-0000-0000-0000-000000000001','official_website','Race2','https://race2.example',true,'$A1','validated')" -c "insert into company_import_rows(batch_id,row_no,raw,name,dedupe_key,status) values ('c6c60000-0000-0000-0000-000000000001',1,'{}'::jsonb,'Race C','n:race c|x','approved')"
( psql -d conc -Atq -c "$(as $A1) select public.import_apply('c6c60000-0000-0000-0000-000000000001')" >/dev/null 2>&1 ) & ( psql -d conc -Atq -c "$(as $A1) select public.import_rollback('c6c60000-0000-0000-0000-000000000001','C6')" >/dev/null 2>&1 ) & wait
chk "C6 F5/F6: apply||rollback leaves either (applied, 1 company) or (rolled_back, 0 companies) - never a mix" "$(Q -c "select case when (b.status='applied' and (select count(*) from companies where import_batch_id=b.id)=1) or (b.status in ('rolled_back','validated') and (select count(*) from companies where import_batch_id=b.id)=0) then 'coherent' else 'MIXED '||b.status end from company_import_batches b where id='c6c60000-0000-0000-0000-000000000001'")" coherent
# C7: double accept_invitation parallel -> one membership
U2=00000000-0000-0000-0000-0000000000e2; Q -c "insert into auth.users(id,email,email_confirmed_at) values ('$U2','e2@t.example',now())" -c "insert into company_members(id,company_id,invite_email,role,status,expires_at) values ('c7c70000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','e2@t.example','sales','invited',now()+interval '1 day')"
for i in 1 2 3; do ( psql -d conc -Atq -c "$(as $U2) select public.accept_invitation('c7c70000-0000-0000-0000-000000000001')" >/dev/null 2>&1 ) & done; wait
chk "C7 F1: 3 parallel accept_invitation -> one active membership" "$(Q -c "select count(*) from company_members where company_id='c0000000-0000-0000-0000-000000000001' and user_id='$U2' and status='active'")" 1
psql -qc "drop database conc" >/dev/null
echo "CONCURRENCY RESULT: $P passed, $F failed"; [ $F -eq 0 ]

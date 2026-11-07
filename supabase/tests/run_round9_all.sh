#!/bin/bash
# ROUND 9 full LOCAL regression from fresh databases. Touches NO hosted Supabase. Usage: SUPABASE_BIN=... bash tests/run_round9_all.sh
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; cd "$(dirname "$0")/.."
case "$PGHOST" in /tmp/*|localhost|127.0.0.1) ;; *) echo "REFUSING: not the local scratch cluster"; exit 2;; esac
LOG=${LOG:-/tmp/round9}; mkdir -p $LOG
echo "PostgreSQL: $(psql -Atc 'show server_version')"
for d in $(psql -Atc "select datname from pg_database where not datistemplate and datname<>'postgres'"); do psql -qc "drop database \"$d\""; done
for r in authenticator anon authenticated service_role; do psql -qc "drop role if exists $r" 2>/dev/null; done
cnt(){ echo "$1: PASS=$(grep -c -E 'PASS:?( |$)' $2) FAIL=$(grep -c -E 'FAIL' $2) ERROR=$(grep -c 'ERROR' $2)${3:+ $3}"; }
bash tests/run_all.sh > $LOG/legacy.txt 2>&1;                                  cnt "1  legacy 138 suite (own synthetic schema)" $LOG/legacy.txt
for p in pre post6 post; do bash tests/run_real.sh $p > $LOG/real_$p.txt 2>&1; cnt "2  real-schema suite phase=$p" $LOG/real_$p.txt "EXPOSED=$(grep -c EXPOSED $LOG/real_$p.txt)"; done
LOADER=baseline/load_baseline_classic.sh bash tests/run_real.sh post > $LOG/real_post_classic.txt 2>&1; cnt "2b real-schema post, classic-default-ACL platform" $LOG/real_post_classic.txt
bash tests/run_real.sh post >/dev/null 2>&1   # rebuild real_post (default platform) for concurrency
bash tests/concurrency_0007.sh > $LOG/conc.txt 2>&1;                           echo "3  concurrency: $(grep 'CONCURRENCY RESULT' $LOG/conc.txt)"
bash tests/run_jwt.sh > $LOG/jwt.txt 2>&1;                                     echo "4  JWT/claims + evidence matrix: $(grep -E 'JWT TESTS|MATRIX' $LOG/jwt.txt | tr '\n' ';')"
bash tests/run_seed.sh > $LOG/seed.txt 2>&1;                                   cnt "5  category seed" $LOG/seed.txt "(1 ERROR line is the deliberate SD11 guard)"
bash tests/run_sequence_acl.sh default > $LOG/seq_default.txt 2>&1;            cnt "6  sequence ACL (default platform)" $LOG/seq_default.txt
bash tests/run_sequence_acl.sh classic > $LOG/seq_classic.txt 2>&1;            cnt "6b sequence ACL (classic-default-ACL platform)" $LOG/seq_classic.txt
bash tests/run_sequence_acl.sh classic pre0008 > $LOG/seq_pre.txt 2>&1;        cnt "6c CONTROL sequence ACL tests WITHOUT 0008 (must show failures)" $LOG/seq_pre.txt
bash tests/run_sequence_roles.sh default > $LOG/seqrole_default.txt 2>&1;      echo "6d genuine-role sequence tests (default platform): $(grep 'SEQUENCE ROLE TESTS' $LOG/seqrole_default.txt)"
bash tests/run_sequence_roles.sh classic > $LOG/seqrole_classic.txt 2>&1;      echo "6e genuine-role sequence tests (classic platform): $(grep 'SEQUENCE ROLE TESTS' $LOG/seqrole_classic.txt)"
bash tests/run_sequence_mutations.sh > $LOG/seqmut.txt 2>&1;                   echo "6f mutation control: $(grep -c '^DETECTED' $LOG/seqmut.txt) detected / $(grep -c '^MISSED' $LOG/seqmut.txt) missed"
(cd functions/evidence-link && node --test 2>&1 | grep -E '^# (tests|pass|fail)' | tr '\n' ' ' | sed 's/^/7  Edge Function node tests: /'); echo
if [ "${NO_PG_DUMP:-0}" = 1 ]; then   # client tools older than the server (PG16 client vs PG17 server): pg_dump cannot be used
bash tests/rollback_fingerprint.sh > $LOG/rbfp.txt 2>&1;                       echo "8  rollback/re-apply (fingerprint-only):"; grep -v NOTICE $LOG/rbfp.txt | cut -c1-200 | sed 's/^/     /'
else
bash tests/dry_run_0008.sh > $LOG/dry8.txt 2>&1;                               echo "8  0008 rollback/re-apply:"; grep -E "APPLY|ROLLBACK|diff|NORMALISED" $LOG/dry8.txt | sed 's/^/     /'
bash tests/dry_run_0007.sh > $LOG/dry7.txt 2>&1;                               echo "8b 0007 rollback/re-apply:"; grep -E "diff|NORMALISED" $LOG/dry7.txt | sed 's/^/     /'
fi
SUPABASE_BIN=${SUPABASE_BIN:-supabase} bash packaging/run_cli_chain.sh > $LOG/cli.txt 2>&1; echo "9  Supabase CLI chain: $(tail -1 $LOG/cli.txt) / $(grep -c Applying $LOG/cli.txt) migrations applied / $(grep IDENTICAL $LOG/cli.txt)"
bash tests/run_proposal_admin_audit.sh control > $LOG/p_aa_c.txt 2>&1; bash tests/run_proposal_admin_audit.sh proposal > $LOG/p_aa_p.txt 2>&1; cnt "10 proposal admin-audit control" $LOG/p_aa_c.txt; cnt "10b proposal admin-audit" $LOG/p_aa_p.txt
bash tests/run_proposal_invitation.sh control > $LOG/p_i_c.txt 2>&1; bash tests/run_proposal_invitation.sh proposal > $LOG/p_i_p.txt 2>&1; cnt "11 proposal invitation control" $LOG/p_i_c.txt; cnt "11b proposal invitation" $LOG/p_i_p.txt
bash tests/run_proposal_urls.sh control > $LOG/p_u_c.txt 2>&1; bash tests/run_proposal_urls.sh proposal > $LOG/p_u_p.txt 2>&1; cnt "12 proposal url control" $LOG/p_u_c.txt; cnt "12b proposal url" $LOG/p_u_p.txt

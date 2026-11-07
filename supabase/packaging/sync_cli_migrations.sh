#!/bin/bash
# Generates supabase/migrations/ (Supabase CLI layout) from the reviewed drafts as BYTE-IDENTICAL copies and verifies them.
# Source of truth stays in migrations_draft/ (historical SQL untouched); rollback files stay in migrations_draft/down/ (never copied into migrations/).
# Usage: bash packaging/sync_cli_migrations.sh [--check]
set -e; cd "$(dirname "$0")/.."
D=migrations_draft; M=migrations; mkdir -p $M
declare -A MAP=(
 ["$D/baseline/0000_baseline_reconstructed.sql"]="20261107120000_baseline_reconstructed.sql"
 ["$D/0001_supplier_foundation_and_contact_vault.sql"]="20261107120100_supplier_foundation_and_contact_vault.sql"
 ["$D/0002_requirements_matching_lead_desk.sql"]="20261107120200_requirements_matching_lead_desk.sql"
 ["$D/0003_contact_vault_functions.sql"]="20261107120300_contact_vault_functions.sql"
 ["$D/0004_claim_verification_and_invitations.sql"]="20261107120400_claim_verification_and_invitations.sql"
 ["$D/0005_scope_claim_review_access.sql"]="20261107120500_scope_claim_review_access.sql"
 ["$D/0006_real_schema_hardening.sql"]="20261107120600_real_schema_hardening.sql"
 ["$D/0007_function_hardening.sql"]="20261107120700_function_hardening.sql"
 ["$D/0008_sequence_privileges.sql"]="20261107120800_sequence_privileges.sql")
rc=0
for src in "${!MAP[@]}"; do
  [ -f "$src" ] || { echo "MISSING source $src"; rc=1; continue; }
  dst="$M/${MAP[$src]}"
  if [ "$1" = "--check" ]; then cmp -s "$src" "$dst" && echo "identical  ${MAP[$src]}" || { echo "DIFFERS/MISSING ${MAP[$src]}"; rc=1; }
  else cp "$src" "$dst"; echo "copied     ${MAP[$src]}"; fi
done
if [ "$1" = "--check" ]; then extra=$(ls $M | grep -v -F -x -f <(printf '%s\n' "${MAP[@]}") || true); [ -z "$extra" ] || { echo "UNEXPECTED files in migrations/: $extra"; rc=1; }; fi
exit $rc

#!/bin/bash
# Usage: load_baseline.sh DBNAME  - empty local PG -> hosted-like platform stand-in -> reconstructed baseline. LOCAL ONLY.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=postgres; D=${1:-bl1}; cd "$(dirname "$0")"
case "$PGHOST" in /tmp/*) ;; *) echo "REFUSING: not the local scratch cluster"; exit 2;; esac
psql -q -d postgres -c "drop database if exists $D" -c "create database $D" || exit 1
psql -q -d $D -v ON_ERROR_STOP=1 -f local_platform_classic_defaults.sql >/tmp/load_bl_$D.log 2>&1 || { echo "FAILED in local_platform.sql"; tail -5 /tmp/load_bl_$D.log; exit 1; }
PGOPTIONS='-c search_path=public,extensions' psql -q -d $D -v ON_ERROR_STOP=1 -f ../migrations_draft/baseline/0000_baseline_reconstructed.sql >>/tmp/load_bl_$D.log 2>&1 || { echo "FAILED in baseline"; tail -8 /tmp/load_bl_$D.log; exit 1; }
echo "loaded $D (baseline)"

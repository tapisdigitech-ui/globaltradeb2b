#!/bin/bash
# Usage: reset_db.sh <dbname> [baseline.sql]. Recreates a disposable DB (and cluster-wide test roles) from a baseline.
export PGHOST=${PGHOST:-/tmp/pgt} PGPORT=${PGPORT:-5544} PGUSER=${PGUSER:-postgres}
DB=$1; BASE=${2:-$(dirname $0)/baseline_reconstructed.sql}
for d in $(psql -Atc "select datname from pg_database where datname like 't%' and datname ~ '^t[0-9]+$'"); do psql -qc "drop database \"$d\"" ; done
psql -qc "drop role if exists anon" -c "drop role if exists authenticated" -c "drop role if exists service_role" 2>&1 | grep -v NOTICE
psql -qc "create database $DB"
psql -q -d $DB -v ON_ERROR_STOP=1 -f $BASE

#!/bin/bash
# Local PostgreSQL 17.11 (same minor as the hosted projects, 17.11.0.018) WITHOUT Docker, at no cost. Linux x86_64, run as root (drops to user postgres).
# Uses the npm package @embedded-postgres/linux-x64 (real PostgreSQL server binaries; includes contrib: pgcrypto, pg_trgm, uuid-ossp). Server only: no pg_dump/psql 17.
# Usage: bash ops/setup_local_pg17.sh [start|stop|status]     then:  export PGHOST=/tmp/pg17 PGPORT=5545 PGUSER=postgres
set -e; ROOT=${PG17_ROOT:-/tmp/pg17try}; DATA=${PG17_DATA:-/tmp/pg17}; V=17.11.0-beta.19; B=$ROOT/node_modules/@embedded-postgres/linux-x64/native
case "${1:-start}" in
 start)
  if [ ! -x "$B/bin/postgres" ]; then mkdir -p $ROOT && (cd $ROOT && npm init -y >/dev/null && npm i @embedded-postgres/linux-x64@$V >/dev/null); chmod -R a+rx $ROOT; fi
  mkdir -p $DATA && chown postgres $DATA
  [ -f $DATA/data/PG_VERSION ] || su postgres -c "$B/bin/initdb -D $DATA/data -U postgres --auth=trust -E UTF8 --locale=C.UTF-8" >/dev/null
  rm -f $DATA/data/postmaster.pid
  su postgres -c "$B/bin/pg_ctl -D $DATA/data -o '-p 5545 -c unix_socket_directories=$DATA' -l $DATA/log start" >/dev/null; sleep 2
  PGHOST=$DATA PGPORT=5545 psql -U postgres -d postgres -Atc "select 'PostgreSQL '||current_setting('server_version')" ;;
 stop) su postgres -c "$B/bin/pg_ctl -D $DATA/data stop" ;;
 status) PGHOST=$DATA PGPORT=5545 psql -U postgres -d postgres -Atc "show server_version" ;;
esac

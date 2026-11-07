#!/bin/bash
# Usage: local_fingerprint.sh DB [kind]  -> per-kind (count, md5) or the items of one kind
export PGHOST=/tmp/pgt PGPORT=5544 PGUSER=postgres; D=$1; K=$2; cd "$(dirname "$0")"
if [ -z "$K" ]; then psql -d $D -AtF'|' -c "with items as ($(cat items.sql)) select kind, count(*), md5(string_agg(name||h, ',' order by name)) from items group by kind order by kind"
else psql -d $D -AtF'|' -c "with items as ($(cat items.sql)) select name, h from items where kind='$K' order by name"; fi

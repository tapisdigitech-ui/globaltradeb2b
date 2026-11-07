#!/bin/bash
# Usage: verify_fingerprint.sh RESULT.txt EXPECTED.txt   — both in "kind|count|md5" lines (psql -At output of preflight_fingerprint.sql, or baseline/compare/local_fingerprint.sh).
# Exit 0 only if all 13 kinds are identical. Pure text comparison; touches no database.
[ $# = 2 ] || { echo "usage: $0 RESULT EXPECTED"; exit 2; }
if diff <(sort "$1") <(sort "$2") >/dev/null; then echo "FINGERPRINT MATCH ($(wc -l < "$2") kinds): $(basename "$2")"; else echo "FINGERPRINT MISMATCH vs $(basename "$2"):"; diff <(sort "$1") <(sort "$2"); exit 1; fi

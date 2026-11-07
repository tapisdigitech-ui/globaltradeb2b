#!/bin/bash
# Source this (or run it) BEFORE any hosted command: it refuses unless the target is the Free-plan STAGING project and nothing else.
# Usage: PROJECT_REF=<ref> bash guard_target.sh      (prints OK or exits 3)
STAGING_REF=lhmexhafyuzojrmcbtbz
FORBIDDEN_REFS="kwtveqzeayupwrxpwkce"          # globaltradeb2b (production-candidate): never a test target. Add TAPIS KASA's ref here too.
[ -n "$PROJECT_REF" ] || { echo "REFUSING: PROJECT_REF not set"; exit 3; }
for f in $FORBIDDEN_REFS; do [ "$PROJECT_REF" = "$f" ] && { echo "REFUSING: $PROJECT_REF is a protected project"; exit 3; }; done
[ "$PROJECT_REF" = "$STAGING_REF" ] || { echo "REFUSING: $PROJECT_REF is not the approved staging project"; exit 3; }
[ "${I_HAVE_WRITTEN_APPROVAL:-}" = yes ] || { echo "REFUSING: hosted writes need explicit written approval (set I_HAVE_WRITTEN_APPROVAL=yes only after it is given)"; exit 3; }
echo "OK: target is staging ($STAGING_REF)"

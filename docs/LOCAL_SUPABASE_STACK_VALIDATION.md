# Local Supabase Stack Validation

Date: 2026-11-07 (IST). Continues from commit `311d2b8`.
Scope: **local only.** No hosted project, branch, backup, migration or spend. Hosted staging was not contacted at all in this round (not even read-only SELECTs). Production, production-candidate and TAPIS KASA untouched. Free plan unchanged.

## 1. Result in one paragraph

**The full local Supabase stack (`supabase start`) could NOT be run. Items 1, 2, 6 and 7 (and the stack-dependent parts of 3, 4, 8 and 9) are BLOCKED and were not substituted by unverified tests.** The Docker daemon does start in this sandbox, but the network egress policy refuses every container registry Supabase uses, so none of the 12 required images can be pulled. What *was* run: the guard scripts (item 10, passed, including refusal of staging and production-candidate), the regression suite on local PostgreSQL 17.11 (green), the CLI migration chain against bare PostgreSQL (green), and the synthetic backup/restore rehearsal (green, with its known gaps). Those are **stand-in results, not Supabase-stack results**, and are labelled as such below.

## 2. Versions

| Component | Version | Note |
|---|---|---|
| Docker Engine (client + daemon) | 29.9.2 | daemon started manually: `dockerd --data-root /tmp/dk/data -H unix:///var/run/docker.sock`; cgroup v1, overlayfs |
| Supabase CLI | 2.122.1 | `/tmp/clitest/node_modules/.bin/supabase` |
| PostgreSQL (local, stand-in) | 17.11 (npm embedded, `ops/setup_local_pg17.sh`) and 16.15 | not the Supabase postgres image |
| Images `supabase start` needs | postgres 17.11.0.006, gotrue v2.197.0, postgrest v16.5, storage-api v1.84.19, edge-runtime v1.77.8, realtime v2.147.1, postgres-meta v0.100.0, studio 2026.10.19-sha-b375769, kong 2.8.1, logflare 1.50.15, vector 0.58.0-alpine, mailpit v1.31.3 | from the CLI's own pull attempt; none obtained |

## 3. The blocker, exactly

Commands and observed output:
```
$ docker info            # after starting dockerd: Server Version 29.9.2, Storage Driver overlayfs  (daemon OK)
$ docker pull public.ecr.aws/supabase/postgres:17.6.1.054
Error response from daemon: failed to resolve reference ...: Head "https://public.ecr.aws/v2/supabase/postgres/manifests/17.6.1.054": Forbidden
$ curl -sSI https://public.ecr.aws/v2/      -> curl: (56) CONNECT tunnel failed, response 403
$ curl -sSI https://registry-1.docker.io/v2/ -> HTTP/1.1 403 Forbidden (proxy)
$ curl -sSI https://ghcr.io/v2/             -> HTTP/1.1 403 Forbidden (proxy)
$ supabase start
Error response from daemon: failed to resolve reference "docker.io/supabase/edge-runtime:v1.77.8": ... Forbidden
  (same for storage-api, postgres-meta, studio, ... — every image; CLI retries then gives up)
$ docker images -q | wc -l   -> 0        $ docker ps -a | wc -l -> 0
```
The egress proxy status endpoint lists `public.ecr.aws:443` as `connect_rejected` ("policy denial"). This is the sandbox's network allowlist (package registries and GitHub only), not a Docker or Supabase fault. I did not try to bypass it (no mirrors, tunnels or alternative downloads). Without those images there is no GoTrue, PostgREST, Storage API or Edge runtime, so nothing in items 1, 2, 6, 7 can be honestly tested here. Building those services from source or faking them with scripts would be the "unverified substitute" the brief excludes.

**To unblock** (any one): run this document's commands on a machine with Docker and normal internet (your computer, Docker Desktop is free); or have the sandbox allowlist `public.ecr.aws`, `registry-1.docker.io`/`docker.io` and `ghcr.io` (allowlisting is the platform owner's decision, so I have not asked for it); or pre-load the 12 images into the sandbox with `docker load`.

## 4. Status of the ten items

| # | Item | Status | Evidence / reason |
|---|---|---|---|
| 1 | `supabase start` | **BLOCKED** | §3 |
| 2 | Verify local Auth, PostgREST, Storage, Edge Functions | **BLOCKED** | needs 1 |
| 3 | Apply baseline + 0001–0008 locally through the CLI | **PARTIAL (stand-in)** | CLI 2.122.1 `db push --db-url` against bare PG17.11: 9 migrations + seed applied, 13-kind fingerprint identical to `ops/expected_fingerprints/after_0008.txt` ("CLI CHAIN OK / IDENTICAL (13 kinds)"). Not against the Supabase image, so extensions/roles/event triggers of the real image are not exercised. |
| 4 | Synthetic category seed | **PARTIAL (stand-in)** | seed suite PASS=18 FAIL=0; the single ERROR line is the deliberate id/slug-collision guard (SD11) |
| 5 | Full regression suite | **DONE on stand-in** | §5 table; PG17.11 + platform stand-in, not the stack |
| 6 | Real local JWT authentication, all roles | **BLOCKED** | JWT tests use claim-injection into `request.jwt.claims` with stand-in `auth.uid()/role()` (43 + 22 + 28 tests green) — that proves RLS/ACL logic under those claims, **not** GoTrue-issued tokens or PostgREST role switching |
| 7 | Evidence-link authorisation, Storage policies, signed-URL expiry | **BLOCKED (DB part only)** | evidence-link DB matrix 22/22 green on stand-in. Storage policies run against a storage *stub*; real Storage API, bucket enforcement and signed-URL expiry untested |
| 8 | Full backup/restore rehearsal | **PARTIAL** | synthetic rehearsal re-run, green (§6); the full dump set (`supabase db dump` roles/schema/data) needs Docker images → blocked |
| 9 | Storage and Auth configuration preserved | **BLOCKED / gap confirmed** | the rehearsal shows the `public`-only path loses 8 storage.objects policies, 5 bucket rows, 1 auth.users trigger; whether the full set preserves them cannot be verified without the stack |
| 10 | Guard scripts refuse staging/production-candidate without approval | **DONE** | §7 |

## 5. Regression on local PostgreSQL 17.11 (stand-in; not the Supabase stack)

Command:
```
cd supabase
bash ops/setup_local_pg17.sh start
PGHOST=/tmp/pg17 PGPORT=5545 LOG=/tmp/round9_pg17b NO_PG_DUMP=1 \
  SUPABASE_BIN=/tmp/clitest/node_modules/.bin/supabase bash tests/run_round9_all.sh
```
Server 17.11. Results: legacy 138/0; real-schema pre 55/0 (41 EXPOSED by design before migrations), post-0006 361/0, final 404/0, classic-default-ACL platform 404/0; concurrency 11/0; JWT-claims 43/0 and evidence-link matrix 22/0; seed 18/0 (+ deliberate guard); sequence ACL 16/0 (default and classic); control without 0008 shows 7 failures as intended; genuine-role sequence tests 28/0 (both platforms); mutation control 9 detected / 0 missed; Edge Function node tests 27/0; fingerprint rollback/re-apply OK (0008 down leaves 7 equivalent identity-sequence ACL representation items; re-apply identical; roll-back-all leaves 3 whitespace-only function-body items); CLI chain OK; proposal tests admin-audit 30, invitation 14, URL 9, each with controls 2/2.

## 6. Backup/restore rehearsal (synthetic data, stand-in)

Command: `bash ops/rehearse_backup_restore.sh` (source PG16.15 → `pg_dump -Fc -n public` + `auth.users` data → AES-256-CBC/PBKDF2 encryption with a throwaway passphrase → decrypt → restore into a fresh PG17.11 database with the platform stand-in → verify).
Result: 9 fingerprint kinds equal; effective privileges identical on all 85 relations (raw sequence ACL text differs only as explicit owner-only vs NULL default); row counts equal (5 / 14 / 0); temp files removed.
**Known gaps of a `public`-only dump (still open for item 9):** 8 `storage.objects` policies, 5 `storage.buckets` rows, 1 `auth.users` trigger. The rehearsal does not prove `supabase db dump` output or restore of the real `auth`/`storage` schemas.

## 7. Guard scripts

Commands and results (all local; no connection was made by any of them):
```
bash ops/guard_target.sh                                                                  -> REFUSING: PROJECT_REF not set                          rc=3
I_HAVE_WRITTEN_APPROVAL=yes PROJECT_REF=kwtveqzeayupwrxpwkce bash ops/guard_target.sh     -> REFUSING: ... is a protected project                   rc=3  (production-candidate, even with approval flag)
PROJECT_REF=lhmexhafyuzojrmcbtbz bash ops/guard_target.sh                                 -> REFUSING: hosted writes need explicit written approval rc=3  (staging, no approval)
I_HAVE_WRITTEN_APPROVAL=yes PROJECT_REF=abcdefghijklmnopqrst bash ops/guard_target.sh    -> REFUSING: ... is not the approved staging project      rc=3
I_HAVE_WRITTEN_APPROVAL=yes PROJECT_REF=lhmexhafyuzojrmcbtbz bash ops/guard_target.sh    -> OK: target is staging                                  rc=0  (only combination that passes)
```
`ops/verify_fingerprint.sh`: final-chain fingerprint vs `after_0008.txt` → MATCH; vs `baseline_only.txt` → MISMATCH (correct, they differ).
**Limitation:** `guard_target.sh` is a gate that must be run before any hosted command; it cannot stop someone typing a hosted command directly. TAPIS KASA's project ref is not in its forbidden list because it is not known to me — add it (and any production ref) to `FORBIDDEN_REFS`. Because it only passes staging, any unknown ref is refused anyway.

## 8. Commands to run on a machine with Docker (to close items 1, 2, 6–9)

```
cd supabase
supabase start                       # pulls the 12 images listed in §2; prints local API URL, DB URL, anon/service keys
supabase status
supabase db reset                    # applies baseline 0000 + 0001–0008 + seed.sql through the CLI
psql "$DB_URL" -At -f ops/preflight_fingerprint.sql > /tmp/fp.txt   # DB_URL from `supabase status -o env`
bash ops/verify_fingerprint.sh RESULT ops/expected_fingerprints/after_0008.txt
# Auth: sign up synthetic users via http://127.0.0.1:54321/auth/v1/signup (anon key), obtain real JWTs for buyer / seller / admin / unconfirmed
# PostgREST: call /rest/v1/ and /rest/v1/rpc/<fn> with those JWTs; expect RLS/ACL results identical to the claim-injection suite
# Storage: create objects in each bucket as each role; request signed URLs, wait past expiry, expect 400/403
# Edge: supabase functions serve; call each function with real JWTs (valid, expired, wrong role)
# Backup: supabase db dump --local -f roles.sql --role-only; ... -f schema.sql; ... -f data.sql --use-copy --data-only ; restore into a second local stack/DB and compare fingerprints, storage policies, buckets, auth.users trigger
```
Everything there uses synthetic users and data only and no hosted target.

## 9. Limitations (summary)
- No result in this document is a Supabase-stack result. PostgreSQL 17.11 here is the community server with a hand-written platform stand-in.
- Real JWT issuance (GoTrue), PostgREST role switching, Storage API enforcement, signed-URL expiry, Edge runtime behaviour and the real `supabase db dump` are **unverified**.
- Staging was not re-checked this round; its last read-only fingerprint (equal to baseline) is from the previous round.
- The Docker daemon I started is session-local and cannot pull images; no images or containers exist.

## 10. Recommendation
Do not treat the platform as hosted-ready on the strength of stand-in results. Run §8 on your machine (free) or permit the three registries here; send me the output or ask me to re-run, and only then consider the backup of staging in `docs/FREE_PLAN_DEPLOYMENT_STRATEGY.md`. No hosted operation is proposed or performed until you explicitly approve it.

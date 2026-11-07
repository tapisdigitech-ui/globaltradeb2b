# Round 10 — Local Supabase Validation

Starting commit: `439972f` (verified: branch `feature/supplier-intelligence-phase0`, working tree clean). Final commit: the commit containing this file (see git log).
Scope: local only. No hosted project, branch, backup, migration, email/SMS or supplier communication. Hosted staging, production, production-candidate and TAPIS KASA were **not contacted at all**. Free plan unchanged. No network restriction was bypassed.

## 1. Outcome

**The real local Supabase stack could not be started. Round 10 sections 3, 4 (except PostgreSQL stand-in), 6, 7 and 8 and the stack-dependent parts of 5 and 10 are NOT validated.** Nothing was simulated to fill the gap. The independent local checks that remain safe (regression suite, rollback, CLI chain on bare PostgreSQL, backup rehearsal, guards) were re-run on `439972f` and are green; they are stand-in results and are labelled as such.

## 2. Initial checks (§2 of the brief)

| Check | Result |
|---|---|
| Repo / branch / commit / tree | `tapisdigitech-ui/globaltradeb2b`, `feature/supplier-intelligence-phase0`, `439972f`, clean |
| Docker | Engine 29.9.2 (client and daemon); **this is the cloud sandbox, not Docker Desktop on your computer**; daemon started manually with `dockerd --data-root /tmp/dk/data -H unix:///var/run/docker.sock` (cgroup v1, overlayfs) |
| Supabase CLI | 2.122.1 |
| Disk | 252 G volume, 29 G free |
| Ports 54321–54329 | free |
| Docs read | `LOCAL_SUPABASE_STACK_VALIDATION.md`, `FREE_PLAN_DEPLOYMENT_STRATEGY.md` |

**"This computer":** the brief authorises validation on your computer. This session runs in a cloud sandbox. The linked-computer bridge is present but its workspace failed to start: `Workspace unavailable ... the hypervisor is not running. Usually hardware virtualization is off in the device's BIOS/UEFI settings.` Even when it starts, that bridge is an isolated Linux VM with access to connected folders, not your Docker Desktop. Computer-use terminals are click-only, so I could not run `supabase start` through the desktop either. I therefore could not reach Docker Desktop.

## 3. Services blocked (exact registries, images, errors)

Retried this round, same result as before. The egress proxy answers `403` to CONNECT for all three registries:

| Registry | Image tried | Error |
|---|---|---|
| public.ecr.aws | `supabase/postgres:17.11.0.006` | `failed to resolve reference ... Head "https://public.ecr.aws/v2/supabase/postgres/manifests/17.11.0.006": Forbidden` |
| docker.io (registry-1.docker.io) | `supabase/postgres:17.11.0.006` | `... Head "https://registry-1.docker.io/v2/supabase/postgres/manifests/17.11.0.006": Forbidden` |
| ghcr.io | `supabase/postgres:17.11.0.006` | `... Head "https://ghcr.io/v2/supabase/postgres/manifests/17.11.0.006": Forbidden` |

`supabase start` (previous round, full output in the session log) fails on every image it needs: postgres 17.11.0.006, gotrue v2.197.0, postgrest v16.5, storage-api v1.84.19, edge-runtime v1.77.8, realtime v2.147.1, postgres-meta v0.100.0, studio 2026.10.19-sha-b375769, kong 2.8.1, logflare 1.50.15, vector 0.58.0-alpine, mailpit v1.31.3. `docker images` and `docker ps -a` are empty.

| Service | Status |
|---|---|
| PostgreSQL (Supabase image) | **blocked** |
| Auth (GoTrue) | **blocked** |
| PostgREST | **blocked** |
| Storage API | **blocked** |
| Edge Runtime | **blocked** |
| Studio / Realtime / Kong / Logflare / Mailpit | **blocked** |
| Services successfully started | **none** |

No unofficial images, mirrors or fake services were used.

## 4. Items not validated (need the real stack) — would have been tested, were not

- §4 service health and "no request reaches hosted Supabase" (no stack, so trivially no hosted traffic from it).
- §5 migrations through the CLI **against the Supabase image**: extensions, roles, platform event triggers, grants/ownership as created by the real image.
- §6 real Auth users and real GoTrue JWTs for: anonymous, buyer, verified seller, unverified seller, assigned reviewer, unassigned reviewer, staff, administrator; real PostgREST requests; proof that user metadata cannot grant admin.
- §7 private verification bucket, uploads, ownership, reviewer/admin access, Edge evidence-link function, invalid/expired tokens, revoked/expired grants, signed-URL creation and expiry, cross-claim denial, confirmation that no private evidence is public.
- §8 Edge: `verify_jwt = true` at the gateway, 401/403 behaviour, audit logging, rate limits, maximum signed-URL lifetime — the real function running in the edge runtime.
- §10 full backup/restore preserving Auth configuration, Storage buckets and policies with the real `auth`/`storage` schemas.

## 5. Independent local checks (stand-in; not Supabase-stack results)

Environment: community PostgreSQL 17.11 (`ops/setup_local_pg17.sh`, npm embedded binaries) plus hand-written platform stand-in (`baseline/local_platform.sql`); JWT tests inject claims into `request.jwt.claims`.

Command:
```
cd supabase
bash ops/setup_local_pg17.sh start
PGHOST=/tmp/pg17 PGPORT=5545 LOG=/tmp/round10 NO_PG_DUMP=1 \
  SUPABASE_BIN=/tmp/clitest/node_modules/.bin/supabase bash tests/run_round9_all.sh
```
Results (server 17.11):

| Suite | Result |
|---|---|
| Legacy | PASS 138 / FAIL 0 |
| Real-schema pre-migration | 55 / 0 (41 EXPOSED by design) |
| Real-schema after 0006 | 361 / 0 |
| Real-schema final | 404 / 0 (also with classic default-ACL platform: 404 / 0) |
| Concurrency | 11 / 0 |
| JWT-claims | 43 / 0 |
| Evidence-link DB matrix | 22 / 0 |
| Category seed | 18 / 0 (+1 deliberate guard ERROR, SD11) |
| Sequence ACL | 16 / 0 (default) and 16 / 0 (classic); control without 0008: 9 pass / 7 fail as intended |
| Genuine-role sequence tests | 28 / 0 (both platforms) |
| Mutation control | 9 detected / 0 missed |
| Edge Function (node unit tests) | 27 / 0 |
| Proposal admin-audit / invitation / URL | 30 / 14 / 9 (+ controls 2 / 2 / 2, all pass) |
| Rollback & re-apply (fingerprint) | 0008 down: 7 items differ (identity-sequence ACL NULL → explicit owner-only, equivalent); re-apply: 0 differences; roll back all: 3 whitespace-only function-body items |
| Supabase CLI chain on bare PG17.11 | 9 migrations + seed applied, 13 kinds IDENTICAL to expected `after_0008` |

Migration order, baseline and 0001–0008 are verified by the CLI chain and per-step fingerprints on this stand-in only.

## 6. Backup and restore rehearsal (synthetic, stand-in)
`bash ops/rehearse_backup_restore.sh`: 9 fingerprint kinds equal after restore; effective privileges identical on all 85 relations; row counts equal (5 / 14 / 0).
Previously discovered omissions of a `public`-only dump, **re-confirmed**: 8 `storage.objects` policies, 5 `storage.buckets` rows, 1 `auth.users` trigger are missing after restore. Whether the full `supabase db dump` set preserves them (and Auth configuration) is **unverified**.

## 7. Guard scripts
```
PROJECT_REF=                          I_HAVE_WRITTEN_APPROVAL=     -> REFUSING: PROJECT_REF not set                    rc=3
PROJECT_REF=kwtveqzeayupwrxpwkce      I_HAVE_WRITTEN_APPROVAL=yes  -> REFUSING: ... is a protected project              rc=3
PROJECT_REF=lhmexhafyuzojrmcbtbz      I_HAVE_WRITTEN_APPROVAL=     -> REFUSING: hosted writes need explicit approval   rc=3
PROJECT_REF=abcdefghijklmnopqrst      I_HAVE_WRITTEN_APPROVAL=yes  -> REFUSING: ... is not the approved staging project rc=3
```
Staging approval was not enabled; no hosted command was executed. The guard is a gate to run before hosted commands, not an enforcement layer; TAPIS KASA's ref is not in `FORBIDDEN_REFS` (unknown to me), but any unrecognised ref is refused anyway.

## 8. Security issues discovered
None new this round (nothing new was testable). Standing observations: the Free plan has no backups/PITR; stand-in coverage cannot show GoTrue/PostgREST/Storage/Edge behaviour, so those remain unproven rather than "passing".

## 9. Remaining verification (needs the real stack; all free, all local)
Run on a machine with Docker Desktop and internet (or permit the three registries here, or `docker load` pre-pulled images): the commands in `docs/LOCAL_SUPABASE_STACK_VALIDATION.md` §8, covering `supabase start`, `supabase db reset`, real Auth sign-up for the eight personas, PostgREST calls with the real JWTs, Storage uploads / signed-URL expiry, `supabase functions serve` with valid/expired/wrong-role tokens, and `supabase db dump --local` backup/restore compared against the fingerprints. Hosted-only items remain after that: pooler behaviour, real statement timeouts, quota behaviour on the Free project.

## 10. Commands used (this round)
`git rev-parse`, `git status`, `df -h`, `ss -ltn`; `dockerd --data-root /tmp/dk/data -H unix:///var/run/docker.sock`; `docker version`; `docker pull {public.ecr.aws,docker.io,ghcr.io}/supabase/postgres:17.11.0.006`; `supabase --version`; `bash ops/setup_local_pg17.sh start`; the guard invocations in §7; the regression command in §5; `bash ops/rehearse_backup_restore.sh`.

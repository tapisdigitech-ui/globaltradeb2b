# Round 9 readiness report – Supabase packaging & authentication readiness

Branch `feature/supplier-intelligence-phase0`, started from `83f7a8c`. **LOCAL ONLY.** No Supabase branch created, no migration applied to any hosted project, nothing deployed or promoted, no communications sent, no real accounts, no staging rows read (the only hosted access this round was the earlier read-only catalogue read of the four `auth.*` function definitions). All test data is synthetic (`SYNTHETIC …` names, `.invalid` emails, `is_demo=true`).

## 1. Blocker status (B1–B6)
| # | Round-8 blocker | Status | Evidence |
|---|---|---|---|
| B1 | Migration packaging | **Resolved locally.** `supabase/migrations/` holds baseline + 0001–0008 as byte-identical, CLI-ordered copies; rollbacks stay in `migrations_draft/down/`. Real Supabase CLI 2.122.1 `db push` (dry-run, apply, re-push "up to date") against a fresh local DB; catalogue fingerprint identical to the plain-psql chain (13 kinds). Isolated-branch initialisation documented. | docs/MIGRATION_PACKAGING.md, `packaging/run_cli_chain.sh` |
| B2 | JWT-realistic harness | **Resolved locally, with documented hosted-only limits.** Real `auth.uid/role/email/jwt` definitions; whole suite now driven by `request.jwt.claims`; PostgREST emulator with signed HS256 tokens (43 claim tests + 22 evidence-link checks). | docs/JWT_TEST_COVERAGE.md |
| B3 | Category seed | **Resolved locally.** `supabase/seed.sql`, 14 names from the app's own `SECTIONS`; idempotent, collision-guarded; 18 tests. **Equality with staging's categories is unverified** (not read). | docs/CATEGORY_SEED.md |
| B4 | Edge `verify_jwt` | **Resolved.** Explicit `verify_jwt = true` in `config.toml` (test-pinned); 27 node tests incl. emulated gateway + 22 DB-side checks; enforcement split documented; function checks not weakened (one 401-mapping added). | docs/EDGE_FUNCTION_JWT.md |
| B5 | Sequence ACLs | **Resolved locally** by new migration 0008 (revoke all 13 from PUBLIC/anon/authenticated/service_role, USAGE on `categories_id_seq` for authenticated only, default privileges closed). 16 ACL/attempt/legit-insert tests on two platform simulations; 404 suite passes with it. Staging's real sequence ACLs still need a hosted check. | docs/SEQUENCE_ACL_AUDIT.md |
| B6 | Organisation plan unconfirmed | **OPEN – cannot be resolved locally.** Branching requires a plan that supports it; the plan was not assumed or inspected. | docs/BRANCH_LIFECYCLE_COST_ASSESSMENT.md |

## 2. Migration commands and layout
See docs/MIGRATION_PACKAGING.md. Summary: `bash supabase/packaging/sync_cli_migrations.sh [--check]`; `SUPABASE_BIN=… bash supabase/packaging/run_cli_chain.sh`; chain = `20261107120000_baseline_reconstructed` → `…0100` (0001) … `…0700` (0007) → `…0800_sequence_privileges` (0008, new). Seed: `supabase/seed.sql`.

## 3. JWT test coverage and limitations
Covered: `sub`, `role`, `aud`, `email`; anon / authenticated / service_role; no token; forged, expired, not-yet-valid, `alg:none`, HS512, malformed tokens (rejected before SQL); role-claim switching limited by the `authenticator` role (`role=postgres` fails); non-UUID / missing sub fail closed; app/user metadata cannot raise privileges (authority is `profiles.app_role`; no policy or function reads `auth.jwt()`); RLS and definer functions through real claims; trusted-session semantics; service_role limits. Limitations (hosted-only): GoTrue issuance/`aud`/`iss`, asymmetric signing keys/JWKS, gateway and PostgREST config, Storage service, per-role timeouts, PG17. Full list in docs/JWT_TEST_COVERAGE.md.
Findings from the new realism: (a) the staging ACLs give `service_role` no UPDATE on `companies`/`profiles` – trusted writes must go through SECURITY DEFINER RPCs; (b) the public anon key and service key both pass a `verify_jwt` gateway, so function-level role checks are essential (already present); (c) `aud` is not checked inside the database.
Test-tooling defects found and fixed this round: a quoting bug in the concurrency script after the claims conversion (caught by re-running it), and two stale expectations in my own new tests.

## 4. Seed provenance
Names/hue/order from `index.html` `SECTIONS` (14 entries); slugs from `make_slug`; `spec_template` left default (shape unknown); never read from or run against staging.

## 5. Edge Function configuration
`[functions.evidence-link] enabled=true verify_jwt=true`. Gateway = valid platform-signed token only; function = role/sub/exp, validation, path and set checks, TTL clamp, no service key; database = identity, staff, assignment, evidence ownership, rate limits, grant lifetime, audit, storage RLS. Not run on the Deno runtime.

## 6. Sequence ACL audit
13 sequences. Before: six serial sequences gave `authenticated` SELECT+USAGE; classic defaults would give all three roles ALL on any new sequence. After 0008: only `authenticated` USAGE on `categories_id_seq`. Rollback restores the original six; does not re-open default privileges; identity-sequence ACLs return as explicit owner-only (equivalent, fingerprint differs).

## 7. Privacy review proposals (not implemented)
docs/PRIVACY_REVIEW_PROPOSAL.md: P1 admin `profiles.phone`, P2 admin orders, P3 `staff_open_enquiry_comms` purpose codes + references + per-enquiry cap, P4 denied-access logging (RPC pattern, flood caps; RLS cannot self-log). Plus the existing admin message-audit prototype. All outside the migration chain.

## 8. Invitation transition decision
Reviewed in docs/INVITATION_TRANSITION_PROPOSAL.md (Round 9 section): affects only pending, unaccepted rows with NULL expiry; expiry = `created_at + 14 days`; **made idempotent**; young legitimate invites stay usable, old ones expire; auditable (immutable log + membership audit); rollback restores NULL only for rows still holding the transition value. Decision: apply once from a trusted session on a hosted branch only if the (still unknown) count is non-zero; needs approval. 14/14 proposal tests (+2 control).

## 9. Complete test results (fresh local databases, PostgreSQL **16.15**; staging is 17.11 so none of this is a PG17 result)
| # | Suite | Result |
|---|---|---|
| 1 | Legacy suite (own synthetic schema) | **138 pass / 0 fail** |
| 2 | Real-schema suite, phase pre (baseline+0001–0005 control) | 55 pass / 0 fail / 41 EXPOSED (expected pre-hardening) |
| 2 | phase post6 (+0006) | 361 pass / 0 fail / 0 exposed |
| 2 | phase post (+0007 +0008) | **404 pass / 0 fail** |
| 2b | phase post on classic-default-ACL platform | **404 pass / 0 fail** |
| 3 | Concurrency (real parallel sessions) | 11 pass / 0 fail |
| 4 | JWT claim tests (PostgREST emulator) | 43 pass / 0 fail |
| 4 | Evidence-link DB matrix (signed tokens) | 22 pass / 0 fail |
| 5 | Category seed | 18 pass / 0 fail (one expected ERROR line = SD11 guard) |
| 6 | Sequence ACL, default / classic platform | 16 / 16 pass; control without 0008: 7 expected failures |
| 7 | Edge Function node tests | 27 pass / 0 fail |
| 8 | 0008 rollback & re-apply | pg_dump diff after rollback 0 lines; re-apply identical (0 lines); fingerprint diff after rollback 28 lines = the 7 identity-sequence ACLs NULL→explicit owner-only (equivalent privileges) |
| 8b | 0007 rollback & re-apply | pg_dump 0, fingerprint 0, re-apply 0 |
| 8c | Roll back all (0008…0001) vs untouched baseline | raw diff 25 lines (whitespace in function bodies); **normalised statement comparison: 0 differences, order-insensitive equal = True** |
| 9 | Supabase CLI chain | 9 migrations + seed applied; re-push up to date; fingerprint identical (13 kinds) |
| 10–12 | Proposals: admin-audit 30 (+2 control), invitation 14 (+2), URL validation 9 (+2) | all pass |

Reproduce everything: `SUPABASE_BIN=… bash supabase/tests/run_round9_all.sh`.

## 10. Remaining hosted-only verification
1. Confirm organisation plan supports branching and cost acceptance (B6) – before any branch.
2. First real apply of the chain on an isolated branch (PG17, real `extensions`/`auth`/`storage`), then rerun the suites there with real tokens.
3. GoTrue-issued JWT claims (`aud`, `role`, `app_metadata`), signing-key type, `auth.users → profiles` signup trigger, gateway `verify_jwt` behaviour, Deno runtime and Storage signed URLs.
4. Staging categories vs `seed.sql`; staging sequence ACLs and default privileges; storage.objects RLS "enabled not forced".
5. Per-role `statement_timeout` effects; the count of legacy NULL-expiry invitations (aggregate only, approved separately).
6. Front-end inventory before any privacy proposal (P1–P4) is approved.

## 11. Verdict
**Ready for an approved, isolated-branch trial – not ready to touch staging, production-candidate or TAPIS KASA.** B1–B5 are resolved to the extent a local PostgreSQL 16 replica can show; B6 is open and external. Blockers before any hosted action: **B6** (plan/cost confirmation and explicit approval to create a branch); and, on that branch, items 2–4 above must pass before anything is promoted. Nothing was created or applied hosted; waiting for explicit approval.

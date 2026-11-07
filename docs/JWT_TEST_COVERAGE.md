# JWT / role test coverage (Round 9 · B2)

LOCAL replica (PostgreSQL 16.15). Not Supabase. All tokens are synthetic, signed with a throw-away secret that is not a Supabase key.

## What changed
1. **Real auth functions.** `baseline/local_platform.sql` now defines `auth.uid()`, `auth.role()`, `auth.email()`, `auth.jwt()` with the exact bodies read from the staging catalogue (read-only `pg_get_functiondef`): they read `request.jwt.claims` (and the legacy `request.jwt.claim.*`). The old `app.uid` stub is gone.
2. **Suite switched to claims.** `tests/real_schema_tests.sql`, `tests/proposals/*`, `tests/concurrency_0007.sh` now set `request.jwt.claims = {"sub":…,"role":"authenticated","aud":"authenticated"}`. All 404 real-schema tests still pass (also on the classic-default-ACL platform). A locally assigned user id is therefore no longer the mechanism: identity comes from the same GUC PostgREST sets. (The legacy 138-test suite is self-contained with its own synthetic schema/stub and was left unchanged.)
3. **PostgREST emulator** (`tests/jwt/postgrest_emulator.py`, stdlib only). Mints and verifies HS256 tokens (signature, `alg` allow-list, `exp`, `nbf`, optional `aud`), then runs SQL the way PostgREST does: `session_user = authenticator` (NOINHERIT, member of anon/authenticated/service_role only) → `BEGIN; SET LOCAL ROLE <role claim, default anon>; set_config('request.jwt.claims', payload, true); …; ROLLBACK`. Bad tokens never reach SQL (401).

## Coverage (`tests/jwt/test_jwt_claims.py` – 43 checks; `test_evidence_link_db.py` – 22 checks)
| Area | Checks |
|---|---|
| `sub`/`role`/`aud`/`email` → `auth.uid()/role()/email()/jwt()`; `current_user`, `session_user` | J1–J5 |
| no token → anon role, null claims; anon-role token; service_role token | J2–J4, J14 |
| rejected before SQL: forged signature, expired, `nbf` future, `alg:none`, HS512, malformed, forged service_role | J6–J11b |
| role-claim handling: `role=postgres` (authenticator cannot `SET ROLE`), unknown role, missing role → anon | J12–J14 |
| fail-closed identity: non-UUID `sub` errors, missing/empty `sub` → uid null → 0 rows | J15–J16b |
| **metadata cannot escalate**: `app_metadata`/`user_metadata` claiming admin/reviewer do not change `is_admin()/is_staff()` (authority is `profiles.app_role`; no function or policy reads `auth.jwt()` – checked by grep) | J17, EV6b |
| `aud` is not enforced by the database (documented; gateway/PostgREST job) | J20, J20b |
| RLS via real claims: own profile only; admin sees others; reviewer cannot read buyer profiles (0006 F-R8); anon blocked from base tables, can read categories; anon cannot execute `is_admin`; update of others' rows blocked; no self-promotion; own update works; audit_log admin-only | J21–J31 |
| service_role: BYPASSRLS, no uid, `is_admin()` false, table ACLs limit writes (no UPDATE on companies – same as staging ACLs), no sequence privileges | J32–J34, J38 |
| trusted session: `is_trusted_session()` true only for service_role/postgres; admin JWT is not trusted; protected company columns guarded | J35–J37 |
| evidence-link RPC, every caller class (see docs/EDGE_FUNCTION_JWT.md) | EV1–EV15 |
| the 404 real-schema tests (all policies, SECURITY DEFINER functions, grants, storage) under claims | run_real.sh |

## Cannot be reproduced without hosted Supabase (carried to the checklist)
- GoTrue: token issuance, refresh, `aud`/`iss` values, `app_metadata` population, email-confirmation flow, `auth.users → profiles` trigger on real signup (the stub `auth.users` + baseline trigger is exercised only by direct insert).
- JWT signing: current projects may use asymmetric signing keys / JWKS; the emulator uses HS256 with a shared secret. Key rotation and revocation not modelled.
- The Edge/Kong gateway and PostgREST specifics (jwt-aud setting, pre-request hook, `Accept-Profile`, exposed-schema list, request-size limits, per-role `statement_timeout` anon 3 s / authenticated 8 s).
- Real `storage` service: signed-URL creation/validation, bucket policies as evaluated by the Storage API (only the RLS expressions on a stub `storage.objects` are tested).
- PG17 behaviour and real default privileges for objects created by `supabase_admin`/dashboard.
- Service-key handling (never in browsers) – operational, not testable here.

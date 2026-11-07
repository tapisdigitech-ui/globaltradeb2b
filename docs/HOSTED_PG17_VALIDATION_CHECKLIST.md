# Hosted PostgreSQL 17 / Supabase validation checklist (Round 8) — NOT executed

Legend: **L** = locally tested (PG 16.15 + platform stand-in); **C** = catalogue-verified (read-only comparison with staging, PG 17.11); **U** = still unverified. Nothing below has been run on hosted.

| # | Area | What must be verified in a real isolated branch | Status today |
|---|---|---|---|
| 1 | Schema reproduction | Branch built from baseline + 0001–0007 has the same 13-kind fingerprints as the local build; `list_migrations` shows the chain | baseline vs staging: **C** (13 kinds); branch build: **U** |
| 2 | PG17 behaviour | whole real suite (404 assertions) passes on PG 17; look for planner/`MAINTAIN`/ACL-display differences; `pg_dump` diff of local vs branch | PG16 only: **L**; PG17: **U** |
| 3 | Extensions | `pgcrypto`, `pg_trgm`, `uuid-ossp` live in schema `extensions`; `extensions.digest/gen_random_bytes` resolve under function `search_path public, pg_temp`; trigram indexes built | stand-in schema: **L**; real: **U** (this was a real hosted-only defect, fixed in 0007 F9) |
| 4 | Auth roles / JWT | `auth.uid()` from real JWT claims (`request.jwt.claims`), `role` claim → `authenticated`/`anon`/`service_role`; `auth.users` → `profiles` trigger; confirmed-email logic in invitations. **The SQL suite impersonates with a `app.uid` setting; it must be re-driven with real tokens or `request.jwt.claims`** | **U** |
| 5 | PostgREST exposure | which functions/tables are reachable via `/rest/v1/rpc`; return types (`respond_quotation` now `text`, `staff_open_*` set-returning); error code/message mapping (`42501` → 403; Edge handler relies on message `staff only`); exposed schemas = `public` only; `anon` sees only the 9 relations | grants **C**; HTTP behaviour **U** |
| 6 | Storage | bucket policies with **real user tokens**: upload/read per bucket, `foldername` + `safe_uuid` path traps (`../`, non-UUID folder), size/MIME limits, `public` bucket direct reads, `storage.objects` RLS not forced (hosted-owned) | policy text **C**; behaviour **U** |
| 7 | Signed URLs | `createSignedUrl` with the staff JWT succeeds only while `evidence_grant_active`; expiry (≤120 s default) honoured; URL unusable after expiry; **not revocable after issuance** (accepted) | SQL gate **L**; signing **U** |
| 8 | Edge Function | deploy to the branch only; `verify_jwt=true` (no `config.toml` exists in the repo — must be set explicitly); 401 for no/anon/expired token, 403 non-staff, 429/denials; `SUPABASE_URL`/`SUPABASE_ANON_KEY` injected; function uses anon key + user JWT (no service role) | handler tests 11/11 **L**; runtime **U** |
| 9 | Privileges | default ACLs of the branch's `postgres` role vs staging; `relation_acl`/`function_acl` fingerprints on the branch; the 7 identity sequences (see MIGRATION_INVENTORY §4) | classic-default simulation **L**; real **U** |
| 10 | SECURITY DEFINER | owner is `postgres` with BYPASSRLS on hosted; confirm every definer function enforces its own checks (tests EL/SF/SA) with real roles; `search_path` fixed | **L** (stand-in owner); real owner attributes **U** |
| 11 | Role settings | `statement_timeout` (anon 3 s, authenticated 8 s) vs slowest policy/function paths (evidence gate, import apply on large batches) | **C** (values read) / timing **U** |
| 12 | Rate limits & time | `now()`/interval logic, per-user hourly/daily counters under real clock and concurrent PostgREST connections | **L** + local concurrency 11/11; pooler **U** |
| 13 | Concurrency via pooler | advisory-lock and `FOR UPDATE` paths (F2, F6, F7, F8) under Supavisor transaction pooling (`pg_advisory_xact_lock` is transaction-scoped, fine in transaction mode) | local sessions **L**; pooled **U** |
| 14 | Migration runner | CLI/branch application of files containing their own `begin/commit`; version naming; seed of the 14 `categories` rows (synthetic) | **U** |
| 15 | Realtime / publications | `supabase_realtime` publication membership of sensitive tables (must exclude message/contact tables) | not reconstructed: **U** |
| 16 | Advisors | run security & performance advisors on the branch; expect findings only for documented design (definer views, unforced storage RLS, zero-policy tables) | **U** |
| 17 | Auth settings | redirect allow-list, email confirmation required, signup disabled/limited, JWT expiry — open-redirect surface | **U** |
| 18 | Cost/teardown | branch deleted, billing stops, no residual objects | **U** |

Exit criteria for a first isolated run: items 1–10 pass with real tokens; every discrepancy documented before any further step.

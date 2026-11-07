# Baseline reconstruction report (Round 7) — LOCAL ONLY

Status: **proposal**. Nothing in this report was applied to any Supabase project. Staging (`lhmexhafyuzojrmcbtbz`) was touched only by read-only catalogue `SELECT`s (earlier rounds and the 13-kind comparison below); no credentials, row data, contact data or real buyer/supplier information appear here.

## 1. Why a baseline is needed
`list_migrations` on staging returns an empty history even though the schema exists (46 public tables). A Supabase branch (or any `db reset`/CLI replay) is built from the migration history, so a branch cut today would contain **no application schema**, and `0001`–`0006` (which `alter` existing objects) could not apply. The schema therefore has to exist as its own migration, ordered before `0001`.

## 2. Artifacts
| File | Purpose |
|---|---|
| `supabase/migrations_draft/baseline/0000_baseline_reconstructed.sql` | the proposed baseline (generated; ~1.5k lines, single transaction, `set local search_path = public, extensions`) |
| `supabase/baseline/build_baseline.py` | generator: reads the git-ignored read-only staging extract (`staging_schema/real_0*.sql`), strips platform stubs, keeps the last body per function signature, emits grants from the ACL catalogue of a loader replica |
| `supabase/baseline/local_platform.sql` | LOCAL stand-in for what Supabase provides (roles, `extensions` schema, `auth.users`/`auth.uid()`, `storage` tables). Never part of a migration |
| `supabase/baseline/load_baseline.sh` | empty local DB → platform stand-in → baseline (refuses non-`/tmp` sockets) |
| `supabase/baseline/compare/{items.sql,local_fingerprint.sh}` | 13-kind catalogue fingerprint, run read-only on staging and locally |
| `supabase/baseline/table_comments.sql` | 46 table comments copied verbatim from staging |

Reproducibility: `bash baseline/load_baseline.sh <db>` on an **empty** PostgreSQL 16.15 database succeeds; `0001`–`0007` then apply on top; the whole real-schema suite runs on this stack (see ROUND7_TEST_REPORT.md).

## 3. (1) Objects included
Enum types (24), tables and views (58 relations incl. 6 views and 6 sequences), 443 columns with defaults/not-null, 165 constraints (PK/FK/unique/check), 76 indexes, 42 triggers, 70 functions (bodies, `SECURITY DEFINER`, `search_path`, volatility), 105 RLS policies plus enable/force-RLS flags, explicit table/sequence/function grants (273 statements) for `anon`/`authenticated`/`service_role`, table comments, and the 5 storage bucket definitions (`storage.buckets` rows, no objects). No secrets, tokens, keys, URLs with credentials, or environment identifiers are embedded (checked by grep on the generated file).

## 4. (2) Objects excluded, and why
| Excluded | Reason |
|---|---|
| `auth.*`, `storage.*` tables/functions/policies owned by the platform, `realtime`, `vault`, `graphql*`, `extensions` contents | Supabase-managed; redefining them is unsafe and non-portable. Only the 5 bucket rows are inserted |
| Roles (`anon`, `authenticated`, `service_role`, `postgres`, `supabase_*`) and their `ALTER ROLE` settings (e.g. statement timeouts) | cluster-level, exist on the target; creating roles in a migration would be wrong |
| Extension installation (`pgcrypto`, `pg_trgm`, `uuid-ossp`) | provided by the platform in schema `extensions`; the baseline only sets `search_path` to find them |
| All row data, including the 14 `categories` seed rows | not captured (names were not read); data is not schema. **Gap**, see 5 |
| The PG17-only `MAINTAIN` table privilege | does not exist in PG16; excluded from fingerprints, cannot be validated locally |
| Event triggers, publication `supabase_realtime`, platform default ACLs of other roles | platform-owned |
| Stub/placeholder bodies from earlier rounds | replaced by exact staging `prosrc` (12 functions in Round 6, plus `set_data_review` and `import_normalize` in Round 7) |

## 5. (3) Objects that cannot be reconstructed reliably
- **`categories` seed rows** (14): count known, names not captured. A branch built from the baseline has an empty catalogue until seeded.
- **Column order** is reconstructed from the extract, not hashed; positional `INSERT`/`SELECT *` consumers are not validated.
- **Comments/ownership** of objects other than tables, and object OIDs/creation order, are not reproducible.
- **Function bodies edited via the dashboard after the extract** would only be caught by a fresh read-only extract (the comparison below is a point-in-time statement).
- **`storage.objects` row-level-security FORCE flag** and platform ownership: staging has RLS enabled (not forced); the local stand-in cannot prove the hosted owner/flag behaviour.

## 6. (4) Reconstructed local schema vs the read-only staging catalogue
Method: the same 13 fingerprint queries (`items.sql`) were run read-only on staging (`execute_sql`, `SELECT` only) and on the local baseline; each item is an md5 of its normalised definition, compared item by item and as a rollup.

| Kind | Local items | Local rollup (md5, 12 chars) | Result vs staging |
|---|---|---|---|
| enum (labels, order) | 24 | 527141766096 | identical |
| column (type, nullability, default) | 443 | c618201545a1 | identical |
| table_flags (RLS, FORCE RLS, kind) | 58 | bef8446600c0 | identical |
| constraint | 165 | 3e786ee7c074 | identical |
| index | 76 | 3448a3e539ee | identical |
| trigger | 42 | 098016cb1179 | identical |
| policy (command, roles, USING, CHECK) | 105 | c5ffbbbffb0b | identical |
| function_body | 70 | c71d3550f084 | identical |
| function_acl | 70 | 2e5b60e0accc | identical |
| relation_acl | 58 | 446cd6939795 | identical (MAINTAIN excluded, PG17-only) |
| view_def | 6 | a530d0df1e69 | identical |
| sequence (type, ACL) | 6 | 924bd51063c4 | identical |
| bucket definitions | 5 | d65a443b1d10 | identical |

**What this supports:** for these 13 kinds, at the time of comparison, the reconstructed local schema is catalogue-equivalent to staging. **What it does not support:** equivalence of data, of column order, of platform-managed objects, of hosted-only settings, or of runtime behaviour on PostgreSQL 17. This report does not claim whole-database equivalence. The comparison was run once against the extract that the baseline was generated from; re-run `compare/` before any hosted use.

Known differences that remain: PG 16.15 (local) vs PG 17.11 (staging); local platform stand-in vs real Supabase; no row data; categories seed absent; `MAINTAIN` privilege absent locally.

## 7. (5) Dependencies on Supabase-managed infrastructure that cannot be validated locally
`auth.uid()` and the JWT-claim plumbing (local stub reads a setting), `auth.users` triggers that create `profiles`, `storage.objects` RLS/ownership and signed-URL signing, PostgREST role switching and exposed-schema configuration, role-level `statement_timeout` (anon 3 s, authenticated 8 s), `pg_net`/Edge Function runtime and secrets, Realtime publications, the `extensions` schema search path of the `postgres` role in a branch, and PG 17 planner/behaviour differences. Anything touching these needs the hosted validation plan (`docs/HOSTED_VALIDATION_PLAN.md`) after explicit approval.

## 8. Recommended use (needs approval; not done)
Name the baseline with a timestamp earlier than `0001` in the Supabase CLI convention, never apply it to the existing staging (objects already exist — only a metadata `migration repair --status applied` would be appropriate there), and use it solely to seed a **branch** history. No branch was created in this round.

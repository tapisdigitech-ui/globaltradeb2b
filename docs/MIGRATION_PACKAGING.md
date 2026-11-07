# Migration packaging (Round 9 · B1)

LOCAL validation only. Nothing here was applied to a hosted project.

## Layout

```
supabase/
  config.toml                      # CLI config (db.major_version = 17, seed path, evidence-link verify_jwt = true)
  seed.sql                         # 14 approved categories (docs/CATEGORY_SEED.md)
  migrations/                      # <- what the Supabase CLI / Git integration reads. GENERATED, byte-identical copies
    20261107120000_baseline_reconstructed.sql
    20261107120100_supplier_foundation_and_contact_vault.sql       (0001)
    20261107120200_requirements_matching_lead_desk.sql             (0002)
    20261107120300_contact_vault_functions.sql                     (0003)
    20261107120400_claim_verification_and_invitations.sql          (0004)
    20261107120500_scope_claim_review_access.sql                   (0005)
    20261107120600_real_schema_hardening.sql                       (0006)
    20261107120700_function_hardening.sql                          (0007)
    20261107120800_sequence_privileges.sql                         (0008, new in Round 9)
  migrations_draft/                # reviewed source of truth; historical SQL untouched
    baseline/0000_baseline_reconstructed.sql, 0001 … 0008
    down/0001_down.sql … 0008_down.sql        # rollback files, NEVER copied into migrations/
  packaging/sync_cli_migrations.sh     # generate / --check the copies
  packaging/run_cli_chain.sh           # real-CLI validation against a throw-away local Postgres
```

Why copies and not a rename: the drafts keep their reviewed paths and hashes. `sync_cli_migrations.sh --check` fails if a copy differs, if one is missing, or if an unexpected file appears in `migrations/` (e.g. a down file).
Timestamps are 14-digit (`YYYYMMDDHHMMSS`), strictly increasing, one second-level step per file, so CLI ordering = intended ordering (baseline first). Names after the timestamp are `[a-z0-9_]+`.

## Commands

```bash
bash supabase/packaging/sync_cli_migrations.sh           # (re)generate migrations/
bash supabase/packaging/sync_cli_migrations.sh --check   # verify byte-identity, no extras
SUPABASE_BIN=/path/to/supabase bash supabase/packaging/run_cli_chain.sh   # local CLI validation (localhost only)
```

`run_cli_chain.sh` refuses any URL that is not `postgresql://postgres@localhost:…`. It: drops/creates a scratch DB → loads the **platform stand-in** (`baseline/local_platform.sql`: roles, `auth`, `storage`, `extensions`, which a real Supabase project already has) → `supabase db push --dry-run` → `db push --include-seed` → second push must report "up to date" → checks 9 rows in `supabase_migrations.schema_migrations` → re-runs `seed.sql` (idempotent) → compares the 13-kind catalogue fingerprint of the CLI-applied database with a database built by plain `psql` from `migrations_draft/`.

Result (Supabase CLI 2.122.1, local PostgreSQL 16.15): dry run lists the 9 files in order; push applies all 9 and the seed without error; second push `upToDate:true`; fingerprints **identical across all 13 kinds**; 66 public tables, 14 categories. Files containing their own `begin;`/`commit;` run fine under the CLI.

## Initialising an isolated branch when staging has no migration history

Fact (read-only catalogue check, Round 7/8): the staging project has **0 recorded migrations**, although its schema exists.
Supabase documents that a GitHub-integrated branch builds its schema from `supabase/migrations/` in the repository, while a branch created from the dashboard/MCP replays the *parent's recorded migration history* – which is empty here, so such a branch would be an **empty database**, not a copy of staging's schema. The schema is not cloned and a branch has no data unless seeded.

Therefore (proposal; nothing executed, no branch created):
1. Use the **Git-integrated** path, or push the chain explicitly: `supabase db push --db-url "<branch URL>"` from this repo. The baseline migration creates the whole pre-Phase-0 schema, 0001–0008 follow, then `seed.sql` supplies the 14 categories. The platform schemas (`auth`, `storage`, extensions, roles) come from the branch itself.
2. Never run the baseline against staging itself (objects already exist). If staging is ever to be brought under migration control, the baseline would be recorded **without executing** it (`supabase migration repair --status applied 20261107120000`), after a read-only fingerprint comparison proves the schemas equal. Not done, not requested.
3. Validate on the branch with the hosted checklist (docs/HOSTED_PG17_VALIDATION_CHECKLIST.md): the local replica is PG16 with a stand-in platform; the first branch apply is the first real-platform run.
4. Branch cost/lifecycle and the unconfirmed organisation plan (B6) are unchanged: docs/BRANCH_LIFECYCLE_COST_ASSESSMENT.md. A plan that supports branching must be confirmed before any branch is created.

## Not covered locally
`supabase start` (the full Docker stack) was not used; the CLI was exercised against the scratch Postgres with `db push --db-url`. Real GoTrue/Storage/PostgREST versions, the platform's own `extensions` placement and PG17 behaviour remain hosted-only.

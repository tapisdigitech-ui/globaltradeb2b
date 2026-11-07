# Free-Plan Deployment Strategy — GlobalTradeB2B

Status: **local work and documentation only. Nothing in this document has been executed against any hosted Supabase project.**
Constraint (permanent unless the owner changes it in writing): the organisation stays on **Supabase Free**. No upgrade, no paid branches, no paid compute, no paid add-ons, no resource that could incur charges without explicit approval.

Hosted contact so far this round: read-only catalogue `SELECT`s against staging (`lhmexhafyuzojrmcbtbz`) to compare its fingerprint with the local baseline. No writes, no migrations, no branches. Production, production-candidate and TAPIS KASA were not touched.

---

## 1. Recommendation (read this first)

1. **Do not apply migrations 0001–0008 to any hosted project yet.** Staging currently equals the reconstructed baseline exactly (13 of 13 catalogue kinds identical, 0 recorded migrations). That is a good, known starting point; keep it that way until a backup exists.
2. **Treat existing staging as the only hosted rehearsal target**, and only after (a) an encrypted, restore-tested backup, (b) the preflight in §7 passing, and (c) your explicit written approval for that specific run.
3. **Never use production-candidate (`globaltradeb2b`, ref `kwtveqzeayupwrxpwkce`) or any production project as a test environment.** `ops/guard_target.sh` refuses it by ref.
4. **Do almost all validation locally**: PostgreSQL 16.15 (fast suite) and PostgreSQL 17.11 (same minor as hosted), both already fully green. Close the remaining hosted-only gaps on **your own machine** with `supabase start` (Docker Desktop is free); that needs no Supabase plan at all.
5. **Set up your own scheduled, encrypted backups** — the Free plan has none (§5). This is the single most important risk reduction.
6. Blocker B6 (org plan unconfirmed) is **resolved as: Free plan, no branching**. The branching path in `docs/BRANCH_LIFECYCLE_COST_ASSESSMENT.md` and `docs/HOSTED_VALIDATION_PLAN.md` is superseded by this document.

## 2. Environment ladder

| # | Environment | Cost | What it proves | Status |
|---|---|---|---|---|
| 1 | Local PG 16.15 + platform stand-in (`baseline/local_platform.sql`) | free | SQL logic, RLS/ACL, triggers, concurrency, rollback, seed; fast suite (`tests/run_round9_all.sh`) | **green** |
| 2 | Local PG 17.11 via `ops/setup_local_pg17.sh` (npm embedded binaries, no Docker) | free | Same suite on the hosted major/minor; fingerprints identical to PG16 | **green** |
| 3 | `supabase start` on the owner's machine (Docker Desktop) | free | Real GoTrue/PostgREST/Storage/Edge runtime: real JWTs, PostgREST role switching, storage policies, Edge Functions | **not run — cannot run in this sandbox (no Docker daemon)** |
| 4 | Existing Free staging project | free (already counted) | Hosted-only behaviour (pooler, timeouts, quotas) | **read-only only, so far**; writes need approval |
| – | Production / production-candidate | — | — | **never a test target** |

A third hosted project is **not possible**: the organisation already has two active projects, the Free maximum (paused projects do not count). Creating one would fail or force a pause/upgrade, so it is out of scope.

### What PG17.11 local validation covered (all green)
Legacy 138; real-schema pre 55 / post-0006 361 / final 404 (also under classic default ACLs); concurrency 11/0; JWT-claims 43 + evidence-link 22; seed 18; sequence ACL 16/16; genuine-role sequence tests 28/28; mutation control 9 detected / 0 missed; Edge node tests 27; fingerprint-based rollback OK; Supabase CLI chain OK (9 migrations + seed, 13 kinds identical); proposal tests 30/14/9 (+ controls). PG16 and PG17 final-chain fingerprints are identical.
Re-run: `PGHOST=/tmp/pg17 PGPORT=5545 LOG=/tmp/round9_pg17 NO_PG_DUMP=1 SUPABASE_BIN=<cli> bash supabase/tests/run_round9_all.sh`.

### What local validation cannot prove (honest limits)
- Platform internals are a **stand-in**, not Supabase's own images: auth/storage schemas, GoTrue, PostgREST, realtime, pg_net/vault, platform event triggers.
- Hosted pooler behaviour, real statement timeouts (observed: anon 3 s, authenticated 8 s), egress and quotas.
- Anything in tier 3 until the owner runs it.
These are listed again as risks in §9. No local result should be described as a "Supabase test" or "staging test".

## 3. Free-plan limits that can affect the platform

Source: Supabase pricing/limits/billing/backup documentation, read this round. Figures can change; re-check before relying on them.

| Limit (Free) | Value | Effect on GlobalTradeB2B | Mitigation |
|---|---|---|---|
| Active projects per org | 2 | No third project; no hosted scratch DB | Use local ladder; staging is the sole hosted rehearsal target |
| Database size | 500 MB | Growth tables (audit/rate-limit/view events, evidence links, directory data) can fill it; exceeding → read-only / restrictions | Monitor size in preflight; retention/pruning policy before launch; keep rehearsals on synthetic data |
| Backups / PITR | **None** (paid only) | A bad migration or deletion is unrecoverable without our own dump | Own encrypted dumps (§5); restore drills |
| Inactivity | Paused after ~7 days of low activity | Staging/prod may pause (warning email ~1 week before); restore via "Resume project" within 1 year | Keep-alive option (needs approval); never rely on a paused project |
| Egress | 5 GB + 5 GB cached | Directory pages / exports could exhaust it | Cache, paginate, avoid bulk exports to clients |
| Storage | 1 GB, 50 MB per upload | Evidence/verification documents | Size caps already per bucket; compress; consider external object store later |
| Auth MAU | 50,000 | Not binding at pilot scale | Monitor |
| Edge Functions | 500,000 invocations; 256 MB; 150 s wall clock; 2 s CPU/request; 20 MB bundle (CLI); 100 functions | Fits current functions | Keep functions thin; heavy work in SQL/background |
| Realtime | 200 concurrent, 2 M messages/month, 256 KB msg | Not used for core flows | Avoid depending on Realtime |
| Log retention | 1 day | Incident forensics is weak | Persist security-relevant events in our own tables/exports |
| Support | Community only | No SLA | Own runbooks (this document) |
| Fair-use enforcement | Notification → grace period → restrictions (pause, read-only DB, HTTP 402) | Quota overrun can take the site down | Alerts at 70% of each quota; documented in operations runbook |
| Branching | Paid, billed hourly, not covered by Spend Cap | **Forbidden** by this constraint | Not used |

Operational note: Free is acceptable for development, staging and a private pilot. It is a **business risk for a public production launch** (no backups, pausing, no SLA). That is a decision for the owner and is not made here.

## 4. Reproducibility of migrations 0000–0008 (Supabase CLI)

- `0000` is the **baseline**: reconstructs the existing schema for fresh environments only. It must **never be executed against existing staging/production** (it is already there); it is *recorded* as applied with `migration repair`.
- `0001`–`0008` are the forward migrations, each with a tested down file.
- Verified locally with CLI 2.122.1: `supabase db push --db-url …` applies 9 migrations + seed on a clean PG16 and PG17.11 database and yields a catalogue fingerprint identical to the file-by-file result and to `ops/expected_fingerprints/after_0008.txt`.
- Not verifiable here: `supabase start` and `supabase db dump` (both need Docker). Owner-machine step, tier 3.

## 5. Backup and restore (existing Free-plan staging)

**Free has no automatic backups or PITR. A manual dump is the only safety net.** No dump has been taken of staging yet (that requires a connection with credentials, i.e. a hosted action needing your approval).

### 5.1 Taking the backup (owner machine; needs approval for the connection)
Prerequisites: Supabase CLI, Docker Desktop (CLI dump runs `pg_dump` inside a container, so the client matches the server major 17), a direct or **Session-pooler** connection string (not the transaction pooler). Keep the connection string out of the repo and shell history.

```bash
supabase db dump --db-url "$STAGING_DB_URL" -f roles.sql  --role-only
supabase db dump --db-url "$STAGING_DB_URL" -f schema.sql
supabase db dump --db-url "$STAGING_DB_URL" -f data.sql --use-copy --data-only \
    -x "storage.buckets_vectors" -x "storage.vector_indexes"
# migration history is a separate schema:
supabase db dump --db-url "$STAGING_DB_URL" -f history.sql --schema supabase_migrations
```
Then **encrypt immediately** and keep only encrypted copies, off-site, outside the repo:
```bash
openssl enc -aes-256-cbc -pbkdf2 -salt -in data.sql -out data.sql.enc    # or age/gpg; passphrase in a password manager
```
Also record separately: the storage **objects** (not in the dump; Storage API/script), auth/storage customisations, Edge Function secrets, vault keys, custom role passwords. `.gitignore` already blocks `*.dump`, `*.dump.enc`, `*.sql.enc`, `*.age`, `supabase/ops/backups/`.

Caveats from the official procedure: comment out `ALTER … OWNER TO "supabase_admin"` in `schema.sql` and the `GRANT "postgres" TO "cli_login_postgres"` line in `roles.sql` before restoring; `DROP ROLE IF EXISTS cli_login_postgres`; enable required extensions first; re-enable Realtime publications.

### 5.2 Restore
Into a **new, empty database** (local PG17 or `supabase start` first — a drill — and only then, if ever, into hosted):
```bash
psql --single-transaction --variable ON_ERROR_STOP=1 \
     --file roles.sql --file schema.sql \
     --command 'SET session_replication_role = replica' --file data.sql \
     --dbname "$TARGET_DB_URL"
```
Verify with the fingerprint (§7.2). A restore that has not been fingerprint-verified is not a recovery.

### 5.3 Rehearsal done this round (synthetic data only)
`ops/rehearse_backup_restore.sh`: PG16 source with synthetic fixtures + seed → `pg_dump -Fc` → AES-256 encrypt (throwaway passphrase) → decrypt → restore into a fresh PG17.11 database → verify. Result: columns, constraints, enums, function bodies and ACLs, indexes, sequences, table flags and views identical; effective ACLs identical for all 85 relations (raw sequence ACL text differs only as explicit owner-only vs NULL default — equivalent); row counts equal.
**Gaps found in a `public`-only dump** (hence the full dump set above is mandatory): 8 `storage.objects` policies, 5 `storage.buckets` rows, 1 `auth.users` trigger are outside `public` and were not restored. `profiles.id` has an FK to `auth.users`, so auth data must be restored first.

### 5.4 Standing backup routine (proposal — not enabled)
Weekly (and before every migration) encrypted dump to off-site storage, plus a monthly restore drill. Scheduling it is a standing configuration change and needs your approval.

## 6. Data protection
- Real supplier/buyer data is never used in tests, rehearsals, fixtures, logs or commits. All local data is synthetic.
- Dumps contain real data once taken from staging/production: encrypted, off-repo, access-limited, deleted per retention policy. A restore drill on a developer machine uses **masked** data, not a raw production dump.
- Credentials never in chat, repo or shell history; `ops/guard_target.sh` and `.gitignore` are guard rails, not a substitute for care.

## 7. Staged migration procedure (staging only, after approval)

Helper scripts (all in `supabase/ops/`): `preflight_fingerprint.sql` (one read-only SELECT), `verify_fingerprint.sh RESULT EXPECTED` (text compare, touches nothing), `guard_target.sh` (refuses anything but staging, and refuses without `I_HAVE_WRITTEN_APPROVAL=yes`), `expected_fingerprints/{baseline_only,after_0001…after_0008}.txt`.

### 7.1 Preflight (read-only; may run once approved)
1. `PROJECT_REF=lhmexhafyuzojrmcbtbz I_HAVE_WRITTEN_APPROVAL=yes bash ops/guard_target.sh` → must print OK.
2. Confirm the project is **active (not paused)** and the plan is Free; do not click anything that changes plan/compute.
3. DB size well under 500 MB (headroom ≥ 100 MB for the migrations).
4. Recorded migrations: expect none (or exactly what the previous step produced).
5. Run `preflight_fingerprint.sql` → compare with `expected_fingerprints/baseline_only.txt` (or the `after_000N` of the last applied step). **Any difference stops the procedure.**
6. Categories seed: check read-only that no row collides on id/slug (the seed guard fails loudly on collision).
7. **Backup taken, encrypted, restore-drilled** (§5). No backup → no migration.

### 7.2 Apply, one migration at a time
For N = 1…8, each on the **direct connection**, never the transaction pooler:
1. `psql --single-transaction -v ON_ERROR_STOP=1 -f migrations/000N_*.sql`
2. Run the fingerprint SELECT; `verify_fingerprint.sh` against `after_000N.txt`. Mismatch → stop, go to §8.
3. `supabase migration repair --status applied <version>` (history recorded only after verification).
Before step 1 of the first run: `supabase migration repair --status applied 0000` (baseline recorded, **not executed**).
After 0008: seed categories (§7.1 item 6), run the post-checks (RLS enabled on all tables, no unpinned `search_path` in definer functions, advisor report), re-take a backup.

### 7.3 Pause points
Stop and report after each migration if anything differs; never "fix forward" on staging without approval.

## 8. Rollback and recovery ladder
| Tier | When | Action | Notes |
|---|---|---|---|
| 0 | Failure inside a migration | None needed: `--single-transaction` rolls it back | Verify with fingerprint = previous `after_000N` |
| 1 | Migration committed but wrong | Apply that migration's tested down file(s) in reverse order | Local result: 0008 down leaves 7 identity-sequence ACL items "NULL → explicit owner-only" (equivalent); rolling back everything leaves 3 function-body items differing by whitespace only. Re-apply is identical. |
| 2 | Down file insufficient | Restore from the encrypted dump into the **same** staging project (§5.2) | Destructive; needs approval; restore drilled locally first |
| 3 | Staging unrecoverable | Reset/recreate staging from baseline + backup | Destructive; needs approval; counts against the 2-project limit while both exist |
| – | Paused project | "Resume project" in dashboard (within 1 year) | Data retained; verify fingerprint after resume |

There is no provider-side recovery on Free. Tiers 2–3 depend entirely on our own backups.

## 9. Risks and limitations
| # | Risk | Likelihood / impact | Treatment |
|---|---|---|---|
| R1 | No backups/PITR on Free | Certain / High | Own encrypted dumps before every change; routine proposed |
| R2 | Local stand-in ≠ hosted platform | Medium / Medium | Tier 3 on owner machine; staging read-only fingerprint equals baseline |
| R3 | Docker-only CLI dump cannot run in this sandbox; local PG17 has no `pg_dump` 17 | Certain / Low | Dump runs on owner machine; `pg_dump` must be ≥ server major (17) |
| R4 | Project pause after 7 idle days | Medium / Medium | Keep-alive (approval needed); runbook for resume |
| R5 | 500 MB DB cap with growth tables | Medium / High at scale | Size check in preflight; retention policy |
| R6 | Fair-use restrictions (read-only, 402) on quota overrun | Low–Med / High | Alerts, caching, pagination |
| R7 | Wrong target (prod-candidate) | Low / Severe | `guard_target.sh`; written approval; never share prod-candidate credentials with tooling |
| R8 | Public-only dump misses storage/auth parts | Certain if misused / Medium | Full dump set + diff (§5.3) |
| R9 | Down-migration differences (ACL representation, whitespace) | Known / Low | Documented, equivalent |
| R10 | Hosted-only items unverified (real JWT round-trip, PostgREST, Storage, Edge runtime) | Certain / Medium | Owner-machine `supabase start`; staging smoke test after approval |
| R11 | 1-day log retention | Certain / Medium | Persist security events ourselves |
| R12 | Free plan for public production | Business decision | Owner decides; not assumed here |

## 10. Actions that require your explicit approval (none have been taken)
1. Any hosted connection that is not a read-only catalogue SELECT (including taking a dump of staging).
2. Applying any migration or seed to staging, or `migration repair` on any project.
3. Restoring a dump into any hosted project; resetting/recreating staging.
4. Enabling scheduled backups or a keep-alive; any new project, branch, add-on, compute change, plan change.
5. Anything involving production-candidate, production or TAPIS KASA (default answer: no).

## 11. Suggested next steps (in order)
1. You run, on your machine: `supabase start`, apply the chain, run the JWT/PostgREST/Storage/Edge checks (tier 3) — free, no hosted effect.
2. You approve a **staging backup** (§5.1) and a restore drill into local PG17/`supabase start`.
3. Only then, you approve a staging migration run following §7, one migration at a time.

## 12. Appendix: artefacts
`supabase/ops/`: `setup_local_pg17.sh`, `preflight_fingerprint.sql`, `verify_fingerprint.sh`, `guard_target.sh`, `rehearse_backup_restore.sh`, `expected_fingerprints/*`. `supabase/tests/rollback_fingerprint.sh` (pg_dump-free rollback check). `tests/run_round9_all.sh` now honours `PGHOST`, `PGPORT`, `LOG`, `NO_PG_DUMP`.

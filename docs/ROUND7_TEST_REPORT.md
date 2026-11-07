# Round 7 test report — local function hardening and reconstructed baseline

**Scope: LOCAL ONLY.** PostgreSQL **16.15** (Ubuntu), disposable cluster. Hosted Supabase runs **PostgreSQL 17.11**; nothing here was run on, or applied to, Supabase (no branch, no staging migration, no production, TAPIS KASA untouched, no email/SMS/invitations sent, demo UI not connected to data). Staging was used only for read-only catalogue `SELECT`s. Base commit `3e213a3`; the Round 7 commit SHA is given in the hand-off message (a file cannot contain its own SHA).

## 1. Results (final run, fresh databases)
| Suite | Result |
|---|---|
| Legacy synthetic suite (`tests/run_all.sh`, its own older reconstruction, 0001–0005) | **138 pass / 0 fail** |
| Baseline from empty DB → real suite `pre` (baseline only; exposure controls) | 55 pass, 41 EXPOSED markers (expected: reproduces known gaps), 0 fail |
| Baseline + 0001–0006 (`post6`, records ORIGINAL behaviour of F1–F10 as regression controls) | **361 pass / 0 fail** |
| Baseline + 0001–0007 (`post`, corrected behaviour, all roles) | **404 pass / 0 fail** |
| Edge Function handler tests (`node --test`) | **11/11** |
| Concurrency (`tests/concurrency_0007.sh`, parallel psql sessions) | **11/11** |
| Admin-audit proposal tests (separate, unapplied) | control 2/2, proposal 26/26 |
| Rollback/re-apply (`tests/dry_run_0007.sh`, `tests/dry_run.sh`) | see §4 |

Counts are `PASS` lines from each runner. The suite includes evidence audit/rate-limit tests (EL1–EL16) and SF1–SF25.
PG16-vs-PG17: all numbers are PG 16.15. Differences expected on PG 17 (planner, `MAINTAIN` privilege, hosted role settings, platform-managed schemas) are **not** validated.

## 2. The fixes (F1–F10): threat, decision, tests, rollback
Each has a `post6` test recording the original behaviour and a `post` test of the corrected one (names SF7…SF25 in `tests/real_schema_tests.sql`; concurrency C1–C7).
| # | Threat / failure scenario | Fix and business decision | Contexts tested | Rollback implication |
|---|---|---|---|---|
| F1 | Invite row with NULL expiry never expires (`NULL < now()` is NULL): a leaked invite works forever | NULL = expired; check constraint (NOT VALID, so existing rows are not scanned) for pending invites. **Decision:** legacy NULL-expiry pending invites become unusable until re-issued; they cannot be updated without setting an expiry | anon, service_role (uid NULL), admin non-invitee, invitee; 3-way parallel accept → 1 membership | down drops constraint, restores body; no data change |
| F2 | Repeating a request creates unlimited duplicate companies and burns the rate limit | Idempotent per creator on name+city (case/space-insensitive) while a request is open; returns existing id before the rate limit. **Decision:** cross-user duplicates are not blocked (a second claimant is legitimate; blocking would leak existence) → staff dedupe | anon, service_role, same user, other user; 8 parallel calls → 1 company | down restores body; created companies remain |
| F3 | Foreign product attached to a correction of another company; `javascript:`/`data:`/`file:` URLs stored | Product must belong to the company; URL must be `http(s)://` non-space, ≤500 chars (blank → NULL); table check NOT VALID. **Decision:** reject (not silently truncate) | anon, service_role, buyer; 9 unsafe URL forms, upper-case scheme, blank | down drops check; stored rows stay |
| F5 | Imports left no operator audit | Immutable `company_import_audit` (apply/rollback, actor, counts); admin-read only; no FK | admin, reviewer, buyer, anon; immutability; 3 parallel applies → 3 rows / 2 companies | down drops the table (import audit history under 0007 lost; export first) |
| F6 | Rollback silently cascaded away lead matches | Refuse if companies have lead matches or quotations; lock batch + company rows (blocks concurrent match inserts); repeat rollback is a no-op. **Decision:** refusal rather than archiving matches | admin, reviewer, buyer, service_role; concurrent match insert vs rollback; apply‖rollback coherent | down restores body |
| F7 | Expiry update undone by the exception that followed; NULL uid passed `<>` | Returns `'expired'` and persists it; `IS DISTINCT FROM`; explicit NULL-uid refusal. **Decision:** API change void→text and an expired response no longer raises (callers must handle the value) | anon, service_role, admin, reviewer, seller, buyer; parallel accept‖decline → one wins | down drops/recreates as void with same ACL; rows already `expired` stay |
| F8 | Order from a lapsed quote or an ineligible supplier; NULL uid; race | Row lock; validity date (`valid_until` null or ≥ today) and supplier eligibility (claim approved, not paused/rejected/suspended, verification not rejected/expired) rechecked. **Decision:** acceptance does not extend validity for ordering | anon, service_role, admin, reviewer, seller, buyer; 4 parallel orders → 1 | down restores body |
| F9 | `digest()`/`gen_random_bytes()` unqualified; pgcrypto is in `extensions` on hosted → 4 functions fail | `extensions.` qualification | buyer call; source scan | down restores unqualified bodies |
| F10 | My 0006 `import_normalize` regex `\\.` rejected every normal website | Restored `\.` | admin import | down restores the 0006 (faulty) body |

## 3. Admin message-read audit
Proposal only: `docs/ADMIN_MESSAGE_AUDIT_PROPOSAL.md`. Not part of any suite or migration.

## 4. Rollback and re-application
- 0007: apply → down → pg_dump diff vs pre-0007 **0 lines**, 13-kind catalogue fingerprints **0 differences**; re-apply → identical to first apply (0 / 0). Down and re-apply also succeed on a database holding suite data (including a legacy NULL-expiry invite).
- Rolling back everything (0007…0001): raw pg_dump differs by 25 whitespace-only lines in function bodies; **normalised comparison** (whitespace collapsed, statement-by-statement) shows 0 statements only-in-base / 0 only-in-rolled-back, order-insensitive equal = True. `0006_down.sql` was **regenerated** this round because the old one restored a stale `import_normalize` body (the F10 regex); 0006-only rollback diff is 0 lines.
- Proposal 0008 rollback: 0-line diff.

## 5. Remaining limitations
Local PG16 and a platform stand-in, not hosted PG17/Supabase; baseline equivalence only for the 13 fingerprint kinds (see BASELINE_RECONSTRUCTION_REPORT.md); categories seed data absent; refusals by non-admins are unaudited by design; signed evidence URLs irrevocable once issued; other URL columns not scheme-checked; NOT VALID constraints leave legacy rows unvalidated (run `VALIDATE CONSTRAINT` after data clean-up); production count of legacy NULL-expiry invites unknown (could be checked read-only with a count query, not done); UI/API callers of `respond_quotation` need to handle the text result.

**Stopped after local validation. Waiting for explicit approval before any hosted step.**

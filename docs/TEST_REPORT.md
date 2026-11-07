# TEST REPORT

## Environment (exact)
* PostgreSQL 16.15 (Ubuntu 24.04 package), disposable local cluster, port 5544. **Not Supabase, not staging.**
* Baseline = `supabase/tests/baseline_reconstructed.sql`: rebuilt from the read-only catalog queries run on staging on 2026-11-07 (columns, enums, function signatures, the recorded policy predicates, grants, storage policy names). Real bodies were used for `is_admin`, `is_staff`, `seller_can_see_leads`, `lead_matches_my_company`, `staff_mark_enquiry`. Everything marked `GUESS` in that file (other helper functions, `submit_claim`/`review_claim` bodies, view definitions, several policy predicates, storage table shape, absence of existing triggers/constraints/indexes) is a stand-in.
* Run: `supabase/tests/run_all.sh` (fresh DB → baseline → migrations 0001–0005 → `0002_full_test.sql`); rollback/diff: `supabase/tests/compare_and_rollback.sh`; raw output: `supabase/reports/test_run_output.txt`.

## Result
**138 assertions PASS, 0 FAIL** (58 are explicit negative controls, marked `NEG`). Status for all of it: **Implemented + locally tested against a reconstructed baseline. NOT staging verified. NOT applied anywhere.** These results say nothing about the real staging schema until the migration-compatibility run on the real schema-only dump (blocker B1).

| Requirement area | Examples of what was executed | Result |
|---|---|---|
| Verified-only routing | S1 verified seller → direct; S3 claimed-not-verified, S4 verified-but-phone-unverified, restricted seller → admin route; suspended / no-category companies not matched | pass |
| Negative: unverified sellers | C2/C4/C5/C6 members see 0 enquiries, 0 details, 0 matches, 0 events; legacy helpers `seller_can_see_leads()` / `lead_matches_my_company()` return false | pass |
| Unclaimed → admin | unclaimed supplier only in admin route + `unclaimed_matches` lead case; never delivered | pass |
| Unmatched queue | no supplier ≥ min score → `unmatched` case + `no_match` event; buyer message says no supplier has received it | pass |
| Scenario 6 | company verified later: no access until admin rematch, then delivered and visible | pass |
| Revocation | admin restriction, withdrawn verification, 400-day-old contact verification each remove access immediately; restored when conditions met | pass |
| Scenario 7 / duplicates | repeated rematch → no extra deliveries, events or notifications; duplicate requirement within 24 h rejected | pass |
| Staff assignment isolation | unassigned staff see 0 enquiries/cases/buyer-private rows; assigned staff see exactly their lead; second staff cannot update/read it; only admin assigns | pass |
| Contact vault | direct SELECT/INSERT denied; read needs purpose + assignment (case matched via *admin route*) + logs actor, company, purpose, related case/claim; denied attempts log nothing; do-not-contact value withheld, only admin clears; log immutable (update/delete blocked even for superuser) | pass |
| Claim verification | token/OTP hashed; code never returned; outbox service-role only; wrong code, 5-attempt lockout, expiry, rate limit, other user denied, approval blocked until email verified, conflicting open claim blocks approval, approval ≠ verification | pass |
| Invitations | one active per company, DNC refused, needs admin approval, manual delivery stays `logged_manual`, other staff denied, token single use, redeem approves nothing | pass |
| Reviewer scope | reviewers see only open claims and their verification documents (storage policy); decided claims hidden; admin sees all | pass |
| Privilege escalation / grants | buyer cannot insert matches/cases, change settings, call admin/staff/internal functions; anon cannot read any new table or execute any new function; internal functions not executable by authenticated; all new SECURITY DEFINER functions pin `search_path` | pass |
| Public surface | `public_companies` columns identical to recorded list; no public view exposes new/private columns | pass (stand-in view) |
| Rollback | up 0001–0005 then down 0005–0001 → `pg_dump --schema-only` identical to baseline | pass |

## Not tested / cannot be tested without the real schema
Real triggers (`guard_*`, `notify_on_enquiry`, `audit_changes`), real `submit_claim`/`review_claim`/`reveal_buyer_contact`/`respond_to_lead`/`submit_enquiry` bodies, the six real `public_*` view definitions, real constraints/indexes, `cev_read` policy, profile role-escalation guard (`guard_profile_role`), real Storage behaviour, Supabase Auth integration, concurrency/load. No frontend is connected to any of this. No staging or production SQL was executed in this phase.

## Frontend (prototype) — executed earlier
Playwright 360–2560 px, zero horizontal overflow; For Buyers flow desktop + mobile. Demonstration data only.


## Update 2026-11-07 — real-schema replica (LOCAL, not staging)
See `REAL_STAGING_AUDIT.md`. Legacy suite still 138 PASS (reconstructed baseline). New `tests/run_real.sh pre|post` runs on a local PG16 replica built from a read-only staging schema extract: pre-0006 = 35 PASS with ten exposure controls recorded; post-0006 = 61 PASS / 0 FAIL. Rollback of 0006 verified by zero schema+grant diff. None of this ran on staging.


## Update (round 2) — LOCAL clone of real schema
Pre-0006 42 pass (controls exposed); post-0006 107 pass / 0 fail; rollback diff 0 lines; competing-claim block now tested on the real-schema clone. Not Supabase, not staging. See REAL_STAGING_AUDIT.md Revision 2.


## Update (round 3) — LOCAL clone of real schema, PG16
Pre-0006: 54 pass, 15 exposure controls. Post-0006: 157 pass / 0 fail / 0 exposed. Rollback (with and without data): 0 diff lines. Not Supabase, not staging. See REAL_STAGING_AUDIT.md Revision 3.

## Round 4 (local replica, not Supabase)
Legacy 138 PASS; real-schema post 258 PASS/0 FAIL; pre 54 PASS, 40 exposed controls; Edge Function unit tests 9/9; rollback 0006 diff 0 lines.

## Round 5
Rollback 0006..0001: statement-level comparison after whitespace normalisation = identical (1302 statements, 0 only-in-either); the 25 raw diff lines were newline/indent differences in three function bodies. BC0 reproduced on original replica (`supabase/tests/bc0_original_policy_repro.sql`). Edge Function tests 13/13. Real-schema post 258 PASS/0 FAIL.

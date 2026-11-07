# Staging Compatibility Checklist — migrations 0001–0005

> **Real staging compatibility has NOT been verified.** Nothing here has been run against the real staging schema (`lhmexhafyuzojrmcbtbz`). All passing tests so far ran on a scratch PostgreSQL 16 database built from a *reconstructed* baseline (`supabase/tests/baseline_reconstructed.sql`) that contains guessed stand-ins for objects whose real definitions were not available. No migration may be applied to staging until every box below is ticked against an **actual schema-only dump** and the user approves.

Prerequisite (blocker B1): a schema-only staging dump (`supabase db dump --schema-only`; no data, no keys), restored into a disposable local Postgres.

## 1. Existing objects each migration depends on
| Mig | Existing objects it references or alters | What to confirm in the real schema |
|---|---|---|
| 0001 | tables `companies`, `categories`; functions `is_staff()`, `is_admin()`, `has_company_role()`, `block_mutation()`; type/column `source_type`; adds `categories.parent_id`, new `subcategories`, `company_contacts`, `contact_access_log`; adds columns + a CHECK constraint (`companies_business_types_valid`) to `companies` | column names/types; no name clashes with the new columns/tables; `categories.id` is integer; `block_mutation()` exists with a trigger-compatible signature; existing CHECKs/triggers on `companies` don't reject the new columns' defaults |
| 0002 | `enquiries`, `enquiry_private`, `companies`, `has_company_role()`, `is_staff()`, `is_admin()`, `check_rate()`; **drops and recreates policies** `enq_leads_read`, `enq_staff_read`, `enq_staff_upd` (on `enquiries`) and `epriv_read` (on `enquiry_private`); redefines `seller_can_see_leads`, `lead_matches_my_company`, `staff_mark_enquiry`; creates enums `lead_status`, `match_route`; new tables/functions listed in `MIGRATION_IMPACT_REPORT.md` | real bodies/signatures of the three redefined functions (callers, dependent policies, grants); the dropped policies' real predicates (are any behaviours lost?); `enquiries.kind`/delivery enum values used by `_match_requirement`; existing triggers on `enquiries` (e.g. `notify_on_enquiry`) still fire correctly with the new rows; no existing object already named like the new ones |
| 0003 | 0001 `company_contacts`, `contact_access_log`; `is_staff`, `is_admin` | functions `staff_add_contact`, `staff_get_contacts`, `staff_set_contact_status` don't collide; direct privileges on both tables revoked from `anon`/`authenticated` |
| 0004 | `company_claims`, `companies`, 0002 `lead_cases`, 0001 `company_contacts`; new `claim_verifications`, `claim_verification_outbox`, `claim_invitations`; trigger `company_claims_approval_gate` BEFORE UPDATE OF status | existing triggers on `company_claims` (ordering/duplication with the gate); real `submit_claim`, `review_claim` and `set_verification` bodies (blocker B2) — the gate must not break an existing legitimate path, and `set_verification` must not be bypassable |
| 0005 | **drops and recreates** policy `claims_read` on `company_claims` and Storage policy `vd_read` on `storage.objects`; new `staff_can_review_claim` | the real predicates of both dropped policies (anything lost, e.g. owner/seller read access?); other `storage.objects` policies for bucket `verification-docs`; **`cev_read` on `company_claim_evidence` is not changed and may still expose evidence rows more widely than reviewers should (blocker B3)** |

## 2. Policies, triggers, functions and views to inspect (real schema)
- [ ] All RLS policies on: `companies`, `company_private`, `company_claims`, `company_claim_evidence`, `company_verification_reviews`, `enquiries`, `enquiry_private`, `storage.objects`. Diff real vs. reconstructed.
- [ ] All triggers on `companies`, `company_claims`, `enquiries` (incl. guard triggers and `notify_on_enquiry`); check execution order vs. new triggers.
- [ ] Bodies, `SECURITY DEFINER` flag, `search_path` and EXECUTE grants of: `is_staff`, `is_admin`, `has_company_role`, `block_mutation`, `check_rate`, `submit_enquiry`, `reveal_buyer_contact`, `respond_to_lead`, `seller_can_reply`, `submit_claim`, `review_claim`, `set_verification`.
- [ ] Default privileges / `anon`+`authenticated` table grants on every new table (must be none for vault, audit, outbox and verification tables).
- [ ] Indexes and foreign keys: confirm new FKs target existing PKs with matching types; confirm no duplicate/redundant indexes.
- [ ] `notify_*` triggers or Edge Functions that could send email/SMS when new rows are inserted — notifications must stay disabled.

## 3. Claim-evidence access requirements
- [ ] Reviewer sees evidence only for claims assigned to them (`staff_can_review_claim`); unassigned staff see none; sellers see none beyond their own claim.
- [ ] Table `company_claim_evidence`: decide and implement the `cev_read` scope (B3) — currently unchanged.
- [ ] Storage bucket `verification-docs`: private; `vd_read` replaced by 0005 scoping; confirm no signed-URL path bypasses it; confirm other storage policies (insert/update/delete) don't widen access.
- [ ] Each evidence view should be audit-logged (not implemented for evidence yet — design gap).

## 4. Security-definer view review (six `public_*` views, `security_invoker=false`)
Run `supabase/tests/check_public_views.sql` against the real schema and for each view record: purpose, source tables, exposed columns, filters (e.g. published only), and confirm that **no** column from `company_private`, `company_contacts`, `enquiry_private`, `lead_cases` or claim/verification tables is exposed.
- [ ] view 1 … [ ] view 6 (names to be filled from the real dump)
- [ ] Confirm new 0001 columns (e.g. `lead_delivery_blocked`) are **not** auto-exposed by any `select *` view.
- [ ] Decide whether to convert to `security_invoker=true` (separate change; not part of 0001–0005).

## 5. Required negative tests against the real staging schema (disposable local copy)
1. Unverified, unclaimed and claimed-but-unverified companies never receive direct leads (`seller_lead_visible`, `seller_can_see_leads`, `_company_lead_eligible`).
2. Verified company with unverified phone, stale contact (>365 days) or `lead_delivery_blocked` gets no direct lead.
3. Staff A cannot read staff B's leads, unrelated enquiries, `enquiry_private`, or claim evidence.
4. Reviewer cannot read unassigned claims or evidence; cannot approve with competing open claims or unverified email.
5. `anon` and `authenticated` cannot select/insert/update/delete `company_contacts`, `contact_access_log`, `lead_status_history`, `lead_distribution_events`, `claim_verification_outbox`.
6. `staff_get_contacts` without purpose fails; with purpose writes one immutable audit row (UPDATE/DELETE on the log fail, even for admin).
7. Duplicate requirement submission is rejected (`create_requirement` + `check_rate`).
8. Privilege escalation: member of company X cannot call staff/admin functions; staff cannot call `admin_*`; direct `UPDATE company_claims SET status='approved'` is blocked by the gate.
9. Existing public flows still work: `submit_enquiry`, `submit_claim`, public views, seller inbox for genuinely verified sellers.
10. Rollback: apply 0001–0005, run suite, apply down scripts in reverse, diff schema against the pre-migration dump (expect identical).

## 6. Sign-off
| Item | Done | Evidence |
|---|---|---|
| Real schema-only dump obtained and restored locally | ☐ | |
| Migrations 0001–0005 apply cleanly | ☐ | |
| Existing policies/functions diffed vs. reconstructed baseline | ☐ | |
| Six views reviewed | ☐ | |
| Negative tests 1–10 pass | ☐ | |
| Rollback diff clean | ☐ | |
| Blockers B2, B3, B4 resolved | ☐ | |
| Explicit user approval to apply to staging | ☐ | |

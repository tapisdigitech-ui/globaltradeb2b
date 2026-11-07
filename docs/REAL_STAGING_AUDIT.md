# REAL STAGING SCHEMA AUDIT (migrations 0001–0006 DRAFT)

**Status: nothing in this document has been applied to staging or production.** All SQL executed against the staging project was read-only catalog `SELECT`s (no table data, no writes, no secrets). Everything else ran on a disposable **local PostgreSQL 16** database built from that extract.

## 1. Environments (what each result ran against)
| Label | What it is |
|---|---|
| **STAGING (read-only)** | Project `globaltradeb2b-staging` (`lhmexhafyuzojrmcbtbz`, PG 17.11). Only catalog `SELECT`s: tables, columns, constraints, indexes, function bodies, triggers, policies, grants, views. |
| **LOCAL REPLICA** | Local PG16 scratch cluster, schema rebuilt from the extract (`supabase/staging_schema/`, git-ignored). Stubs: `auth`/`storage` platform schemas and 16 unrelated RPC bodies. Differences from real: PG16 vs PG17, no Supabase Auth/Storage services. |
| **LOCAL RECONSTRUCTED** | Earlier stand-in baseline (`tests/baseline_reconstructed.sql`), 138 legacy assertions. |
No test in this report ran against staging.

## 2. Schema compatibility findings (real vs. assumptions)
* 46 public tables, all `ENABLE + FORCE RLS`; 97 public + 8 storage policies; 41 triggers; 6 views.
* Migrations **0001–0005 apply cleanly** to the replica (no conflicts with existing names, enums, constraints).
* Real function bodies differ from what 0001–0005 assumed; the following gaps exist in the REAL schema (tested as controls on the replica after 0001–0005 only):

| ID | Gap in real staging | Control result (replica, 0001–0005) | After 0006 |
|---|---|---|---|
| F-R1 | `respond_to_lead` / `reveal_buyer_contact` / `seller_can_reply` accept any claimed+published member in the category; reveal needs only a prior response | **EXPOSED** (E1, E2): unverified seller responds then reveals buyer name/phone/email | closed: eligibility re-checked at access time + delivery (`seller_match_visible`) |
| F-R2 | `notify_on_enquiry` notifies every claimed+published seller of every new requirement | **EXPOSED** (E3) | closed: no requirement notifications; awaiting_admin → admins only |
| F-R3 | `submit_enquiry` marks product enquiries `visible_to_seller` for unverified sellers | by inspection; E3 covers visibility | verified-only, honest delivery notice |
| F-R4 | `guard_company_columns` does not protect `lead_delivery_blocked`/`is_demo`; owners hold column UPDATE | **EXPOSED** (E4): restricted seller clears own restriction | closed |
| F-R5 | `review_claim` — any staff can decide any claim | **EXPOSED** (E10) | assignment-based (`claim_reviewer_assignments`) |
| F-R6 | `cev_read` = claimant OR any staff; storage `vd_read` likewise; no read audit | **EXPOSED** (E8, E9) | claimant-only direct access; staff via audited RPC + short grant |
| F-R7 | `company_private` (phone/email/address) readable/writable by all staff | **EXPOSED** (E6) | owner/manager only |
| F-R8 | `profiles_self_read` — all staff read all profiles (buyer phones) | **EXPOSED** (E7) | own / admin / staff-role rows only |
| F-R9 | New tables lacked `FORCE RLS` used by all existing tables | by catalog | forced |
Not exposed on the replica (controls): other-company seller reading `company_private` (E5), anon access to functions/tables, buyer/seller privilege escalation attempts.

## 3. Existing functions inspected (real bodies)
`reveal_buyer_contact`, `respond_to_lead`, `seller_can_reply`, `submit_enquiry`, `submit_claim`, `review_claim`, `set_verification`, `notify_on_enquiry`, `create_requirement`, `buyer_requirement_status`, `staff_can_access_company`, `staff_can_review_claim`, `staff_get_contacts`, `staff_set_contact_status`, `admin_rematch*`, `guard_company_columns`, `guard_enquiry`, `guard_member`, `is_staff`, `is_admin`, `has_company_role`, `is_trusted_session`, `check_rate`, `block_mutation`. All SECURITY DEFINER functions pin `search_path = public, pg_temp`. Default ACLs grant ALL to anon/authenticated/service_role on new objects — every new function/table in 0006 revokes and re-grants explicitly (tested: anon cannot execute `reveal_buyer_contact`, `respond_to_lead`, `review_claim`, `set_verification`).

## 4. The six security-definer public views (`security_invoker=false`, owner `postgres`)
| View | Filter | Exposes | Notes |
|---|---|---|---|
| `public_companies` | `directory_status='published'` AND `data_review_status='approved'` | id, slug, name, business_type, about, city, state, country, website, logo_path, `public_label`, is_claimed, is_verified, data_as_of, updated_at | No contacts, no claim/owner data. Label derived from verification/claim status. |
| `public_company_categories` | joins `public_companies` + non-hidden category | company_id, category_id | |
| `public_company_images` | published company, image `approved` and rights in owned/licensed/permission_granted/public_domain | id, company_id, path, position | |
| `public_company_sources` | published+approved company; excludes `direct-submission:%` URLs | field_name, source_type, source_name, source_url, collected_at, last_checked_at | Source URLs are public by design (provenance). |
| `public_products` | product published+approved, company in `public_companies`, non-hidden category | product fields, `source_name/url`, company slug/name/label | No contacts. |
| `public_product_images` | product in `public_products`, `public_path` set, approved, rights ok | id, product_id, public_path, position | |
All six: SELECT-only grants to anon/authenticated; column-name scan for phone/email/contact/private/etc. returned **0 rows** on the replica both before and after 0006; none of the 0001–0006 objects add columns to them. 0006 does not alter any view.

## 5. Claim evidence decision (`cev_read`)
* Table `company_claim_evidence`: direct SELECT = **claimant only**. Staff have no direct table path.
* Staff read through `staff_open_claim_evidence(claim, purpose)` (SECURITY DEFINER): requires admin, or reviewer **assigned** to an **open** claim; purpose ≥5 chars; writes an immutable row to `claim_evidence_access_log` (actor, claim, company, purpose, count, time) and a 10-minute grant in `claim_evidence_grants`.
* Storage `vd_read` (bucket `verification-docs`): claimant OR active grant for that claim → the file itself is unreadable without a prior logged RPC call.
* Assignment: `admin_assign_claim_reviewer` (admin only); `review_claim` and `staff_can_access_company` use assignment.
* Admin reads all claims but also through the logged RPC.
Tested (replica): assigned reviewer reads via RPC + object after grant; unassigned reviewer, and the assigned reviewer for the *other* claim, denied (RPC, rows, storage); direct table read by staff denied; log forgery/update/delete denied (even admin); every RPC read logged; claimant reads own, other claimant denied.

## 6. Business rules implemented (configurable in `lead_routing_settings`)
365-day freshness, cap 5, verified email AND phone required; approved claim + verified + published + not `lead_delivery_blocked` + active member + category match for direct delivery; unclaimed / claimed-unverified → admin desk; suspended never matched; delivery re-checked on seller access; duplicates rejected (24h requirement dedupe, unique `(enquiry, company)`); claim approval needs verified claimant email, phone optional, approval ≠ verification, competing open claims block (0004 gate, tested on the reconstructed baseline).

## 7. Test results
| Suite | Environment | Result |
|---|---|---|
| `tests/run_all.sh` (legacy) | LOCAL RECONSTRUCTED baseline | 138 PASS / 0 FAIL |
| `tests/run_real.sh pre` | LOCAL REPLICA of real schema + 0001–0005 | 35 PASS; exposure controls recorded as EXPOSED: E1–E4, E6–E10 |
| `tests/run_real.sh post` | LOCAL REPLICA + 0001–0006 | 61 PASS / 0 FAIL; every exposure control closed |
Covered on the replica: routing outcomes (verified→direct; claimed-unverified, unclaimed, restricted → admin; suspended never matched), eligibility function incl. stale contact and no-category, requirement duplicate rejection, two-step buyer flow, honest delivery state, E1–E10, function ACLs, direct-table denial, anon denial, privilege escalation (buyer/seller), buyer-contact privacy, evidence suite above, view scan.
**Also covered on the replica:** cap of 5 (7 eligible suppliers → exactly 5 direct, 2 routed to admin) and duplicate delivery (unique constraint). **Not covered / limits:** competing-claim approval block is a 0004 gate tested on the reconstructed baseline (replica run stops earlier at "email not verified"); real Auth/Storage services, PG17 behaviour, concurrency/load not tested.

## 8. Rollback
`down/0006_down.sql` (generated from the replica's post-0005 definitions). Replica: apply 0006 → run down → `pg_dump --schema-only` (incl. grants) **identical** to pre-0006 (0 diff lines); re-apply after rollback succeeds. First attempt found a diff (FORCE RLS on 11 earlier tables) which the down script now reverts. Legacy rollback 0005→0001 passes on the reconstructed baseline.

## 9. Breaking changes if 0006 is ever applied (need owner decision)
1. Staff UIs can no longer read `company_private` or all `profiles` directly. 2. Reviewers only see/decide claims assigned to them (admin must assign). 3. Staff read claim evidence only through the audited RPC (edge function/signed URL flow must call it). 4. `submit_enquiry` no longer marks product enquiries visible to unverified sellers (held `awaiting_admin`, admin-only until a lead-case path exists — documented gap). 5. Sellers no longer receive notifications for new requirements. 6. Claimant-facing flows unchanged.

## 10. Residual risks / blockers
* B1 closed (real schema obtained read-only) but **PG17/Supabase platform behaviour untested** — before any application: dry-run on a Supabase branch/clone, not staging itself.
* Remaining staff-wide policies on other tables (direct messages, orders, etc.) not tightened by 0006 — separate review.
* Product enquiries held `awaiting_admin` lack a lead-case/desk path.
* Sixteen unrelated RPCs were stubbed in the replica.
* Owner approvals pending: breaking changes above; permission to apply to a non-production branch.


---
# Revision 2 (review round): refined 0006, notification rules, product-enquiry desk, DM/orders audit, isolated dry-run
Status unchanged: **nothing applied to original staging or production; the Lead Desk UI stays demo-only.**

## R2-1. Exact security changes in 0006 (cumulative)
1. `respond_to_lead`, `reveal_buyer_contact`, `seller_can_reply` re-check, at access time, that the seller is a delivered, currently eligible recipient (`seller_match_visible`/`_company_lead_eligible`). Reveal still needs a prior response and writes `enquiry_contact_access`.
2. `guard_company_columns` protects `lead_delivery_blocked` and `is_demo`; owners/managers cannot clear a restriction. (Suspension is `directory_status`, already guarded.)
3. `claim_reviewer_assignments` + `staff_can_review_claim`: reviewers read/decide only assigned open claims; admin assigns (`admin_assign_claim_reviewer`) and keeps full oversight.
4. Evidence: claimant-only direct table/storage access; staff via `staff_open_claim_evidence` (purpose, assignment, immutable log, 10-minute grant).
5. `company_private`: owner/manager only. Staff reach supplier contacts only through the 0003 audited vault functions (`staff_get_contacts`, purpose + assignment + log).
6. `profiles_self_read`: no staff-wide read of buyer profiles.
7. NEW: `staff_mark_enquiry` can no longer mark `visible_to_seller` for requirements or for ineligible suppliers (previously any staff could, making the buyer-facing status false).
8. NEW: staff-wide reads removed from `direct_threads`, `direct_messages`, `orders` (admin only) and scoped to assigned enquiries for `quotations`, `enquiry_replies`.
9. FORCE RLS on all new tables and the 11 earlier migration tables; explicit revoke/grant on every new object.

## R2-2. Seller notification rules (in-app `notifications` rows only; the schema has no email/SMS sender and none is called)
* A requirement notification is created **inside `_match_requirement` only when a `delivered_direct` event is newly recorded**, i.e. one notification per active owner/manager/sales member of the delivered, eligible company. `notify_on_enquiry` no longer notifies sellers for requirements.
* A product-enquiry notification is created only when delivery is `visible_to_seller` (at submit for an eligible supplier, or when staff release a held enquiry after the supplier became eligible).
* Unclaimed, claimed-but-unverified, restricted and suspended suppliers: **no seller notification** (tests N2–N4, P5).
* Admin/staff alerts (`kind='admin'`) go to admins only and are separate from seller notifications (test P6).
* Tests N1–N6 prove every lead notification maps to an actual delivered event and counts match.

## R2-3. Product-enquiry admin workflow
Held product enquiries (supplier not eligible) now create a Lead Desk case in new queue `product_enquiry_review` with a `routed_admin` event and an admin alert. Admin assigns it (`admin_assign_lead`); only the assignee or admin sees the enquiry. The assignee can release it with `staff_mark_enquiry(..., 'visible_to_seller')` **only after** the supplier is eligible (otherwise refused, buyer status unchanged); release notifies the seller and closes the case. Other outcomes (`sent_external` with a provider reference) also close the case. Tests P1–P16.

## R2-4. Direct messages / orders audit (real policies)
| Table | Before | After 0006 |
|---|---|---|
| `direct_threads`, `direct_messages` | buyer, seller roles, **any staff** | buyer, seller roles, **admin** |
| `orders` | buyer, seller roles, **any staff** | buyer, seller roles, **admin** |
| `quotations` | seller roles, **any staff**, buyer (non-draft) | seller roles, **assigned staff/admin**, buyer |
| `enquiry_replies` | buyer, seller (`seller_can_reply`), **any staff** | buyer, eligible seller, **assigned staff/admin** |
Writes were already limited to buyer/company roles. Tests MO1–MO7. Reviewers keep their authorised work through assigned leads/claims and the audited RPCs. Breaking change: any reviewer screen that lists all messages/orders will go empty (needs product decision: admin-only is the default).

## R2-5. Stubbed functions
See `STUBBED_FUNCTIONS_REPORT.md` (all 16, real bodies read-only from staging). Two open decisions: staff-wide `set_data_review`/`set_directory_status`.

## R2-6. Isolated environment
**No Supabase branch was created.** Branching runs under the original staging project, needs a cost confirmation and was not authorised, so the permitted fallback was used: a **local disposable PostgreSQL 16.15 cluster** (socket `/tmp/pgt`, port 5544, data dir `/tmp/pgt/data`, databases `dry_rb`, `dry_base`, `real_pre`, `real_post`) built from the staging schema extract. It is not Supabase, not PG17, not any hosted project; `tests/dry_run.sh` refuses to run unless the connection is a local `/tmp` socket. Not production, not TAPIS KASA, not the production-candidate project, not original staging. Staging was used only for read-only catalog SELECTs (schema extract, 16 function bodies).

## R2-7. Results (every row = LOCAL replica or LOCAL reconstructed baseline; none on Supabase)
| Suite | Environment | Result |
|---|---|---|
| Legacy 138 assertions | LOCAL reconstructed baseline | 138 pass |
| `run_real.sh pre` | LOCAL clone of real schema + 0001–0005 | 42 pass; exposure controls EXPOSED: E1–E4, E6–E10, MO4, MO5, P0 |
| `run_real.sh post` | LOCAL clone + 0001–0006 | 107 pass / 0 fail, all controls closed |
| `dry_run.sh` apply 0006 | LOCAL clone | ok (424 changed dump lines) |
| rollback 0006 only | LOCAL clone | schema+grants+policies+settings diff **0 lines**; re-apply ok |
| rollback 0006..0001 | LOCAL clone | identical to an untouched clone except whitespace in the bodies of 3 restored functions (`seller_can_see_leads`, `lead_matches_my_company`, `staff_mark_enquiry`); identical after whitespace normalisation |
Required-test mapping: verified seller delivered lead (N1, V1–V3), unverified zero leads (N2, V7), restricted cannot clear restriction (E4), cross-seller contacts (V4–V6, V8), staff isolation (a2/a3 tests, P9–P10), reviewer unassigned claim (E10), evidence needs audited grant (evidence tests), competing claims (CC1–CC4 on the real-schema clone), notifications (N1–N6), buyer privacy (V7, buyer-contact tests), product enquiry workflow (P1–P16), rollback (above).

## R2-8. Blockers / limits
* Supabase-hosted behaviour (Auth, Storage service, PG17, PostgREST grants) is untested; recommended next step is a real Supabase branch once you approve its cost.
* Whole-schema `diff` ignores data; rollback with live data present is untested (the down script re-queues `product_enquiry_review` cases).
* Open decisions: admin-only vs. scoped `set_data_review`/`set_directory_status`; reviewer access to messages/orders; storage upload paths for evidence by edge function.

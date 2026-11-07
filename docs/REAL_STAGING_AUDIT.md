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


---
# Revision 3 (decisions 1–4 implemented). Still LOCAL only: nothing applied to original staging/production; no Supabase branch created; Lead Desk demo untouched and unconnected.

## R3-1. Permission matrix (post-0006, enforced by RLS + definer functions; tested on the local clone)
| Resource | Buyer | Seller (eligible, delivered) | Seller (other) | Reviewer (assigned) | Reviewer (unassigned) | Admin |
|---|---|---|---|---|---|---|
| Buyer contact (`enquiry_private`, reveal) | own | via `respond_to_lead`+`reveal_buyer_contact`, logged | none | **assigned enquiry only, read directly via RLS (`epriv_read`; needed to work the lead; not individually logged, see R3-6)** | none (tested: 0 rows) | all |
| Enquiry / requirement row | own | delivered only | none | assigned only | none | all |
| Quotations, enquiry replies | own | own company roles | none | assigned enquiry **and** active 10-min audited grant | none | all |
| Direct threads / messages | own | own company roles | none | thread associated with an assigned enquiry **and** active grant | none | all |
| Orders | own | own company roles | none | **none** | none | all |
| Claim row | claimant | n/a | n/a | assigned open claims | none | all |
| Claim evidence (table + storage) | own claim only (upload to own open claim; read own) | n/a | n/a | via `staff_open_claim_evidence`, 10-min grant, assignment re-checked on every read | none | via same audited function |
| Company private contacts (`company_private`, vault) | n/a | owner/manager | none | vault functions only (purpose, assignment, log) | none | vault functions |
| set_data_review / set_directory_status | no | no | no | **denied** (recommend only) | denied | allowed, audited in `moderation_actions` |
| `staff_recommend_review` | no | no | no | assigned records only; immutable; audited | denied | allowed |
| Seller notifications | n/a | active owner/manager/sales of a delivered eligible company only | none | n/a | n/a | admin alerts separate |
Audit trails: `claim_evidence_access_log`, `staff_comms_access_log`, `contact_access_log`, `enquiry_contact_access`, `moderation_actions`, `audit_log` (all immutable or insert-only). Limitation: **admin reads through RLS are not individually logged** (oversight); only staff reads are grant-gated and logged.

## R3-2. Evidence upload/read architecture
1. **Upload:** claimant uploads (client or edge function with the claimant's JWT) to private bucket `verification-docs` at `<claim_id>/<file>`; `vd_insert` allows it only if the caller is the claimant of that claim and the claim is open (`claim_is_open_for_me`). No UPDATE policy (no overwrite); only admin may delete. Row in `company_claim_evidence` (`cev_ins`, same check).
2. **Read by claimant:** own claim folder (`vd_read`, `cev_read`).
3. **Read by staff:** (a) call `staff_open_claim_evidence(claim, purpose)` — requires admin or the assigned reviewer of an open claim, purpose ≥5 chars, writes the immutable log, opens a **10-minute** grant, returns the paths and `max_signed_url_seconds = 600`; (b) an edge function acting with the staff user's JWT then creates signed URLs with `expiresIn ≤ max_signed_url_seconds`. (c) `vd_read` additionally requires an unexpired grant **and** current assignment, so the raw Storage API cannot be used to bypass (a); revoking the assignment (`admin_unassign_claim_reviewer`) deletes grants and blocks reads immediately.
4. **No public URLs:** bucket `verification-docs` is `public=false` (read from staging, mirrored in the clone) and no policy on it is granted to anon/public (test U0).
Not testable locally: actual signed-URL generation and its TTL are done by the Supabase Storage service; locally we prove the database side (grant TTL ≤10 min, ceiling value, policy checks). A signed URL, once minted, is a bearer link until it expires (≤10 minutes by construction of the edge function; **to be verified on a Supabase branch**).

## R3-3. Seller notification behaviour (unchanged rules, extra tests N7–N11)
Only active owner/manager/sales members of a company that received an actual `delivered_direct` event (or an eligible/released product enquiry). Catalogue editors and removed members receive nothing (N9). Totals equal delivered events × eligible members (N10). Admin alerts are separate rows (`kind='admin'`). No email/SMS: the clone has no `pg_net`/`http` extension and no function mentions an HTTP/SMTP sender (N11); notifications are in-app rows only.

## R3-4. Product enquiry workflow (unchanged from Revision 2; tests P1–P16)
Held enquiry → Lead Desk case `product_enquiry_review` → admin assigns → assignee sees it → release only after the supplier is eligible → seller notified → case closed.

## R3-5. Review of grants, RLS, Storage policies and definer functions (`tests/security_inventory.sql`, post-0006 clone)
* 0 SECURITY DEFINER functions without pinned `search_path`; 0 public functions executable by `anon`.
* 0 public tables without ENABLE+FORCE RLS; deny-all tables (no policy, definer-only): `claim_evidence_grants`, `staff_comms_grants`, `claim_verifications`, `claim_verification_outbox`, `rate_events`.
* New tables grant `authenticated` SELECT only on the audit/assignment tables (read policies admin/own); grants tables have no grants.
* `anon` table privileges: only `categories`, `cms_pages`, `media_assets` SELECT (existing, public by design) plus the six public views.
* Storage: 8 policies, all `authenticated`; `vd_*` as described.

## R3-6. UNRESOLVED risks (not covered by decisions 1–4; need your decisions)
Assigned staff read the buyer's contact details (`enquiry_private`) directly through RLS for their assigned enquiries, without a purpose/log step (existing 0002 design). If audited access is wanted here too, it needs the same grant pattern as comms.
39 existing policies still use a bare `is_staff()` (any reviewer). Most relevant: `company_internal_notes`, `company_outreach_events`, `company_follow_ups`, `company_acquisition`, `seller_feedback`, `enquiry_contact_access` (log of who revealed buyer contacts), `lead_responses`, `audit_log`, `company_membership_audit`, `suppression_list`, `company_sources`, `company_data_corrections`, `company_images`/`product_images`, `members_read`, import tables, and UPDATE policies `companies_staff_update` / `products_staff_upd` (protected columns are guarded by triggers, tested D1e, but other columns are editable by any reviewer). Also `approve_product_image` (staff-wide), and storage policies `bro_obj_read/write`, `pmp_public_staff`, `cap_write` that include `is_staff()`. None of these touches buyer/seller contact data or evidence directly, but internal notes and outreach events may hold supplier contact details.

## R3-7. Results (every figure: LOCAL clone of the staging schema extract on PostgreSQL 16.15, NOT Supabase, NOT staging; legacy = LOCAL reconstructed baseline)
| Suite | Result |
|---|---|
| Legacy (reconstructed baseline) | 138 pass, 0 fail |
| Real-schema clone + 0001–0005 (`run_real.sh pre`) | 54 pass, 0 fail, **15 exposure controls EXPOSED** (E1–E4, E6–E10, P0, MO4, MO5, D1a, D1b, D1d) |
| Real-schema clone + 0001–0006 (`run_real.sh post`) | **157 pass, 0 fail, 0 exposed** |
Negative tests include: reviewer denied publication functions (D1f–D1h), direct table UPDATE denied (D1e), unassigned staff denied comms/evidence (MO6h, MO6i, R5, R5b), cross-claim upload and read denied (U2, R1), anon denied (U5, U5b), expired/revoked grants (R3, R6, R7), planted grants useless (R5b, MO6i), seller cross-access (V4–V8), restricted seller (E4).
Limits: U3 (no overwrite) passes in the clone because the stub grants no UPDATE on `storage.objects`; on Supabase it rests on the absence of an UPDATE policy — verify on a branch. Expiry tests manipulate `expires_at` rather than waiting 10 minutes.

## R3-8. Rollback comparison
| Check | Result |
|---|---|
| Apply 0006 to clone | ok (753 changed dump lines) |
| Roll back 0006 → `pg_dump -s` (tables, columns, functions incl. SECURITY DEFINER/search_path, triggers, policies, RLS/FORCE flags, grants) vs pre-0006 | **0 diff lines**; re-apply ok |
| Roll back with data present (post suite data: 5 enquiries, cases, grants) | down ran clean; schema identical to a clone that never had 0006 (0 diff lines) |
| Roll back 0006→0001 vs untouched clone | identical except whitespace in 3 restored function bodies (identical after normalisation) |

## R3-9. Remaining blockers
Supabase-branch validation (cost approval pending); signed-URL TTL and Storage-service behaviour; the 39 staff-wide policies above; `approve_product_image`; edge function for evidence URLs and the admin/reviewer UI changes required by decisions 1–3 (reviewer screens for messages/orders will be empty by design).

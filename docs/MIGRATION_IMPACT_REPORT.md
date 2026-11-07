# MIGRATION IMPACT & COMPATIBILITY REPORT (draft migrations 0001–0005)

Status: **NOT applied. Not staging verified.** Compatibility with the real staging schema is **unproven** until blocker B1 is cleared. This report separates what was measured locally from what must still be verified.

## 1. What the migrations do
| File | Purpose | Touches existing objects? |
|---|---|---|
| 0001 | `categories.parent_id`; `companies` +`is_demo`, `business_types`, `export_markets`, `capabilities`, `lead_delivery_blocked`; new `company_contacts`, `contact_access_log` | additive columns (defaults) |
| 0002 | requirements, matching, lead desk, eligibility, assignment-scoped staff | **replaces policies** `enq_leads_read`, `enq_staff_read`, `enq_staff_upd`, `epriv_read`; **redefines** `seller_can_see_leads`, `lead_matches_my_company`, `staff_mark_enquiry` |
| 0003 | contact-vault functions (purpose + scope + audit) | none |
| 0004 | claim email/phone verification, approval gate trigger, claim invitations | adds trigger on `company_claims` |
| 0005 | reviewer scope for claims/verification docs | **replaces** `claims_read` and `storage.objects.vd_read` |

Object counts (reconstructed baseline, `reports/schema_diff_before_after.diff`): 11 tables, 30 functions, 15 policies (10 new + 5 replaced), 5 triggers, 4 indexes, 2 types added; 11 diff lines removed/changed = the 5 replaced policies, 3 redefined function bodies and 3 column-list alignments. **Rollback proof:** applying `down/0005…0001` returns a schema dump byte-identical to the baseline.

## 2. Behavioural changes for existing users (must be accepted deliberately)
1. Sellers who are claimed+published but **not verified** lose direct lead visibility (intended; fixes finding F1).
2. Staff (admin/reviewer) lose role-wide read of all enquiries, buyer-private rows, and claims. Admin keeps all; reviewers see assigned leads and open claims.
3. `company_claims` can no longer be set to `approved` without a verified claimant email and without resolving conflicting open claims (trigger). Any existing admin tooling that approves directly will start to fail until the claimant verifies.
4. `staff_mark_enquiry` now requires the staff member to be assigned the lead (or admin).

## 3. Compatibility risks to verify on the real schema (checklist; all open)
| # | Risk | How to verify |
|---|---|---|
| R1 | `guard_company_columns` may block writes to new `companies` columns or reject the admin restriction flag | run 0001 on the dump; update each new column as admin/staff/owner |
| R2 | `guard_enquiry` may reject `_match_requirement` setting `enquiries.delivery` | run create_requirement test on the dump |
| R3 | Real `reveal_buyer_contact`, `respond_to_lead`, `seller_can_reply`, `submit_enquiry` bodies may depend on the old lead-visibility rule or let an unverified seller reveal buyer contact | read bodies; add tests (not captured so far) |
| R4 | Real `submit_claim`/`review_claim`/`set_verification` vs the new approval gate trigger | execute claim flows on the dump |
| R5 | `notify_on_enquiry` may also notify sellers on requirement enquiries (duplicate/unauthorised notifications) | read body, test |
| R6 | `cev_read` (claim evidence metadata) predicate was not captured; left unchanged and unscoped (documented gap) | read policy; scope like `claims_read` |
| R7 | Six security-definer public views — see §4 | run `tests/check_public_views.sql` on the dump |
| R8 | Name clashes (`lead_status`, `match_route` types; `company_contacts`) with objects not captured | the dump will show; migrations use plain `create` so a clash fails loudly |
| R9 | Advisor: ~27 new authenticated-executable SECURITY DEFINER RPCs will appear in the existing WARN list; each begins with an explicit role/ownership check (tested) | re-run advisors on staging after an approved apply |
| R10 | Real indexes/FKs on `enquiries`, `companies` (e.g. unique claim index referenced by `submit_claim`) | review dump |

## 4. The six SECURITY DEFINER public views
Known from the catalog (read-only, 2026-11-07): `public_companies`, `public_company_categories`, `public_company_images`, `public_company_sources`, `public_product_images`, `public_products` all have `security_invoker=false`; anon holds SELECT on exactly these (plus `categories`, `cms_pages`, `media_assets`) and on no base table; their output columns contain no phone/email/address/pin/contact fields, no buyer data, no `created_by`/`verified_by`. **Purpose (inferred, to be confirmed):** an allow-listed, owner-privileged projection so anonymous users can read approved rows without any RLS policy for anon on base tables. Not confirmed: the view bodies (publication/approval filters, joins), which is why this is *not* declared verified.
`supabase/tests/check_public_views.sql` lists options/owner, definitions, base-table dependencies, flagged private-looking column names, views lacking a publication filter, and grants. **Must be run on the real dump** (B1). My migrations do not modify any public view, and a local test asserts the public view surface is unchanged.

## 5. Open blockers
* **B1:** exact schema-only dump of staging (user runs `supabase db dump --schema-only` themselves; no data, no keys). Needed for §3 and §4. I will not run further SQL on staging without approval.
* **B2:** real bodies of the functions in R3–R5 (included in the dump).
* **B3:** decision on `cev_read` scope (R6).
* **B4:** product decisions: eligibility requires verified email **and** phone by default (configurable in `lead_routing_settings`); contact verification expires after 365 days; per-requirement direct cap 5; claim approval requires verified email (phone optional).

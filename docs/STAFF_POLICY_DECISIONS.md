# Staff-wide policy decisions (migration 0006, ROUND 4)

Status: DRAFT, validated only on a **local PostgreSQL 16 replica** built from the staging schema catalogue. Nothing has been applied to staging, a Supabase branch, or production. "Assigned" = `staff_assigned_to_company(company)`: admin, OR reviewer assigned via an open claim, a lead case matched to the company, or a product-enquiry case.

Tests named below are in `supabase/tests/real_schema_tests.sql` (blocks `POL`, `W1-W18`, `K1`). Every policy has a read/write matrix test for: assigned staff, unassigned staff, admin, owner/member, anon. Pre-0006 controls prove the old staff-wide behaviour (26 EXPOSED in the pre run).

| # | Table / op | Before | Purpose | Roles needing it | Assignment-scoped | Audit event | New rule | Negative tests |
|---|---|---|---|---|---|---|---|---|
| 1 | audit_log SELECT (audit_read) | any staff | forensic review | admin | n/a | reading not logged | admin only | POL audit_log (assigned, unassigned denied) |
| 2 | brochures SELECT (bro_read) | any staff | verify brochure | member, assigned | yes | no | member or assigned | POL brochures |
| 3 | companies SELECT | any staff | review company | member, claimant, assigned | yes | no | + assigned | POL companies |
| 4 | companies UPDATE (companies_staff_update) | any staff | correct record | assigned | yes | publication columns remain behind guard triggers + admin RPC | assigned only | W3 |
| 5 | company_acquisition ALL | any staff | outreach pipeline | assigned | yes | existing | assigned | W5 |
| 6 | company_categories SELECT | any staff | listing | live, member, assigned | yes | no | + assigned | POL ccat |
| 7 | company_categories write (ccat_write) | any staff | category edit | owner/manager, admin | no | existing moderation | owner/manager/admin | W-ccat |
| 8 | company_data_corrections SELECT | any staff | triage reports | reporter, owner/manager, assigned | yes | no | assigned | POL corr |
| 9 | company_data_corrections UPDATE | any staff | resolve | assigned, reviewed_by=self | yes | reviewer recorded | assigned | W-corr |
| 10 | company_follow_ups ALL | any staff | follow-up tasks | assigned | yes | no | assigned | W5 |
| 11-14 | company_images DEL/INS/READ/UPD | any staff | image upkeep | editors, assigned | yes | no | assigned | POL cimg |
| 15 | company_import_batches ALL (cimp_b) | any staff | bulk import | admin | no | operator_id=self | admin only | POL import |
| 16 | company_import_rows ALL (cimp_r) | any staff | bulk import | admin | no | no | admin only | POL import |
| 17 | company_internal_notes INSERT | any staff | notes | assigned | yes | author_id=self | assigned (+admin) | W1 |
| 18 | company_internal_notes SELECT | any staff | notes | assigned (+admin) | yes | no | assigned | POL notes |
| 19 | company_members SELECT | any staff | roster | self, members, assigned | yes | no | + assigned | POL members |
| 20 | company_membership_audit SELECT | any staff | audit | admin | n/a | no | admin only | POL cma |
| 21 | company_outreach_events INSERT | any staff | log outreach | assigned | yes | recorded_by=self | assigned (+admin) | W2 |
| 22 | company_outreach_events SELECT | any staff | outreach history | assigned (+admin) | yes | no | assigned | POL outreach |
| 23 | company_sources ALL | any staff | provenance | assigned | yes | no | assigned | POL sources |
| 24 | company_verification_reviews SELECT | any staff | verification | assigned | yes | no | assigned | POL cvr |
| 25 | enquiry_contact_access SELECT (eca_read) | any staff | contact-reveal log | admin (no separate audit-personnel role exists) | n/a | immutable log | admin only | POL eca |
| 26 | lead_responses SELECT | any staff | lead history | seller member, buyer, staff on case | yes (`staff_can_see_enquiry`) | no | case-scoped | POL lr |
| 27 | media_assets ALL | any staff | site media | admin (public read stays by design) | no | no | admin only | W18 |
| 28 | moderation_actions SELECT | any staff | decision trail | admin, or own actions | n/a | immutable | admin or own | POL mod |
| 29-30 | product_images DEL/SELECT | any staff | image upkeep | editors, assigned | yes | no | assigned | IMG3, POL |
| 31 | product_view_events SELECT | any staff | analytics | member, admin | no | no | member or admin | POL views |
| 32 | products SELECT | any staff | review | member, assigned | yes | no | + assigned | POL products |
| 33 | products UPDATE | any staff | correct record | assigned | yes | guard_product protects publication | assigned | W4 |
| 34 | seller_feedback SELECT | any staff | feedback | admin | n/a | no | admin only | POL fb |
| 35 | suppression_list ALL | any staff | do-not-contact | admin | no | no | admin only | POL supp |
| 36-39 | storage: bro_obj_read/write, cap_write, pmp_pending_rw, pmp_public_staff | any staff | file upkeep | owner/manager, assigned; public bucket admin | yes / admin | no | assigned or admin | storage POL tests |

Kept deliberately unchanged: `categories_read_auth`, `cms_read_auth`, `profiles_self_read`, `cinv_read` (no staff-wide exposure of supplier or buyer data).

Also changed: `import_normalize` is now `is_admin()`; `epriv_read` (buyer contact) moved to the audited-grant model (see `BUYER_CONTACT_ACCESS.md`).

Limitations: the table above groups some policies, the migration holds the exact predicates; policies marked "no" audit rely on row-level author/reviewer columns, not an access log; denied attempts are not logged (exceptions roll back).

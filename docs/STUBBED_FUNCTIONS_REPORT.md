# The 16 stubbed functions: real counterparts and security implications
Context: the local replica (`supabase/staging_schema/`, git-ignored) replaces these 16 function bodies with empty stubs because they are unrelated to migrations 0001–0006. Real bodies were read from `globaltradeb2b-staging` with **read-only catalog SELECTs** (project ref `lhmexhafyuzojrmcbtbz` verified by `get_project` before reading; nothing written). All 16 are `SECURITY DEFINER` with `search_path=public, pg_temp`; **none is executable by `anon`**; `record_product_view` is not executable by `authenticated` either (service role only).
Consequence of stubbing: the local tests say nothing about these functions' behaviour. None of 0001–0006 calls, replaces or depends on them, except where noted.

| # | Function | Real behaviour (summary) | Who may call | Security implication / interaction with 0001–0006 |
|---|---|---|---|---|
| 1 | `accept_invitation(member)` | Confirmed-email user accepts a pending seat; same error for unknown/other-person invite (no enumeration); expiry; needs a claimed company; rate-limited | authenticated | Creates **active company members**, which feed lead eligibility (`_company_lead_eligible` needs an active owner/manager/sales member). Eligibility is re-checked at access time, so a new member of an ineligible company still gets no leads. OK |
| 2 | `decline_invitation(member)` | Invitee marks own invite removed | authenticated | Own invite only. OK |
| 3 | `my_invitations()` | Lists live invitations for the caller's confirmed email, only for approved-claim companies | authenticated | Email-matched, no leakage. OK |
| 4 | `create_company_request(...)` | Authenticated user creates a company (`claim_submitted`) + `direct_submission` source + a "Creator" claim; rate-limited 3/day | authenticated | Feeds **claims**. Approval still passes the 0004 gate (verified email, no competing claim) and 0006 assignment. Creator claims have no evidence upload at creation: `review_claim` already refuses approval without evidence. OK |
| 5 | `report_correction(...)` | Authenticated user files a correction for a live company; rate-limited | authenticated | Writes to `company_data_corrections` only. OK |
| 6 | `record_product_view(product, hash)` | De-duplicated (1 h) anonymous-hash view counter; ignores unpublished products | service role only | No PII. OK |
| 7 | `set_data_review(target,id,status,note)` | Sets review state of a company/product; non-approved review always withdraws publication; writes `moderation_actions` | staging: `is_staff()`. **0006 (Decision 1): admin only** | RESOLVED in draft. Reviewers use `staff_recommend_review` (assigned records only, immutable, audited). Tested D1a–D1q |
| 8 | `set_directory_status(target,id,status,reason)` | Changes directory status with mandatory reason; writes `moderation_actions` | staging: `is_staff()`. **0006: admin only** | RESOLVED in draft (same as 7) |
| 9 | `approve_product_image(image,path)` | Any staff approves an image if rights are cleared and sets its public path | `is_staff()` | UNRESOLVED: affects public visibility of an image and `public_path` is unvalidated free text exposed by `public_product_images`. Not covered by Decision 1 (companies/products); recommend admin-only |
| 10 | `import_normalize(batch)` | Staff normalises/dedupes staged import rows against the suppression list | `is_staff()` | Respects suppression list. OK |
| 11 | `import_apply(batch)` | Admin-only; requires confirmed source terms; creates companies | admin | Imported companies become unclaimed supplier records (Admin Lead Desk route). No contacts imported into the vault by this function. OK |
| 12 | `import_rollback(batch, ref)` | Admin-only; refuses if any batch company is published or has enquiries/claims/members | admin | Protective. OK |
| 13 | `create_order(quote)` | Buyer creates an order from an **accepted** quotation of an active supplier; rate-limited | authenticated buyer | Orders readable per 0006-revised `orders_read` (buyer, seller roles, admin only) |
| 14 | `advance_order(order,status)` | Supplier owner/manager/sales moves order through a fixed state machine | company roles | No eligibility re-check (an order is an existing commitment). Acceptable |
| 15 | `cancel_order(order)` | Buyer cancels own `placed` order | buyer | OK |
| 16 | `respond_quotation(quote, accept)` | Buyer accepts/declines an open quotation | buyer | OK |

## Open items from this review
* #9 `approve_product_image` is still staff-wide (see row).
* Replica caveat: since round 3 the replica uses the real bodies of #7/#8 (read from staging, SELECT only); the other 14 are still empty stubs locally.


## Round 5 impact report: functions still stubbed on the replica
Actual count: **12** (not 14). Of the original 16, `set_data_review`, `set_directory_status`, `approve_product_image` and `import_normalize` now run their real (or 0006 replacement) bodies locally. No front-end code in this repo calls any of the 12 (the only UI is the demo `index.html`), so "unused" cannot be proven from this repo; none is classed obsolete.

| Function | Class | Depends on | Recommended next action |
|---|---|---|---|
| accept_invitation | Required for launch (supplier team seats); **security-sensitive** (creates active members that feed lead eligibility) | company_members, invitations, claim_status='approved', verified email, check_rate | Mirror real body, add tests: wrong email, expired, unclaimed company, enumeration, eligibility after accept |
| decline_invitation | Required later | company_members | Mirror body; own-invite-only test |
| my_invitations | Required later | profiles/email, approved claims | Mirror body; leakage test |
| create_company_request | Required for launch (supplier self-signup); **security-sensitive** (creates a claim) | companies, company_claims, company_sources, 0004 claim gate, rate limit | Mirror body; test with 0004/0006 approval gate and evidence rule |
| report_correction | Required later | company_data_corrections, rate limit | Mirror body; abuse/rate test |
| record_product_view | Required later (analytics) | product_view_events, service role only | Verify EXECUTE is service_role only on hosted; low risk |
| import_apply | Required for launch if the directory is seeded by import; **security-sensitive** (creates companies) | import batches/rows, suppression list, source terms | Mirror body; test admin-only, terms confirmed, suppression, no contact vault writes |
| import_rollback | Same as import_apply; **security-sensitive** | import tables, published/enquiry/claim checks | Mirror body; test refusal paths |
| create_order | Required later (orders phase); **security-sensitive** (commitment) | quotations, orders, rate limit | Mirror body; test accepted-quote-only, active supplier |
| advance_order | Required later; **security-sensitive** | orders state machine, company roles | Mirror body; state-machine and role tests |
| cancel_order | Required later | orders | Mirror body; buyer-own placed-only test |
| respond_quotation | Required later; **security-sensitive** | quotations | Mirror body; buyer-own, open-quote-only test |

If orders/quotations are out of launch scope, consider revoking EXECUTE from `authenticated` on the order functions until that phase (recommendation only; not applied). Next step for all 12: mirror real bodies by read-only catalogue SELECT (as done in round 3) before the hosted run; the hosted run then covers them natively.


---
## Round 6: real definitions mirrored and reviewed (supersedes the Round 5 classification where they differ)
Source: read-only catalogue SELECT (`pg_get_functiondef`, `proacl`) against `globaltradeb2b-staging` (ref `lhmexhafyuzojrmcbtbz`, verified with get_project before reading; no function replaced or executed there). Mirrored into the local replica (git-ignored `staging_schema/real_02_functions.sql`), no stubs remain for these 12. Staging runs PostgreSQL 17; the replica is 16.15 (a caveat for hosted validation). All 12 are SECURITY DEFINER with `search_path = public, pg_temp`. Tests: `real_schema_tests.sql` block SF1-SF21 (run in the post phase; 38 assertions).

| Function | Auth / role | RLS & assignment interaction | Contact exposure | Duplicates / consequences | Findings |
|---|---|---|---|---|---|
| accept_invitation | login + confirmed e-mail, 10/day (successes only) | definer; creates active member; profile -> seller; eligibility is re-checked at access time elsewhere | none | second accept refused (SF5b); no enumeration (SF2); unclaimed workspace refused (SF4) | **F1** NULL `expires_at` = never expires (SF7). Failed attempts are not rate-counted (exception rolls the event back) |
| decline_invitation | confirmed e-mail only | own invite only | none | not found on repeat | none |
| my_invitations | confirmed e-mail; approved company only | no leakage (SF1) | none | - | none |
| create_company_request | login, 3/day | new company is claim_submitted, owned by nobody, invisible to unrelated users and to unassigned reviewers (SF9f-g) | none | **F2** same name can be created repeatedly (SF9c); approval impossible without evidence (SF9h) | add duplicate check (name+city) and admin dedupe review |
| report_correction | login, 10/day, company must be live | writes only `company_data_corrections` (assigned staff / owners read) | none | **F3** `p_product` not tied to `p_company` (SF20b); `evidence_url` stored raw, e.g. `javascript:` (SF20a) | validate product belongs to company; UI must link http/https only |
| record_product_view | service_role only | no PII, 1 h de-dupe | none | **F4** unbounded rows if a caller varies the hash (service-side hashing must be trusted) | keep server-side; add retention job later |
| import_apply | admin only; terms confirmed; batch validated | creates unpublished companies + sources, no contacts, not public (SF11d) | none | idempotent (SF11c); duplicate rows flagged (SF11e) | **F5** no import-specific audit/applied_by (SF11f) |
| import_rollback | admin only | refuses published/claimed/enquired companies (SF12) | none | **F6** `requirement_matches` is ON DELETE CASCADE, rollback silently deletes matches of imported companies (SF12a) | add a guard for matches/lead cases |
| respond_quotation | buyer who owns the enquiry | row lock; open + not expired | none | repeat refused (SF14b) | **F7** the expiry update is rolled back by its own exception (quote stays `sent`, SF14d); `e.buyer_id <> auth.uid()` is NULL when uid is NULL (service role passes the owner check, SF19) - use `is distinct from` |
| create_order | buyer, accepted quote, supplier claimed, 20/day | no staff path | none | unique(quotation_id) blocks duplicate orders (SF15b); amount/currency/supplier taken from the quote (SF15) | **F8** does not re-check quote validity date, supplier verification/restriction, or NULL uid |
| advance_order | supplier owner/manager/sales | reviewers and admins refused (SF16, SF16c); strict state machine (SF17) | none | repeat -> illegal transition | status changes audited by `trg_audit_orders` with actor (SF17d); no reason/notes field |
| cancel_order | buyer, own, `placed` only | - | none | repeat refused | none |

Classification (unchanged where not mentioned): Required for launch - accept_invitation, create_company_request, import_apply, import_rollback (if the directory is import-seeded); Required later - decline_invitation, my_invitations, report_correction, record_product_view, orders/quotation functions (create_order, advance_order, cancel_order, respond_quotation); security-sensitive - accept_invitation, create_company_request, import_*, all four order functions; none proven unused/obsolete (nothing in this repo calls them).
Recommended migration items (proposed only, NOT written or applied; need approval): F1 invitation expiry NOT NULL/default; F2 duplicate detection; F3 product/company check; F5 import audit; F6 rollback guard; F7/F8 `is distinct from`, order-time validity checks, expiry persistence (write the expired status without raising). These replace real staging functions, so each needs its own approved migration and test.

## Round 7: findings F1–F8 fixed locally in `0007_function_hardening.sql` (draft, local PG 16.15 only; not applied to any Supabase project)
Details, threat scenarios, decisions and tests: `docs/ROUND7_TEST_REPORT.md` §2. Status of the original table:

| # | Function | Fix in 0007 | Status |
|---|---|---|---|
| F1 | `accept_invitation` | NULL `expires_at` = expired (fail closed); `NOT VALID` check forbids new pending invites without expiry | fixed, tested |
| F2 | `create_company_request` | per-creator idempotent (advisory lock + open-state lookup before rate limit); cross-user duplicates intentionally allowed | fixed, tested incl. 8-way concurrency |
| F3 | `report_correction` | product must belong to company; evidence URL http(s) only, ≤500 chars, `NOT VALID` check on the table | fixed, tested |
| F4/F5 | `import_apply`/`import_rollback` | new immutable `company_import_audit` (apply + rollback rows) | fixed, tested |
| F6 | `import_rollback` | refuses when imported companies have lead matches or quotations; batch row lock; second rollback is a no-op | fixed, tested incl. concurrent match insert |
| F7 | `respond_quotation` | returns `'expired'` and persists it instead of raising; NULL-uid refused; `IS DISTINCT FROM` owner check; return type void→text | fixed, tested |
| F8 | `create_order` | NULL-uid, row lock, validity date and supplier eligibility rechecked | fixed, tested incl. 4-way concurrency |
| new F9 | 4 pgcrypto functions | `extensions.`-qualified `digest`/`gen_random_bytes` (hosted layout) | fixed, tested |
| new F10 | `import_normalize` | my own 0006 doubled the backslash in the website regex (every normal URL rejected); staging form restored | fixed, tested |

Not changed (documented limits): refusals raised for non-admin callers are not audited (the exception rolls the row back); other URL columns (`company_sources.source_url`, batch `source_url`) are not scheme-checked; cross-user company duplicates remain a staff dedupe task.

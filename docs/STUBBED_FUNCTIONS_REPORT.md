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

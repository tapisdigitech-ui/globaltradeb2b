# Frontend / Backend Integration Contract

Status: **specification only.** The frontend (`index.html`) is a demonstration and is **not** connected to Supabase; this document does not change that. Operation names and signatures below come from the final local schema (baseline + 0001–0008) and the Edge Function in `supabase/functions/evidence-link/`. HTTP status mapping and Storage/Edge behaviour are **not verified on the real stack** (see `ROUND10_LOCAL_SUPABASE_VALIDATION.md`); items marked ⚠ must be confirmed there. Findings referenced as F-x / P1-x are in `ROUND10A_INDEPENDENT_AUDIT.md` and `PRIORITISED_LAUNCH_CHECKLIST.md`.

## 1. Ground rules

1. The browser holds only the project URL and the **anon (publishable) key**. The service-role key never reaches the browser, the Edge Function, or any client bundle.
2. Authorisation is enforced by the database (RLS, grants, `SECURITY DEFINER` functions). Client-side role switches (`#admin`, `#seller`, `UI.role`) are presentation only and must be removed or hidden behind a real session role check.
3. Writes go through the RPCs below. Direct table writes by the client are limited to the cases listed in §6 and are always subject to RLS and guard triggers.
4. Identifiers (`ref`, ids, statuses, timestamps) come from the server; the client never generates enquiry references (the demo's `uid()` is removed).
5. No private phone/email of any supplier or buyer is stored in `localStorage`, logged to the console, put in URLs, or sent to analytics. Buyer contact details are submitted once to `submit_enquiry` and are never read back by the buyer UI or by sellers except through `reveal_buyer_contact`.
6. Every response is rendered through text nodes or an escaping function; `innerHTML` with user data is forbidden (audit: 103 `innerHTML` sites to review).
7. Pages display server-provided wording for delivery state (§4); the client does not invent "sent / delivered / received" text.

## 2. What the prototype simulates today

| Prototype module (`index.html`) | Today | Real backend equivalent |
|---|---|---|
| `Store` (`localStorage` keys `gtb2b-myprods/-paused/-enquiries/-admin/-buyer/-loc`) | all data local to the browser | Postgres tables via PostgREST |
| Homepage/category/supplier/product cards (`SECTIONS`, sample companies and 103 Unsplash photos) | static demo data | `public_companies`, `public_products`, `public_company_categories`, `public_*_images`, `categories` |
| Enquiry / "Get Best Price" / "Contact Supplier" forms | saved locally; notes say "nothing is sent" | `submit_enquiry` (+ `create_requirement` for requirements) |
| Post a requirement (`rqMsg` "Preview only") | not connected | `submit_enquiry(kind=requirement)` then `create_requirement` |
| My Enquiries + replies | local threads | `enquiries` (own), `enquiry_replies`, `buyer_requirement_status` |
| Seller Centre (listings, pause, brochure, messages, help notes) | local; any visitor can open it | product/company tables under RLS; `direct_threads/messages`; Storage |
| Buy Leads / Admin Lead Desk simulation (`S.cos`, `route()`, "Delivered to seller inbox (simulated)") | client-side re-implementation of routing | server routing (`create_requirement` → `_match_requirement`), `admin_*` / `staff_*` RPCs |
| Admin console (hide/reject categories, companies) | local toggles | `set_directory_status`, `set_data_review`, `set_verification`, `categories` (admin) |
| Claim / verification / onboarding wizard | local, "no real account/verification" | `create_company_request`, `submit_claim`, `start/confirm_claim_verification`, Storage, `staff_request_evidence_links` |
| Sign-in (`signinView`) | cosmetic | Supabase Auth (email), session JWT |
| Messages / quotations / orders | demo threads | `direct_*`, `quotations`, `respond_quotation`, `create_order`, `advance_order`, `cancel_order` |

Pages that display **demo data** and must carry a visible demo marker until real data replaces them: home, category sections, supplier and product pages, trending, buy-leads board, seller centre, admin console, "My Enquiries" samples. When connected, the server flag `is_demo` (after P1-3 exposes it) decides the marker; demo rows must be excluded from default production listings.

## 3. Actions that must not look operational until the backend exists

Hide, disable with an explanatory "demonstration" state, or relabel:

- "Contact Supplier", "Get Best Price", "Send enquiry", "Post requirement" — until `submit_enquiry` is wired and its response is displayed.
- "Claim your company", verification badges, "email/phone verified" statuses — until driven by `public_label`/`is_verified` from the server.
- Seller "Reply", "Send quotation", "Accept order", brochure upload — until messaging/quotation/order RPCs and Storage are wired.
- Admin console, lead desk, claim review, evidence viewer — until behind a real session with `app_role` admin/reviewer (server-checked).
- Any text promising matching ("suppliers will send quotations", "your details go to each supplier", "Buyers will contact you on these details") — until the corresponding backend state exists; see §4.
- Promotions/trending/"top supplier" ranking claims — there is no ranking backend.

## 4. Delivery and verification wording (server-driven)

`submit_enquiry` returns `(enquiry_ref, delivery, notice)`. The UI shows `notice` verbatim and uses `delivery` only for styling:

| `delivery` | Meaning (server) | Allowed UI claim |
|---|---|---|
| `stored` (requirements, step 1) | recorded; **no supplier contacted** | "Recorded. No supplier has been contacted yet." |
| `awaiting_admin` | held: supplier unclaimed or not verified for direct enquiries | "Held by our team. NOT delivered to the company directly." |
| `visible_to_seller` | visible in an eligible, verified supplier's seller account; read status unknown | "Visible to the supplier in their account. We cannot confirm they have read it." Never "received", "sent to", "delivered to" |

After `create_requirement`, `buyer_requirement_status` returns `{delivered_to_verified_suppliers, being_handled_by_team, message}`; display `message` and the count only. ⚠ The current server message says "Sent to N verified supplier(s)"; since delivery means "made visible in the seller's account", change the server wording (P1 item) or render the count as "made available to N verified supplier account(s)".

Company labels come only from `public_companies.public_label` (`Verified`, `Verification Pending`, `Claimed — Not Verified`, `Claim Requested`, `Unclaimed — Not Verified`). The client must not compute its own badge. Product availability, price and stock shown on cards are supplier-entered and unverified: label them "as listed by supplier"; there is no stock or availability service.

## 5. Public (anonymous) reads

| Operation | Backend | Response | Permission | Notes |
|---|---|---|---|---|
| Categories | `GET categories` | `id, slug, name, hue, position, hidden, parent_id…` | anon read where `not hidden` | seed = 14 top-level categories |
| Company directory | `GET public_companies` | `id, slug, name, business_type, about, city, state, country, website, logo_path, public_label, is_claimed, is_verified, data_as_of, updated_at` | anon | **no phone/email/address by design**; paginate (`max_rows` 1000) |
| Company sources | `GET public_company_sources` | field, source type/name/url, dates | anon | show provenance ("data from …"), not contact values |
| Company categories | `GET public_company_categories` | `company_id, category_id` | anon | |
| Products | `GET public_products` | product fields, `company_slug/name/label`, `search`, provenance | anon | prices are supplier-entered |
| Images | `GET public_company_images`, `public_product_images` | path, position | anon | only `approved` with rights `owned/licensed/permission_granted/public_domain`; render attribution/rights note |
| CMS | `GET cms_pages` (published) | | anon | |

Errors: network/5xx → generic "unavailable" state; empty list ≠ error. Never fall back to local demo data silently.

## 6. Authenticated operations

All calls use the user's JWT. "Denied" is a database error that the UI must treat as "not allowed" without revealing why. ⚠ PostgREST status mapping to confirm (expected: `42501` → 401/403, `28000` → 401/403, `P0001` → 400); the UI should branch on the SQLSTATE/message class, not on a specific HTTP code.

### 6.1 Account
| Operation | Backend | Request → response | Notes |
|---|---|---|---|
| Sign up / in / out | Supabase Auth | session JWT | profile row created with `app_role = 'buyer'` always; roles cannot be self-assigned (verified); email confirmation setting must be ON (P0-2) |
| Read own profile | `GET profiles?id=eq.<uid>` | own row | staff directory rows only |
| Update own profile | `PATCH profiles` | name/phone | `app_role` change is rejected by the server |

### 6.2 Buyer
| Operation | Backend | Key inputs | Response | Denials / limits |
|---|---|---|---|---|
| Product/company enquiry | `rpc submit_enquiry` | kind `product`, product or company, category, subject, quantity, unit, message, city, buyer name, phone/email (≥1), `p_consent=true`, notice version | `(enquiry_ref, delivery, notice)` | consent required; 10/hour, 30/day; product must be published+approved; **no idempotency yet (P1-11)** — disable the submit button while pending |
| Post requirement | `rpc submit_enquiry` (kind `requirement`) then `rpc create_requirement(enquiry, product, material, size, quality, specs, destination, timeline, additional, contact_pref)` | | `jsonb` status | duplicate within 24 h → error; 10/day; flow is two calls, handle failure after step 1 (a stored enquiry with no matching) |
| Requirement status | `rpc buyer_requirement_status(enquiry)` | | `jsonb` | own enquiries only |
| My enquiries | `GET enquiries?buyer_id=eq.<uid>` | | rows (no contact columns; contact is in `enquiry_private`, own-readable) | |
| Replies | `GET/POST enquiry_replies` | message | | seller replies appear only when allowed; `thread closed` for spam |
| Threads/messages | `POST direct_threads`, `POST direct_messages`, `GET` both | company, subject / body | | only with live **and claimed** companies; rate-limited by trigger |
| Quotation response | `rpc respond_quotation(quote, accept)` | | `'accepted' | 'declined' | 'expired'` | expired quotes return `expired` |
| Orders | `rpc create_order(quote)`, `cancel_order(order)`, `GET orders` | | order id | supplier must still be eligible; cancel only while `placed` |
| Correction report | `rpc report_correction(company, product, field, value, url, note)` | | id | URL scheme checked; rate-limited |

### 6.3 Seller (member of a claimed company: owner/manager/sales/catalogue_editor)
| Operation | Backend | Notes |
|---|---|---|
| Company request / claim | `rpc create_company_request(name, type, city, statement)`, `rpc submit_claim(company, title, statement)`, `rpc withdraw_claim` | idempotent per creator for identical requests |
| Evidence upload | Storage `verification-docs/<claim_id>/<server-generated-name>`, then `INSERT company_claim_evidence(claim_id, storage_path, description)` | object name **must** match `[A-Za-z0-9._-]{1,120}` (the Edge function rejects others — use `<evidence_uuid>.<ext>`); bucket allows pdf/jpeg/png ≤ 10 MiB |
| Verify claim contact | `rpc start_claim_verification(claim, channel, target)` → `rpc confirm_claim_verification(claim, channel, code)` | code delivery provider is **not enabled** (P1-8): UI must say verification is unavailable rather than imply an email was sent; 5/hour, 5 attempts |
| Claim summary | `rpc claim_verification_summary(claim)` | booleans only |
| Edit listing | `PATCH/POST products`, `product_images`, `company_images`, `company_private` | status/review/provenance columns are server-protected; edits of published items go back to review (known gap F-A until fixed) |
| Leads | `GET enquiries?kind=eq.requirement`, `GET requirement_details`, `GET requirement_matches` | only leads **delivered directly to eligible companies** appear; show `reasons` ("why matched") |
| Respond to lead | `rpc respond_to_lead(enquiry, company)` | 30/day; re-checks eligibility |
| Reveal buyer contact | `rpc reveal_buyer_contact(enquiry, company)` → `(buyer_name, buyer_phone, buyer_email, buyer_company)` | only after responding; logged; 100/day; render in memory only, never cache |
| Quotations | `POST/PATCH quotations`, `GET` | sellers cannot accept/decline |
| Orders | `rpc advance_order(order, status)` | legal transitions only |
| Notifications | `GET/PATCH/DELETE notifications` | own rows |
| Member invites | `POST company_members` (invited only), `rpc my_invitations`, `accept_invitation`, `decline_invitation` | owner role is staff-managed |
| Claim invitation (from outreach) | `rpc redeem_invitation(token)` → company id | redeeming approves nothing; still `submit_claim` |

### 6.4 Staff (reviewer) — assignment-scoped
| Operation | Backend | Notes |
|---|---|---|
| My leads | `rpc staff_my_leads`, `rpc staff_update_lead(case, status, note, next_follow_up)` | assigned cases only |
| Supplier contacts | `rpc staff_get_contacts(company, purpose, case, claim)`, `staff_add_contact`, `staff_set_contact_status` | purpose mandatory; each call logged; show values only while the screen is open |
| Buyer contact | `rpc staff_open_buyer_contact(enquiry, purpose)` | 10-minute grant; logged |
| Messages | `rpc staff_open_enquiry_comms(enquiry, purpose)` then normal reads | grant required |
| Claim review | `rpc review_claim(claim, decision, reason)`; recommendation `staff_recommend_review` | only the **assigned** reviewer; admins publish/verify |
| Evidence | **Edge `POST /functions/v1/evidence-link`** (below) | never read evidence rows/paths directly |
| Outreach | `rpc staff_create_invitation`, `staff_mark_invitation_sent`, `staff_log_call` | no message is sent by the platform; "sent" means a human recorded it |

### 6.5 Admin
`admin_lead_overview`, `admin_assign_lead`, `admin_assign_claim_reviewer`, `admin_unassign_claim_reviewer`, `admin_rematch`, `admin_rematch_for_company`, `admin_set_routing_settings`, `admin_approve_invitation`, `admin_revoke_buyer_contact_access`, `set_directory_status`, `set_data_review`, `set_verification`, `approve_product_image`, `import_normalize/apply/rollback`. All fail with `admin only` for other roles. Admin reads of messages/orders/profiles are not logged yet (P1-9): the admin UI must not be exposed to real data before that is addressed.

## 7. Evidence-link Edge Function

`POST /functions/v1/evidence-link`, `Authorization: Bearer <staff JWT>`, `verify_jwt = true` at the gateway.

Request: `{ "claimId": uuid, "evidenceIds": [uuid, 1..10], "purpose": string (≥5 chars), "ttlSeconds": integer 1..600 (default 120) }`

| Status | Body | When |
|---|---|---|
| 200 | `{ links: [{ evidenceId, url, expiresInSeconds }], note }` | authorised assigned reviewer; `expiresInSeconds` ≤ min(requested, 600, remaining grant); links cannot be revoked once issued |
| 400 | `invalid claimId` / `evidenceIds must be 1-10 uuids` / `ttlSeconds must be 1..600` / `purpose … required` / `invalid request` | validation |
| 401 | `authentication required` | missing/expired/anon token (also bad signature, via PostgREST) |
| 403 | `not authorised` | non-staff, not assigned, claim closed, evidence not on claim, no signed URL — **no ids/paths/reasons returned** |
| 429 | `too many requests, try later` | rate limit (audited) |
| 502 | `unexpected response` / `could not create link` | defence-in-depth mismatch (e.g. a malformed stored path, F-G) |
| 503 | `service unavailable` | database layer error |

Client rules: request links only when the reviewer opens a document; do not store URLs; do not log them; re-request after expiry (each call is audited). ⚠ CORS/OPTIONS is not implemented in `index.ts` — add before calling from a browser.

## 8. Privacy rules for the UI

- Never render supplier phone/email on public pages; the directory contract has no such fields. Contact is shown to staff/sellers only through the audited calls above.
- Buyer forms: collect consent explicitly (`p_consent`) and show the notice version; warn buyers not to type phone/email into free-text fields (sellers can read those fields before any reveal).
- Unclaimed profiles show `Unclaimed — Not Verified`; claimed-unverified show `Claimed — Not Verified`; only `is_verified` earns "Verified".
- Images: show only what the public image views return; display rights/attribution. Replace hotlinked Unsplash/Google Fonts/YouTube with self-hosted, licence-recorded assets or obtain consent before loading third-party resources; add a CSP and `Referrer-Policy`.
- No PII in URLs, `console`, error toasts or analytics events.

## 9. Open decisions for the owner
1. Claim-contact verification provider (P1-8) and cost/approval.
2. Whether the buyer-facing delivery wording is changed on the server (§4).
3. Retention periods and an erasure process (P1-5, P1-6).
4. Whether sellers may see `buyer_id` (P1-10).
5. Production treatment of `is_demo` rows (P1-3).

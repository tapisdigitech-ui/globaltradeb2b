# CURRENT STATE AUDIT (Phase 0) — 2026-11-07

Status legend: **Implemented** (code exists) · **Locally tested** · **Staging tested** · **Production deployed**.

## 1. Repository `tapisdigitech-ui/globaltradeb2b`
| Item | Finding |
|---|---|
| Branches | `main`, `redesign/homepage-v2` (remote). `redesign/homepage-v2` is an ancestor of `main`: every redesign commit is already in `main`. Local-only/feature: `feature/seller-enquiry-chat` (ea4d381, contained in main). |
| Tip of main | 31316d7 (For Buyers selection flow). Recent pushes to `main` were made at the owner's explicit request to see changes live on Vercel. **From this point all new work goes on `feature/*` branches; no pushes to main, no merges.** |
| Contents | `README.md`, `index.html` (single file, ~575 KB, ~4,965 lines). **No Next.js app, no `supabase/` folder, no migrations, no package.json in this repo.** |
| Backend code | None. `grep supabase index.html` = 0 hits. The prototype is not connected to any backend. |

## 2. Frontend prototype (index.html) — Implemented, locally tested (Playwright, 360–2560 px, zero horizontal overflow), deployed to production via Vercel Git link (static demo only)
Everything is demonstration data stored in browser `localStorage` (`gtb2b-*` keys: company, myprods, enquiries, chats, basket, buyer, admin, notifs, inbox, session, listdraft, photos…).

* **Public site**: homepage, categories, search, product page, supplier page, trending, per-category rows, hero banners, My Enquiries, Post Your Requirement, **For Buyers selection/requirement-list flow** (select product pictures, quantities, notes, buyer details → one enquiry per product).
* **List Your Business** 5-step wizard (details, business, company profile incl. GST/IEC/last-4 bank, products, publish) → creates a *demo* company + products in the browser.
* **Seller Centre** (shadow-DOM template `sellerTpl`): Home, Buy Leads, Messages (client chat with catalogue attach), More, products, profile, photos, brochures.
* **Admin Console** (`adminTpl`): browser-only moderation (reject/suspend/hide category, image licence note). Not a lead desk.
* **Claim Your Company**: only FAQ text and footer link. **No claim workflow exists.**

### Gaps vs the master brief (all missing, none are partially built)
Supplier-intelligence/ingestion, unclaimed/claimed/verified profile model, contact vault, claim + verification workflow, requirement matching engine, lead routing (Path A / Path B), admin lead desk, staff roles, notifications, reports, SEO pages (the site is a hash-routed SPA; not crawlable as separate URLs), image licence tracking in a database, any authentication.

### Risks in the prototype that must not be carried to production
1. Demo companies, prices, enquiry counts and "Delhi/Pune…" suppliers are fabricated samples; they must never appear as real suppliers or be mixed into real reports (brief Part 16).
2. Hotlinked Unsplash images illustrate categories only; they are not supplier inventory.
3. Auth is simulated in localStorage — no real security boundary exists.
4. Client-side only validation.

## 3. Supabase staging (`lhmexhafyuzojrmcbtbz`) — audited read-only (see EXISTING_SCHEMA_MAP.md)
*(Correction: an earlier version of this section said staging was unreachable. That was caused by the session's connector being pointed at a different account; it now reaches the GlobalTradeB2B organisation. Only the staging project was queried.)*

44 tables, RLS on all, empty except 14 categories. The Phase 2 foundation already covers: companies with directory/claim/verification states, private company contacts, field-level source provenance, import batches/rows with terms gate and rollback, claims + evidence + reviews, members, products/images with rights, enquiries with private buyer contact and audited reveal, quotations, orders, outreach events, follow-ups, internal notes, suppression list, audit log, rate limiting, private/public storage buckets.

### Findings that affect the brief
1. **Lead eligibility is too loose for Path A.** `seller_can_see_leads()` / `lead_matches_my_company()` only need an *approved claim + published* company; they do not require `verification_status='verified'`, verified contact details or profile completeness. Brief scenario 3 (claimed but unverified → no direct routing) is therefore **not satisfied**.
2. **Staff are not scoped by assignment.** `is_staff()` = any admin/reviewer; staff read all enquiries, claims, `company_private`. Brief requires access limited by assignment/role, plus admin visibility of staff activity.
3. **Contact vault is thin.** One row per company; no contact-level status, last_verified, source, legal basis, do-not-contact, and no read/export audit (only enquiry-buyer reveals are audited).
4. **No requirement model beyond quantity/unit/message/city/category**; no match table, no match explanation, no assignment/lead-status history, no delivery history beyond one `delivery` column, no duplicate protection.
5. **Claims lack email-token and phone-OTP verification and claim invitations.**
6. **Categories are flat** (no subcategories); `business_type` is a single text; no export markets/capabilities.
7. No demo/real flag for reporting (staging is empty, so none needed yet, but reports must exclude demo data once any is loaded).
8. Advisor items listed in EXISTING_SCHEMA_MAP.md.

### What can be reused unchanged
Provenance, import pipeline, claim review RPCs and evidence bucket, image rights/pending→public flow, enquiry privacy design (`enquiry_private`, `reveal_buyer_contact`), outreach logging semantics (`logged_manual` vs `sent` with provider_ref), audit_log, rate limiter.

## 4. Vercel
Project is Git-linked; a push to `main` deploys production (confirmed by GitHub commit status "success" per push). Preview URLs are produced for non-main branches. This session's shell cannot reach the deployed site (proxy 403); deployment status is read via the GitHub commit-status API only.

## 5. Phase 0 conclusion
Reusable: the UI components (cards, selection flow, wizard, seller/admin shells) and most of the Phase 2 backend foundation. New work is a targeted extension (see IMPLEMENTATION_ROADMAP.md gap list), not a rebuild.

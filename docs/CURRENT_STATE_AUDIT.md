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

## 3. Supabase staging (`lhmexhafyuzojrmcbtbz`) — **NOT AUDITED: BLOCKER**
The Supabase connector available in this session returns `permission denied` for the staging project (list_tables, list_migrations) and lists only one project, **TAPIS KASA STAGING** (`udtiszljbycvmvpwqodu`), which is explicitly out of scope and was **not** touched. The Phase 2 schema files (Phase 2.2 `p22/` scripts) live on the owner's machine, not in this repository.
Therefore: tables, RLS, functions, triggers, storage buckets/policies, views and grants are **unverified**. See `EXISTING_SCHEMA_MAP.md` for what is needed. No schema work will be proposed as final until this is resolved. No production-candidate project (`kwtveqzeayupwrxpwkce`) access was attempted.

## 4. Vercel
Project is Git-linked; a push to `main` deploys production (confirmed by GitHub commit status "success" per push). Preview URLs are produced for non-main branches. This session's shell cannot reach the deployed site (proxy 403); deployment status is read via the GitHub commit-status API only.

## 5. Phase 0 conclusion
Reusable: UI components (cards, selection flow, wizard, seller/admin shells), design tokens, enquiry/claim concepts as UX reference. Everything backend-related must be designed from the verified staging schema once available.

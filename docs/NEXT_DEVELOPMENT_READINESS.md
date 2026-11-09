# Next Development Readiness (Round 11, Docker-free)

Base commit `47f9160`; changes are uncommitted on `feature/supplier-intelligence-phase0`. Scope: this repository only. No Docker, hosted Supabase, migrations, credentials, emails/SMS or outreach were used. SQL was read as source only.

## 1. What actually exists (verified)
- **Does not exist:** `apps/platform`, `packages/*`, any `package.json`, CI, `.env.example`. There is no Next.js app yet.
- **Frontend:** `index.html`, a single-file demo (localStorage `gtb2b-*`, hash routing, simulated Seller/Admin/Lead-Desk modules). It is not connected to Supabase (a test now enforces this).
- **Backend (SQL):** baseline + 9 CLI migrations, tests, ops scripts, one Edge function (`evidence-link`). Validated only on a local PostgreSQL stand-in; **never on the real Supabase stack** (Round 10 is paused).

## 2. Readiness by area
| Area | Real (SQL/Edge, stand-in tested) | Demo-only (frontend) | Missing |
|---|---|---|---|
| Authentication & roles | `app_role`, `guard_profile_role`, RLS | Client-side role switch, `#admin` reachable by anyone | Real Auth UI/session, hosted Auth config (email confirmation, password length) |
| Supplier registration & claiming | `create_company_request`, `submit_claim`, `review_claim`, assignment-scoped reviewers | Onboarding wizard (localStorage) | Email-verification provider (F-H); invitation lifecycle fix (F-D) |
| Company verification | `set_verification`, admin-only publish | Badges are sample data | Re-verification on identity edits (F-B); `is_demo` in public views (F-C) |
| Product & catalogue | Guards, image guards | Seller product CRUD (local) | Pause→edit→republish bypass fix (F-A) |
| Buyer requirement | `create_requirement`, `submit_enquiry` | Enquiry modal + requirement form (local save) | Idempotency (F-J); server-side validation |
| Supplier matching | `_match_requirement` | None (simulated) | Real-stack run |
| Verified-only lead delivery | `_company_lead_eligible` | Labelled "(simulated)" | Sellers see `buyer_id` (F-I) |
| Admin Lead Desk | `admin_*`, `staff_*` RPCs | Simulated desk | Real UI; admin-read audit (F-O) |
| Staff permissions & audit | Assignment scoping, audit/log tables | None | Retention/purge (F-F), erasure (F-E) |

## 3. Gaps ranked by launch priority
Full table: `docs/PRIORITISED_LAUNCH_CHECKLIST.md`.
1. **P0:** real-stack validation on the Mac (paused); read-only check of hosted Auth settings; backup before any hosted write.
2. **P1:** one reviewed "0009-candidate" migration for F-A, F-B, F-C, F-D, F-G(1) (needs owner approval); decide email-verification provider; erasure/retention; seller lead view without `buyer_id`; idempotency.
3. **P1 (architecture):** decide whether to build the real Next.js app (`apps/platform`) or keep extending the demo. Integration rules: `docs/FRONTEND_BACKEND_INTEGRATION_CONTRACT.md`.
4. **P1 (frontend hygiene):** self-host fonts/images, CSP, XSS review of ~103 `innerHTML` sites, remove client-side admin.
5. **P2:** items in the checklist.

## 4. Changes made this round (`index.html`, frontend only)
- 320 px horizontal overflow fixed (grid children `min-width:0` / `minmax(0,1fr)`, Hindi banner, wrapping header).
- `<html lang="en">` added; switched Hindi/English snippets carry their own `lang`.
- Skip-to-content link.
- Enquiry and requirement forms: invalid field gets `aria-invalid`, receives focus, errors are announced (`role="alert"`); requirement form uses the same custom validation (`novalidate`).
- Three misleading copy lines made prototype-honest (FAQ, "How it works", seller onboarding).

Existing behaviour kept: demo ribbon, duplicate-submission guard, storage-unavailable warning.

## 5. Tests (all run without Docker or network)
`tests/frontend/static.test.mjs` (7) and `tests/frontend/ui.test.mjs` (8; Playwright Chromium, external requests blocked):
```
NODE_PATH=$(npm root -g) node --test tests/frontend/*.test.mjs        # 15 pass / 0 fail
node --test supabase/functions/evidence-link/*.test.mjs                # 27 pass / 0 fail
```
Playwright is resolved from the global install; no `package.json` exists yet (part of the architecture decision). Also: `bash -n` on every tracked `.sh` (clean); ESLint 10.1.0 with an ad-hoc config on `tests/frontend/*.mjs` (clean). `tsc` was not run: there is no TypeScript project, and the Edge `index.ts` needs Deno types. The SQL regression suite was not re-run (no SQL changed).

## 6. Not done / known limits
- Not tested: real Supabase stack, hosted Auth, Storage, Edge runtime (blocked/paused). Mac Docker cleanup untouched.
- Seller/Admin/Desk shells have no `<h1>` and some modal focus-trapping is unverified; a full screen-reader pass was not done.
- Hotlinked fonts/images remain; the demo needs network for them.

## 7. Next recommended task
Owner decision on the architecture (create `apps/platform` Next.js with `package.json` and CI, or continue the demo), and approval to draft the "0009-candidate" hardening migration for F-A..F-D, F-G(1) with regression tests on the local PG17 stand-in. Real-stack validation resumes when Docker on the Mac is available.

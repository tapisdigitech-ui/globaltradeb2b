# Phase 1.1 — Pre-Backend Hardening

Base commit `c8465ae` (branch `feature/supplier-intelligence-phase0`). Committed and pushed after owner approval (see git log). Scope: `apps/platform/`, `.github/workflows/platform-ci.yml`, and this document. The root prototype, SQL, migrations and Edge Functions are untouched. No hosted service, Docker, secret, deployment or external communication was used.

## 1. Changes
### 1.1 Demo verification badges (task 1)
- Demo records **never** use a status tone. `supplierBadge()` returns tone `sample` for every `isDemo` record: dashed amber outline, italic, white background, text `Sample label: <label> (illustrative, not a real status)`. The green "Verified" style and the bare word "Verified" can only be produced for a real (non-demo) verified record.
- The sample profile alert is now "Invented sample — no real verification"; the old "Verified profile (sample)" is gone. Unverified demo profiles still show the "Not verified / held by our team" notice.
- **No demo record carries the "Verified" label any more** (the former sample, "Sample Loom Works", is now "Claim Requested"). The directory filter "Verified" therefore returns the empty state until real data exists. Tests assert this.
- Tests: unit (tone, text, no `bg-success-100`, no bare "Verified" on any demo card), browser (computed style is dashed/italic, not success green; no bare "Verified" inside any card).

### 1.2 Security headers and CSP (task 2)
- **CSP** (`src/lib/csp.ts`, applied per request by `src/proxy.ts`, Next 16's replacement for middleware): `default-src 'self'`; `script-src 'self' 'nonce-…' 'strict-dynamic'` (no `unsafe-inline`/`unsafe-eval` in production; `unsafe-eval` only in development); `style-src 'self' 'nonce-…'`; `img-src 'self' data: blob:`; `font-src 'self'`; `connect-src 'self'`; `object-src 'none'`; `base-uri 'self'`; `form-action 'self'`; `frame-ancestors 'none'`.
- Consequence of nonces: **every page is now rendered dynamically** (root layout awaits `connection()`); no static prerendering. Chosen over `unsafe-inline` and over the experimental SRI mode. Cost is negligible for a prototype; revisit caching when real data is added.
- Static headers (`next.config.ts`): `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` (camera, microphone, geolocation, payment, usb, interest-cohort off), `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`, `Strict-Transport-Security: max-age=31536000` (no `includeSubDomains`/`preload`: owner decision once the domain is known). `X-Powered-By` removed.
- **Real defects found by the new tests and fixed:** (a) zod's JIT probe (`Function("")`) produced a CSP `script-src eval` violation on every form page → `z.config({ jitless: true })`; (b) a root `loading.tsx` made unknown suppliers return HTTP **200** instead of 404 → removed (note left in `States.tsx`).
- Not used: `upgrade-insecure-requests` (breaks plain-http local testing; HSTS covers production), CSP reporting endpoint (no backend), Trusted Types (not yet evaluated with Next).
- **When the backend is wired**, `connect-src` must gain the exact Supabase origin in the same change; a test should then assert it is the only extra origin.

### 1.3 Legal content (task 3)
- No legal text was written. `/legal/terms` and `/legal/privacy` are clearly marked "DRAFT placeholder — not legal advice" and only list the questions qualified counsel must decide (controller identity, applicable laws to be confirmed, retention, processors, supplier outreach basis, "Verified" meaning, liability, etc.).
- Every consent checkbox now carries "[Draft wording — pending legal review]" and links to the relevant draft page; footer links added. Tests assert the notice, the absence of policy-style commitments, and the links.

### 1.4 CI (task 4)
`.github/workflows/platform-ci.yml` is **manual only** (`on: workflow_dispatch`); no push or pull-request trigger is enabled. `permissions: contents: read`; no secrets; no deploy; 20-minute timeout; concurrency cancel; steps: `npm ci`, typecheck, lint, vitest, build, Playwright Chromium install, e2e, `npm audit --omit=dev`, failure artefacts.
Actions are pinned to full commit SHAs, verified against upstream tags on 2026-11-09 (each resolves to a commit object; the inputs used exist in each `action.yml`):
| Action | Version | SHA |
|---|---|---|
| actions/checkout | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| actions/setup-node | v7.1.0 | `949feb2413d6458794dcd2491c4babbbce0c15c1` |
| actions/upload-artifact | v7.0.2 | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` |
The workflow has never run on GitHub (YAML parses; the same commands pass locally). Private-repository Actions minutes may be billed; enabling automatic triggers needs owner approval. The prototype tests and SQL suite are not part of this workflow.

### 1.5 Public-page review (task 5)
| Area | Result |
|---|---|
| Privacy | no contact data in any public page (unit + browser), no external requests, no storage/cookies, no console errors, Referrer-Policy strict, forms discard input, search term is the only URL parameter |
| Accessibility | axe **WCAG 2.2 AA** (incl. colour contrast and target size) clean on 12 routes; skip link is first tab stop and moves focus to `<main>`; one `<h1>`, `lang`, landmarks on every route |
| Mobile | no horizontal overflow at 320 / 360 / 390 / 768 / 1280 px on 12 routes; 200 % text size at 320 px: header and content reflow (fixed: header wrapped, `overflow-wrap:anywhere`); touch targets ≥ 44 px for menu button, inputs and primary button |
| Other | `robots: noindex`; unknown supplier returns 404 |

## 2. Tests run (2026-11-09, Linux sandbox, Node 22.23.4)
| Check | Result |
|---|---|
| `tsc --noEmit` | pass |
| ESLint | pass, 0 warnings |
| Vitest | 4 files, **44 passed**, 0 failed |
| `next build` | success (all routes dynamic + Proxy) |
| Playwright | **22 passed**, 0 failed |
| `npm audit --omit=dev` | 0 vulnerabilities |
| `npm ci --dry-run` | lockfile consistent |
| Prototype frontend tests | 15 passed |
| Edge Function tests | 27 passed |
| Workflow YAML parse | OK (not run on GitHub) |

## 3. Remaining risks
1. CSP is verified only in Chromium against `next start`; Firefox/Safari untested. Nonce CSP disables static caching/CDN page caching.
2. CI has never run on GitHub (manual trigger only; SHAs pinned); automatic triggers and cost need approval.
3. `/dashboard` and `/admin/lead-desk` still have **no server-side access control** (labelled shells with synthetic data only).
4. Legal texts do not exist; the consent checkboxes are placeholders and must not be used to collect real personal data.
5. HSTS `max-age` is set without `includeSubDomains`/`preload`; confirm after the production domain is chosen. No HTTPS-redirect behaviour is tested.
6. No rate limiting/bot protection; no CSP violation reporting; no Trusted Types; no screen-reader (manual) testing; shell tab bars scroll horizontally at large text sizes.
7. The real Supabase stack remains unvalidated (Round 10), so backend wiring stays gated.
8. Because no demo record is verified, the "green Verified" design has no on-screen example; it is covered only by unit tests until real data exists.

## 4. Recommended next step
Decide when to enable automatic CI triggers (cost); then Phase 2 (local-stack-only Supabase Auth + server-side session helper + route guards) once Round 10 is run on the Mac.

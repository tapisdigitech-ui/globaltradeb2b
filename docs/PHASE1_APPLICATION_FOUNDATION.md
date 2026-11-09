# Phase 1 — Application Foundation

Base commit `6e89f61`. Everything described here is **uncommitted** on `feature/supplier-intelligence-phase0` until the owner approves. Scope: this repository only. No Docker, hosted Supabase, project/branch creation, deployment, secrets or demo changes. `index.html` (the single-file demo) is untouched.

## 1. What this is — and is not
A separate Next.js application in `apps/platform/`: design system, eight page groups, validation, tests. It is **frontend only**: no backend call, no environment variable, no cookie/localStorage, no fake sign-in. Forms validate input, show a "preview only" notice and discard the data. Dashboard and Lead Desk are visibly-labelled **shells** with synthetic data.

## 2. Architecture
```
apps/platform/
  src/app/            routes (App Router): /, /suppliers, /suppliers/[slug], /requirements/new,
                      /register/supplier, /register, /login, /dashboard, /admin/lead-desk, + loading/error/not-found
  src/components/ui/  reusable accessible primitives: Button, Field (text/select/textarea/checkbox), Badge, DataTable, States (Empty, Loading, Alert, Card, PageHeader)
  src/components/layout/  SiteHeader (role-aware nav), SiteFooter, DemoBanner, PreviewShell
  src/features/       suppliers/ requirements/ auth/ forms/  (feature code; dashboard/ and lead-desk/ reserved for real data binding)
  src/lib/            domain types, label + delivery wording, role navigation, zod validation
  src/data/demo.ts    synthetic data only
  tests/              Vitest + Testing Library (unit/component)      e2e/  Playwright (browser)
```
Rules: UI primitives know nothing about the domain; features own their forms and data shape; `lib/` is pure and unit-tested; pages are thin. Server components by default; client components only where interaction is needed (header menu, forms).

### Dependency selection (checked against the npm registry on 2026-11-09)
| Package | Version | Why / compatibility |
|---|---|---|
| next | 16.4.5 | current; engines node ≥ 20.9; React 19 peer OK |
| react / react-dom | 19.3.1 | within next peer range |
| tailwindcss + @tailwindcss/postcss | 4.3.5 | v4 CSS-first `@theme` tokens |
| **typescript** | **6.0.3** | **not 7.0.2**: `typescript-eslint` (used by eslint-config-next) declares `typescript <6.1.0` |
| eslint | 9.39.5 | **not 10**: Next's bundled plugins still target ESLint ≤ 9 |
| vitest 5.1.0 + vite 8.3.7 + @vitejs/plugin-react 6.3.0 | | vitest 5 needs vite ≥ 6.4/8 and Node ^22.12; plugin-react 6 needs vite 8 |
| jsdom 31, Testing Library, axe-core 4.14 | | component tests / accessibility engine |
| @playwright/test | 1.63.0 | pinned to the Playwright whose Chromium is already installed (no download needed) |
| zod 4.6.7, clsx 2.1.1 | | validation; class merging |
Engines: Node ≥ 22.12 (sandbox 22.23.4). `npm audit --omit=dev`: **0 vulnerabilities**. Full audit: 1 moderate (`minimatch` ReDoS inside the ESLint toolchain, dev-only, no non-breaking fix); not shipped to users.
`apps/platform` has its own `package.json`/lockfile and is **not** a workspace of anything; the demo needs no tooling.

## 3. Design system
- **Tokens** (`globals.css`, Tailwind `@theme`): navy scale (structure), one accent (primary actions), ink/muted/line/surface/canvas, success/warning/danger/info pairs, radii, shadow, compact type scale (12–36 px), 4 px spacing grid. System font stack — no third-party font requests.
- **Components**: Button / ButtonLink (4 variants, ≥ 44 px touch target on small screens), TextField / SelectField / TextAreaField / CheckboxField (label, hint, error with `role="alert"`, `aria-invalid`, `aria-describedby`, required marker + screen-reader text), Badge + DemoBadge, DataTable (labelled scroll region, captions), EmptyState, LoadingState (`role=status`, `aria-busy`), Alert, Card, PageHeader, header with mobile disclosure menu (`aria-expanded`, `aria-current`).
- **Accessibility**: skip link, one `<h1>` per page, `lang="en"`, visible focus ring, reduced-motion, first invalid field focused on submit. Automated: axe WCAG 2.1 A/AA **including colour contrast** passes on all 10 tested routes.
- **Responsive**: verified at 320 / 390 / 768 / 1280 px with no horizontal page overflow on every route (the test caught and fixed one dashboard overflow).

## 4. Pages
| Page | Route | State |
|---|---|---|
| Homepage | `/` | hero, status-label explainer, 14 seed categories, 3 sample suppliers, how-it-works |
| Supplier directory | `/suppliers` | GET search form (works without JS): name/product, category, verification status; empty state |
| Supplier profile | `/suppliers/[slug]` | label badge, about, products, **no contact data**, status-specific notice; unknown slug → 404 |
| Requirement submission | `/requirements/new` | validated form, preview-only result, explains the three server delivery states |
| Supplier registration | `/register/supplier` | validated claim form, states that registering ≠ verified |
| Account / sign in | `/register`, `/login` | validated; creates **no** session or account; no role choice |
| Supplier dashboard shell | `/dashboard` | company status, leads empty state, products table |
| Admin Lead Desk shell | `/admin/lead-desk` | synthetic requirement table with server delivery wording |

## 5. Safety properties (each is tested)
1. Public data types contain no phone/email/address/contact fields; rendered public pages contain no email, phone number, `mailto:` or `tel:`.
2. Only a record with `isVerified` can display "Verified"; inconsistent data degrades to "Unclaimed — Not Verified". Unclaimed/unverified cards never use the word "Verified" unqualified. Demo records say "· Demo sample".
3. Delivery copy never says sent / delivered / received; `visible_to_seller` says "we cannot confirm that they have read it".
4. Every demo card, profile and shell carries a Demo badge; a site-wide banner says nothing is connected.
5. Shells state "access control is not connected"; the layout always renders anonymous navigation. Role-aware navigation exists as a pure function (`navigationFor`) for previews and tests only.
6. Source scan: no `supabase`, `process.env`, `fetch(`, storage, cookies or `dangerouslySetInnerHTML` in `src/`. Forms write nothing to storage.
7. Security headers set in `next.config.ts` (nosniff, referrer policy, frame deny, permissions policy); `robots: noindex`.

## 6. Test results (run 2026-11-09, Linux sandbox, Node 22.23.4)
| Check | Command (in `apps/platform`) | Result |
|---|---|---|
| TypeScript | `npx tsc --noEmit` (strict, `noUncheckedIndexedAccess`) | pass, 0 errors |
| Lint | `npx eslint .` (next/core-web-vitals + typescript) | pass, 0 errors/warnings |
| Unit/component | `npx vitest run` | 3 files, **34 passed**, 0 failed |
| Production build | `npx next build` | success; 16 pages generated |
| Browser | `npx playwright test` (build first) | **13 passed**, 0 failed |
| Existing demo checks | `NODE_PATH=$(npm root -g) node --test tests/frontend/*.test.mjs` and `node --test supabase/functions/evidence-link/*.test.mjs` | 15 passed + 27 passed, 0 failed |
Coverage areas: navigation (links, current page, mobile menu, route existence), responsive (4 widths × 10 routes), form validation (empty, bad phone, mismatch, consent, focus, no storage, no network write), role presentation, public-contact protection, demo labelling, accessibility (axe), 404, empty states. Not covered: real keyboard/screen-reader testing, visual regression, Safari/Firefox (only Chromium), print.

## 7. Remaining gaps
- **No backend**: no auth, sessions, RLS-backed reads, `submit_enquiry`, Storage or Edge calls. Real-stack validation (Round 10) remains paused/unproven, so connecting is gated on it.
- No route protection exists; `/dashboard` and `/admin/lead-desk` must not receive real data until server-side session checks exist (contract §10).
- No CSP (needs nonce strategy), no rate limiting, no CAPTCHA/bot protection decision, no cookie/consent banner (none needed while nothing is stored).
- Legal texts (terms, privacy notice, consent wording, notice version) are placeholders.
- No images, logos, favicon or self-hosted font; no i18n (Hindi exists in the demo only); no pagination for large directories; search is substring over demo data.
- No product pages, categories pages, messaging, quotations, orders, notifications (SQL exists; UI not started).
- CI is not configured (GitHub Actions minutes may cost money; needs approval). `apps/platform` has no deployment config by design.
- Generated types from the database schema are not yet produced (needs a real schema source).

## 8. Next recommended step
Owner decisions: (a) approve committing this foundation; (b) approve a hardening migration (F-A…F-D, F-G(1)) before any hosted work; (c) when Docker on the Mac is available, finish Round 10. Then Phase 2: Supabase Auth integration in `apps/platform` behind a server-side session helper (still against a local stack only), starting with sign-in/up, profile and server-side route protection, and the read-only directory against `public_companies`.

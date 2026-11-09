# Phase 1.3 — Backend Integration Preparation

Base commit `e4f3046`, branch `feature/supplier-intelligence-phase0`. **Uncommitted** until approved. Scope: `apps/platform/` and documentation. SQL migrations, Edge Functions, the root prototype, CSP and `proxy.ts` are unchanged. No Supabase client, credential, session, network or database operation exists in the app. No hosted service, Docker or TAPIS project was used.

## 1. Architecture
```
src/contracts/        pure types + zod (safe to import anywhere, except private.ts)
  enums.ts            SQL enums mirrored in TS (drift-tested against the migrations as text)
  ids.ts              branded UUID ids (UserId, CompanyId, ClaimId, EnquiryId, CaseId)
  public-supplier.ts  PUBLIC DTO: strict zod schema + allow-list mapper from public_companies rows + forbidden-key tripwire
  private.ts          PRIVATE contact types (server-only usage)
  claims.ts           BusinessClaim, CompanyState, CompanyMembership, isEffectiveMember (mirrors SQL is_company_member)
  requirements.ts     RequirementInput, BuyerRequirement, SellerLeadView (NO buyerId), LeadCaseSummary, LeadAssignment, RequirementMatch
  staff-actions.ts    StaffAction union; purpose rule (>= 5 chars, mirrors the Edge Function)
src/server/           every file starts with `import "server-only"` (build error if a client component imports it)
  auth/types.ts       Session, AuthState (anonymous | authenticated | unavailable), SessionProvider, Actor
  auth/provider.ts    notConnectedSessionProvider: always "unavailable" (fail closed). The ONLY provider.
  access/permissions.ts  24 permissions, Resource facts, Decision/DenyCode
  access/policy.ts    evaluate(actor, permission, resource, {purpose}) — deny by default, exhaustive switch
  access/route-guards.ts RouteRequirement, decideRoute, guardRoute, AUTHENTICATED_PAGE_CACHE (NOT applied to any page)
  data/repositories.ts  Supplier/Claim/Requirement/Lead/StaffAction repository interfaces + DataAccess
  data/not-connected.ts the only implementation: every method rejects with NotConnectedError, no I/O
  services.ts         policy check THEN repository call; returns Result<T> with coarse error codes
  index.ts            `services` = createServices(notConnected provider, notConnected data)
tests/                contracts/, access/, services/, architecture.test.ts, fixtures.ts (test-only), stubs/server-only.ts
```
Layering rule: pages/actions → `services` → policy → repository. The database remains the authority (RLS, grants, SECURITY DEFINER RPCs); the app policy is defence in depth and a precise model to compare with Round 10 results.

## 2. Access-control model
Tenant boundary = **effective company membership**: `status = active` AND the company's `claim_status = approved` (SQL `is_company_member`/`has_company_role`). `app_role = seller` alone grants nothing.

| Capability | anonymous | buyer | seller (member) | reviewer | admin |
|---|---|---|---|---|---|
| Read public suppliers | yes | yes | yes | yes | yes |
| Create requirement / read **own** | – | yes | yes | yes | yes |
| Read company private data | – | – | owner, manager (own company) | – | – |
| Edit company profile | – | – | owner, manager | – | – |
| Edit catalogue | – | – | owner, manager, catalogue_editor | – | – |
| Submit / read own claim | – | yes | yes | yes | yes |
| Read / respond to lead | – | – | owner, manager, sales **and** lead delivered directly **and** company verified | – | – |
| Reveal buyer contact | – | – | as above **and** already responded | – | – |
| List assigned cases / update | – | – | – | assigned only | all |
| Open supplier/buyer contact | – | – | – | assigned + purpose | all + purpose |
| Review claim / evidence link | – | – | – | assigned claim (evidence also needs purpose) | all (evidence needs purpose) |
| Lead overview, assign, set verification, publish, routing | – | – | – | – | yes |
Principles: deny by default; unknown permission = deny; resource facts come from the server, never the client; staff gain **no** seller/buyer power over others' data; cross-tenant and missing records are indistinguishable (`forbidden`); unavailable auth is never treated as anonymous.
**Not yet verified against the real database**: the model was derived from the migration SQL as text. Round 10 must confirm each cell (especially admin vs assignment scope, which the SQL changed across migrations 0002/0005/0006).

## 3. Route guards (prepared, not applied)
`decideRoute(AuthState, requirement)` returns `allow | redirect-login | not-found | unavailable`. `seller-dashboard` needs an effective membership; `lead-desk` needs reviewer/admin; anyone else gets not-found (route existence hidden); unavailable auth shows an error, never content. With the shipped provider every guard answers `unavailable`. `/dashboard` and `/admin/lead-desk` do **not** call a guard and stay labelled "access control is not connected"; tests assert they import nothing from `src/server` and that no page claims to be secure. Guarded pages must also be dynamic with `Cache-Control: private, no-store`, re-check in every server action/route handler, and be protected by the database regardless.

## 4. Privacy protections
- Public DTO has no contact/identity/internal fields; `strictObject` rejects any extra key; mapper is an allow-list (never spreads); a recursive tripwire rejects 20 forbidden key names; label/flag consistency enforced ("Verified" ⇔ `isVerified`, verified ⇒ claimed); website restricted to http(s).
- Seller lead view has no `buyerId` (audit F-I) and no contact fields, enforced by a compile-time type assertion plus a runtime test. Buyer contact exists only as `BuyerPrivateContact`, returned by the separate reveal call after responding.
- `contracts/private.ts` may be imported only inside `src/server`; client files cannot import `src/server` (build-time `server-only` + test).
- Staff reveal requires a purpose (≥ 5 chars); evidence is link-only via the Edge function; error codes carry no ids or reasons.
- No storage, cookies, headers(), env access (except `NODE_ENV`), fetch or token-shaped strings in `src/` (scanned). Fixtures are test-only, synthetic, and contain no names, phones or emails.

## 5. Tests (run 2026-11-09, Node 22.23.4)
See §7 for exact results. New (98 tests): enum drift vs SQL (12), public contract (27), policy matrix (22), route guards (9), services incl. cross-tenant/unauthorised (18), architecture/CSP (10). Mutation check performed by hand: 7 deliberate policy/contract weakenings (reveal without responding, tenant check removed, purpose skipped, unavailable→allow, non-strict schema, unassigned reviewer allowed, membership status ignored) were each caught by at least 2 failing tests; all mutations reverted.

## 6. Future Supabase integration steps (not started)
1. **Gate:** complete Round 10 on the Mac (real GoTrue JWTs, PostgREST, Storage, Edge). Reconcile every cell of §2 and the `evaluate()` model with observed behaviour; record results; fix whichever side is wrong.
2. Decide Auth settings (email confirmation ON, password length ≥ 12; P0-2) in the local config first.
3. Add `@supabase/ssr` + `@supabase/supabase-js` (pin exact versions after checking compatibility), anon key only, via `NEXT_PUBLIC_SUPABASE_URL/ANON_KEY` pointing at the **local stack**. Add `.env.example` (names only).
4. Implement `SessionProvider` with `auth.getUser()` (server-validated), cookie sessions (HttpOnly/Secure/SameSite=Lax), then load `memberships` and `staffScope` from the database per request. Update the architecture test that currently allows exactly one provider file.
5. Add the Supabase origin to `connect-src` in the same change, with a test that it is the only extra origin; keep nonce CSP unchanged otherwise.
6. Implement repositories one at a time against views/RPCs with the **user's JWT** (never service-role): public reads first (`public_companies`), then requirements, claims, leads, staff. Each method gets a contract test against the local stack (including the cross-tenant cases already modelled here).
7. Apply `guardRoute` to `/dashboard` and `/admin/lead-desk` and make them dynamic/`no-store`; remove the preview-shell warnings only when guards and RLS are both verified.
8. Prerequisite database work (needs owner approval, separate migration round): F-A…F-D, F-G(1), seller lead view without `buyer_id` (F-I), idempotency (F-J).
9. Only after local success: owner-approved read-only checks of hosted staging; no hosted writes without the backup/restore drill (P0-3).

### Dependencies on Round 10
| Needs real stack | Why |
|---|---|
| Access matrix (§2) | confirm RLS/RPC behaviour per role and tenant |
| PostgREST error → HTTP mapping | services map SQLSTATEs to coarse codes today by assumption |
| Auth JWT claims / `getUser()` | session provider design |
| Storage + Edge evidence links | `requestEvidenceLinks` contract (401/403/429/502/503) |
| Signed URL expiry, rate limits | purpose and TTL rules |
| Backup/restore with Auth config | before any hosted use |

## 7. Results
Run in `apps/platform` with `npm run typecheck && npm run lint && npm test && npm run build && npm run test:e2e`:
| Check | Result |
|---|---|
| `tsc --noEmit` (strict) | pass |
| ESLint | pass, 0 warnings |
| Vitest | 10 files, **142 passed** (44 from earlier phases + 98 new), 0 failed |
| `next build` | success |
| Playwright (incl. axe WCAG 2.2 AA, CSP, responsive) | **22 passed**, 0 failed |
| `npm audit --omit=dev` | 0 vulnerabilities |
| `npm ci --dry-run` | OK (one new runtime dependency: `server-only@0.0.1`, exact) |
| Prototype frontend tests / Edge function tests | 15 / 27 passed |
| SQL / migrations / Edge sources | untouched (read as text by the drift test only) |

## 8. Remaining security gaps
No real authentication, sessions, or route protection (guards unused); policy model unverified against the real database; repositories unimplemented, so PostgREST mapping, rate limiting, idempotency and audit writes are untested; seller lead view relies on a database view that does not exist yet (F-I); no CSRF design for server actions yet (Next's origin check applies; to be reviewed); no CAPTCHA/bot control; legal texts still placeholders; CI never executed on GitHub.

## 9. Readiness for Phase 2
Ready to start **only** a local-stack-only Phase 2, and only after Round 10 (or an explicit owner decision to proceed in parallel against the local stack and treat Round 10 as its test bed). Not ready for hosted use.

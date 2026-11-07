# Round 8 — final security and hosted-readiness audit

Local audit only. Base commit `e4e474d` (local == remote, tree clean at start). PostgreSQL **16.15** local. No Supabase branch, no hosted migration or write, no production / production-candidate / TAPIS KASA access, no communications, no UI→Supabase connection. Staging was touched by **read-only statistics/catalogue SELECTs only** (table statistics for the invitation question; no row content).

## Verdict: **READY ONLY AFTER SPECIFIED LOCAL CHANGES**
The security design is internally consistent and fully reproducible locally (404 real-schema assertions, 138 legacy, 11 handler, 11 concurrency, all passing; 66/66 tables RLS-forced; no anon write or function access). An isolated hosted run would however fail or be uninformative today for reasons that are local, mechanical and listed below. None of them is a security hole in the validated chain; they are packaging and test-harness gaps, plus decisions only you can make.

### Blockers for the first isolated hosted validation (all local work)
| # | Blocker | Evidence | Needed change |
|---|---|---|---|
| B1 | Migrations are not in a layout a branch can replay | no `supabase/migrations/`, no `config.toml`; sequential names; staging history empty so a branch would be empty (Supabase docs: "The schema isn't cloned") | create CLI layout with timestamped baseline + 0001–0007; settle `begin/commit` handling |
| B2 | Test harness impersonates users with a local `app.uid` setting | `tests/real_schema_tests.sql`, `local_platform.sql` stub; real `auth.uid()` reads JWT claims | make the stub and suite use `request.jwt.claims` (same GUC Supabase uses) so the same suite can run on the branch unchanged |
| B3 | No synthetic seed | 14 `categories` rows not captured; branch is data-less | write a synthetic seed (no real data) |
| B4 | Edge Function config absent | no `config.toml`; checklist requires `verify_jwt=true` explicitly | add config and deployment notes |
| B5 | Identity sequences depend on platform default ACLs | with classic defaults 7 sequences gain `anon` USAGE (simulation `local_platform_classic_defaults.sql`; suite still 404/0) | small new migration revoking sequence privileges, or confirm branch defaults match staging first |
| B6 | Plan/cost not confirmed | org plan unknown; Pro-and-above per pricing page | your confirmation (approval item, not a code change) |

### Not blockers for a first branch, but blockers for staging/production
- Invitation transition decision and legacy count (§2). - URL validation (§3). - Admin message audit decision (§4). - The two NOT VALID constraints must be validated after clean-up.

## 1. Migration-chain audit
See `docs/MIGRATION_INVENTORY.md`. Summary: fresh empty DB → baseline + 0001–0007 reproduces the expected final schema (66 tables, 115 functions, 120 policies, 52 triggers, 106 indexes, 6 views); no duplicate tables; 27 intentional function redefinitions; all re-created policies preceded by drops; 66/66 RLS enabled and forced, 6 deliberate no-policy deny tables; all 97 definer functions pin `search_path`; extensions properly qualified; 8 storage policies on 5 buckets; rollback order 0007→0001 verified (normalised equal). Discrepancies documented: two baseline artifacts (legacy suite uses an older one), non-CLI layout, nested transactions, sequence ACL dependency, two NOT VALID constraints, one forward-fixed 0006 defect, nine accepted helper oracles. No historical migration was modified.

## 2. Legacy invitation transition
See `docs/INVITATION_TRANSITION_PROPOSAL.md`. Affected rows can only come from trusted-session hand inserts (the guard trigger always sets 14 days; `my_invitations()` already hid NULL). **The affected count is UNKNOWN**: an exact count needs a data query that this round's rules forbid; statistics views show zero DML since 2026-11-03 and 0 live tuples (suggestive, not proof). Proposal: retroactively apply the normal rule `created_at + 14 days`, log changes, validate the constraint; tests control 2/2, proposal 12/12; rollback restores NULLs from the log and leaves the function failing closed. Not applied.

## 3. URL-field inventory
See `docs/URL_FIELD_INVENTORY.md`. 3 anon-readable URL fields (`companies.website`, `public_company_sources.source_url`, `public_products.source_url`) have no scheme check (U2); staff-only URL fields unchecked (U3); demo UI interpolates `src` unescaped (U1, demo only); no redirect or server-side fetch exists in the repo (U4). Proposal `0009_url_validation_PROPOSAL.sql` (NOT VALID checks, `is_http_url`, `is_website_value`); tests control 2/2, proposal 9/9. Not applied.

## 4. Admin message-read audit review
See the "Round 8 review" section of `docs/ADMIN_MESSAGE_AUDIT_PROPOSAL.md`. Confirmed: four policies; audited `admin_open_comms`; 10-minute grant; logging gap for non-admin denials; UI changes required (no real admin console exists); rollback 0-line diff; tests control 2 / proposal 30. New finding: admins already have a second, weaker audited route (`staff_open_enquiry_comms`, 5-character purpose) for enquiry-scoped messages; only the thread scope is genuinely new. Other admin shortcuts remain (`orders`, `profiles.phone`, …). Kept separate and unapplied.

## 5. Security cross-review (one boundary)
Verified from the final local catalogue and code:
| Area | Result |
|---|---|
| Contact vault | `company_private` owner/manager only; `company_contacts` owner/manager select; staff reach contacts only via `staff_get_contacts` (staff + assignment + purpose + immutable log; `do_not_contact` values nulled). **No admin shortcut** |
| Buyer contact access | `enquiry_private` readable by the buyer or an active grant; sellers use `reveal_buyer_contact` (role, eligibility, lead-response precondition, 100/day, access log). `service_role` NULL-uid is refused (`has_company_role` false) |
| Supplier lead routing | visibility helpers are definer functions evaluated per caller; consistent with policies (tests SA/SF suites) |
| Claim evidence / signed URLs | table readable by claimant only; staff via `staff_request_evidence_links` (assignment, exact ids, ttl ≤600 s, rate limits, non-raising audit); storage `vd_read` requires claimant or active grant, so Edge signing with the *user's* JWT is gated twice. Message contract consistent: SQL raises `staff only`, Edge maps it to 403. Irrevocable after issuance (accepted) |
| Messages / quotations / orders | participant policies + admin shortcut (§4); F7/F8 hardening; orders keep `is_admin()` |
| Import pipeline | admin-only apply/rollback with immutable `company_import_audit`; rollback guard; regex fixed (F10) |
| Staff assignments | staff see only assigned cases/claims; admin sees all by design |
| Admin / reviewer | reviewer limited to open assigned claims (0005/0006); admin broad by design — the audit gap is the four message policies plus `profiles.phone`, `orders` |
| Audit logs | immutable via `block_mutation`, admin-read; **denials by non-admin callers raise and are not logged** (consistent design limitation across contact, evidence-open, comms, import) |
| Storage | 8 policies, folder-UUID path checks, per-bucket MIME/size limits; two public buckets by design |
| Edge Function | anon key + user JWT only; handler validates shape/expiry, platform verifies signature (`verify_jwt` must be set — B4) |
| Frontend expectations | the demo UI is localStorage-only; **no frontend ↔ SQL contract exists to compare**. Expectations that will bind later: `respond_quotation` now returns text (`'expired'` no longer an error), `accept_invitation` fails closed on NULL expiry, empty results (not errors) from `staff_open_claim_evidence` on denial, 'staff only' message mapping |
Inconsistencies found: (i) admin has two comms routes (§4); (ii) `profiles` exposes `phone` to all admins unaudited; (iii) one dead UPDATE grant on `product_group_items`; (iv) helper oracles; (v) sequence ACLs depend on platform defaults. None enables cross-tenant data access in the tested configuration.

## 6. PostgreSQL 17 / Supabase compatibility
`docs/HOSTED_PG17_VALIDATION_CHECKLIST.md` — 18 items each marked locally tested / catalogue-verified / unverified. Verified by catalogue against staging: the 13 definition kinds (Round 7). Locally tested only: all behaviour. Unverified: anything involving real JWTs, PostgREST, Storage, Edge runtime, PG 17 execution, pooler, realtime publications, auth settings.

## 7. Branch and cost readiness
`docs/BRANCH_LIFECYCLE_COST_ASSESSMENT.md`. Publicly verified: branching not on Free; Pro and above; $0.01344 per branch-hour on Micro (24 h $0.32, 48 h $0.65, 72 h $0.97); disk/egress/storage at parent rates; not covered by the Spend Cap. Org plan **not assumed**. Unknowns: plan, credit offset, billing rounding after deletion, copied Edge Functions. The reconstructed baseline must be the first replayed file; pre-apply checklist included. No branch created.

## Evidence index (all local, PG 16.15)
| Item | Result |
|---|---|
| Real-schema suite, baseline + 0001–0007 | 404 pass / 0 fail (re-run this round); also 404/0 with classic default privileges |
| Edge handler | 11/11; concurrency 11/11 |
| Proposals (unapplied, separate runners) | invitation 2 + 12; URL 2 + 9; admin audit 2 + 30; admin rollback 0-line diff |
| Legacy 138, rollback dry-runs | unchanged since `e4e474d` (no migration changed this round) |
| New files | docs listed above; `supabase/proposals/0007a_*`, `0009_*`; tests `tests/proposals/{invitation_transition,url_validation}_tests.sql`, runners `run_proposal_invitation.sh`, `run_proposal_urls.sh`; `baseline/local_platform_classic_defaults.sql`, `load_baseline_classic.sh` |

**Stopped after the report. No hosted action taken. Waiting for explicit approval.**

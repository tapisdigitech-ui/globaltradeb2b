# SECURITY IMPACT ASSESSMENT (Phase 0, pre-implementation)

| # | Risk introduced by the new system | Required control | Gate |
|---|---|---|---|
| 1 | Private contact vault leaks via public view/API/JS | Separate table + schema-level revoke from anon/authenticated; RLS by staff role and assignment; no joins from public views; automated test that anon/buyer/seller get 0 rows | Contact-privacy tests |
| 2 | Claim hijack (wrong person claims a company) | Expiring, hashed, rate-limited tokens; domain/website evidence; manual admin approval; never auto-approve on email/phone match; conflict → extra review; unique active claim per company | Claim tests |
| 3 | IDOR / privilege escalation (sellers reading other leads, staff reading unassigned) | RLS using `auth.uid()` ownership + role claims stored server-side; explicit grants; no trust in client role | Staff/seller tests |
| 4 | SECURITY DEFINER misuse | Each use documented, `SET search_path=''`, explicit `REVOKE ... FROM PUBLIC` then grant | Advisor + review |
| 5 | Verification documents exposure | Private bucket, per-owner policies, signed URLs, admin-only read | Storage tests |
| 6 | Ingestion legal/ethical risk | Source allow-list with per-source terms/robots/licence record, rate limits, provenance per field, review before publish, do-not-contact flag | Data policy sign-off |
| 7 | Image licensing | Per-image licence/source/attribution record, private pending bucket, approved public bucket | Image policy |
| 8 | Demo data contaminating real metrics | `is_demo` flag/ separate dataset; reports filter it | Report tests |
| 9 | Secrets | No service-role key in frontend or repo; env vars only in Vercel/Supabase | Secret scan |
| 10 | Outbound comms | Email/SMS integrations disabled by config until explicitly approved | Approval gate |

## Findings from the real staging schema (supersede the 'blocking dependency' note)
* **F1 (high, business logic):** direct lead visibility ignores `verification_status` (see CURRENT_STATE_AUDIT §3.1). Fix: route through a new eligibility function requiring approved claim + verified + published + verified contact + active member.
* **F2 (medium):** staff access is role-wide. Fix: assignment-scoped helper (`is_assigned_staff(case)`), keep admin = all, audit staff reads of the contact vault.
* **F3 (medium):** contact-vault reads are not audited. Fix: contact reads via an audited RPC; revoke direct SELECT for staff on the new contacts table.
* **F4 (info):** six SECURITY DEFINER public views flagged ERROR by the linter; intended, document in SECURITY_ARCHITECTURE.md and re-evaluate invoker views.
* **F5 (info):** 42 authenticated-executable SECURITY DEFINER RPCs; every new RPC must start with an explicit auth/role check, `search_path=public,pg_temp`, `REVOKE ... FROM PUBLIC, anon`.
* New objects follow existing patterns: RLS on, explicit grants, immutable logs via `block_mutation` trigger, RPC-only writes for status changes.

## Remediation status of findings F1–F3 (2026-11-07)
| Finding | Draft fix | Status |
|---|---|---|
| F1 lead eligibility ignores verification | `_company_lead_eligible()` + RLS read-time check (0002) | Implemented; locally tested (reconstructed baseline); **not staging verified** |
| F2 staff access role-wide | assignment-scoped helpers, policy replacements, reviewer scope on claims/docs (0002, 0005) | same |
| F3 contact reads not audited | purpose-required, assignment-scoped, immutable log with related case/claim; direct table access closed (0001, 0003) | same |
| F4 six SECURITY DEFINER views | investigation script prepared; needs real definitions | **open (B1)** |
| `cev_read` unscoped | not changed | **open (B3)** |

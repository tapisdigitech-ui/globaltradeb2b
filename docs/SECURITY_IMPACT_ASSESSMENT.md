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

**Blocking dependency:** the existing staging RLS/grants/functions posture (previous hardening) must be read before any migration is drafted so new objects follow the same patterns.

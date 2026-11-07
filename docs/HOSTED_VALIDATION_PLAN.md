# Hosted Supabase validation plan and branch cost (PLAN ONLY - nothing created)

Preconditions (all need explicit approval): a temporary Supabase branch of `globaltradeb2b-staging` (ref `lhmexhafyuzojrmcbtbz`, verify with get_project first), seeded with SYNTHETIC data only. No real emails/SMS/invitations (Auth email provider off or test-only addresses `*.example.test`), no supplier contact, no production or production-candidate project, no TAPIS KASA.

## Cost and lifetime estimate
- Supabase documents a branch at the default Micro compute at **$0.01344/hour**, no fixed fee, plus disk/egress/storage like the parent; branch usage is not covered by the Spend Cap ([Supabase docs](https://supabase.com/docs/guides/platform/manage-your-usage/branching)).
- 8 h session ~ $0.11; 24 h ~ $0.32; 72 h ~ $0.97; 7 days ~ $2.26. Expected lifetime: **1-2 working days** (apply, test, rollback, re-apply, delete). Storage/egress for a few test PDFs is negligible.
- Not confirmed from the docs page: which plan the organisation needs for branching, and whether the tool shows a confirmation price. The org (`GlobalTradeB2B`) plan is not visible to me; the create-branch cost confirmation must be shown to you before anything is created. Treat the plan fee (if the org is not already on a paid plan) as a possible extra cost.
- Delete the branch the same day validation finishes.

## Checklist (run in order; stop on first failure)
0. **Baseline migration first** (staging has 0 recorded migrations, so a branch would be empty): apply the reconstructed baseline, then compare catalogue with staging read-only. See `SUPABASE_BRANCH_COST_REPORT.md` (supersedes the cost numbers below with 48 h figures and plan caveats).
1. **Branch + baseline**: verify branch ref; dump schema/policies/grants/functions; compare with the local replica extract (catalogue diff must be 0 apart from known stubs).
2. **Apply 0001-0006** to the branch only; record errors; re-run local catalogue diff (policy/grant/trigger/setting equality).
3. **SQL suites** on the branch: legacy 138 + real-schema (post) 258; note which tests depend on stubbed functions.
4. **Auth**: create synthetic buyer, supplier owner, reviewer, admin via Auth admin API with real JWTs; confirm `auth.uid()` and `profiles.app_role`; confirm unconfirmed-email users cannot accept claims/invitations; confirm anon-key JWT is rejected by the Edge Function.
5. **PostgREST**: through the REST API with each JWT, repeat the key negative tests (unassigned reviewer reads of the 39 tables, `enquiry_private` direct select = 0 rows, rpc calls for admin-only functions return 403, anon cannot execute any staff/admin RPC). Check `Prefer`/`select=*` cannot reach hidden columns; check views `security_invoker` behaviour.
6. **Storage**: buckets exist with expected public/private flags; `verification-docs` private; upload by claimant to own claim path ok, to another claim path denied; overwrite denied; reviewer read denied before grant, allowed with grant + assignment, denied after expiry/unassign/revoke; `product-media-public` write admin only.
7. **Edge Function** (`evidence-link`, deployed to the branch only): `verify_jwt=true`; tests for 401 (no/anon/expired token), 400, 403 unassigned, 404 cross-claim id, 200 for assigned; confirm the function uses only the anon key.
8. **Signed URL expiry**: request ttl 5 s, fetch immediately (200), after 7 s (expect 400/403); request 600 s and confirm clamp to remaining grant; confirm ttl 601 refused. Record that a URL issued before revocation keeps working until expiry (expected; document the measured window).
9. **Access revocation**: admin unassigns reviewer / revokes grant; confirm new link requests fail at once, `enquiry_private` and comms reads stop, previously issued URL lifetime measured.
10. **Audit**: verify log rows (actor, purpose, ids/ttl) exist and are immutable via REST (PATCH/DELETE denied).
11. **Advisors**: run security + performance advisors; resolve or document findings.
12. **Rollback**: apply `down/0006_down.sql`, compare to baseline catalogue (expect 0 diff after whitespace normalisation), re-apply 0006, run suites again.
13. **Teardown**: delete the branch; confirm only the original staging remains and that it was never modified (migration list unchanged).

Pass criteria: 0 failing tests, 0 unexplained catalogue diffs, advisors clear of high findings, measured signed-URL behaviour documented.

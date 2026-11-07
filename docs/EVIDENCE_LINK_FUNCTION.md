# evidence-link Edge Function and reviewer UI design

STATUS: written and unit-tested locally with injected dependencies (`node --test supabase/functions/evidence-link/handler.test.mjs`, 9/9). **Not deployed. Hosted Supabase Storage behaviour (signed URL creation, expiry enforcement, RLS on storage.objects with a real JWT) is NOT verified.** Not connected to the demo or any supplier data.

Flow (`handler.mjs`; Deno wiring in `index.ts`):
1. Authentication: the caller's JWT is required (401 otherwise) and forwarded; only the anon key is used, no service role.
2. Validation: claimId and 1-10 evidence uuids, purpose >= 5 chars, ttlSeconds integer 1..600 (default 120) else 400.
3. Authorisation + grant: RPC `staff_open_claim_evidence` runs as the caller; it checks staff role and reviewer assignment on an open claim, logs the purpose, creates a 10-minute grant. Any refusal returns a generic 403.
4. Evidence ids not belonging to that claim return 404 and nothing is signed.
5. Signed URLs: `createSignedUrl` with the caller's JWT, so storage policy (grant + assignment) is evaluated when the link is CREATED. Correction: a signed URL is a bearer link and is not re-checked when used; failure returns 502/403, no partial output.
6. Audit: RPC `staff_record_evidence_links` (requires an active grant, ttl <= 600) logs "signed links issued (ttl Ns)". If auditing fails, links are discarded.
7. Revocation: assignment change, claim closure, grant expiry or admin revoke stop new links and storage reads; an already-issued URL stays valid until its own expiry (max 600 s) - an inherent limit of signed URLs.

Audit events: open (purpose), links issued (ttl), all in the immutable `claim_evidence_access_log`.

UI design (not built into live data): reviewer opens a claim, must type a purpose, sees evidence names, presses Open, gets links with a visible countdown, and a banner that access is logged. Admin sees the access log and a Revoke button. The existing Lead Desk demo in `index.html` stays simulated.


## Production-readiness review (round 5)
Fixed in code (13 local tests pass): anon-key/expired/malformed JWT rejected (401; signature itself must be verified by the platform with `verify_jwt=true`); storage path must be exactly `<claimId>/<plain file name>`; link lifetime clamped to the remaining 10-minute grant (previously a link issued at minute 9 could live to minute 19).

Open items (need approval, not changed):
1. `staff_record_evidence_links` logs only a count and ttl, not evidence ids, and does not verify the ids belong to the claim (the function does). Log ids and validate in SQL; would require regenerating the down script and re-running tests.
2. Signed URLs cannot be revoked after issue (max 600 s, now clamped to grant). For identity documents consider streaming through the function with a per-request grant check instead.
3. No rate limit on opening evidence; no request-size/CORS policy; all RPC errors map to 403 (infra errors should be 5xx with a request id); audit is written after signing (move to before, or write intent first).
4. Storage behaviour, `verify_jwt`, and signed URL expiry are unverified until the hosted run (see `HOSTED_VALIDATION_PLAN.md`).

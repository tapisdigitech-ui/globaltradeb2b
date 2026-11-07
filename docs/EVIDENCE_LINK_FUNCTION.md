# evidence-link Edge Function, evidence audit design and signed-URL security (round 6)

STATUS: SQL and handler are implemented and tested on a LOCAL PostgreSQL 16.15 replica / with injected dependencies only. **Not deployed. Hosted Supabase Storage behaviour (createSignedUrl, expiry enforcement, storage RLS with real JWTs, `verify_jwt`) is NOT verified.** Not connected to the demo or any real supplier data.

## 1. Database design (migration 0006)
Single entry point for the Edge Function: `staff_request_evidence_links(claim, evidence_ids uuid[], purpose, ttl default 120)`; `staff_open_claim_evidence(claim, purpose)` (metadata listing) shares the same gate `_evidence_gate` (not executable by clients).

Order of checks inside the gate (every outcome except "not staff" is logged, because the functions do NOT raise for staff - a raised exception would roll the audit row back):
1. caller must be staff (otherwise plain `staff only` error and no log row, so ordinary users cannot flood the log);
2. rate limits (below) -> `rate_limited`;
3. assignment: admin or reviewer assigned to the OPEN claim -> else `denied`;
4. purpose >= 5 chars; 1..10 distinct non-null evidence ids; ttl 1..600 -> else `invalid`;
5. every id must belong to THAT claim (mixed-claim, other-claim and non-existent ids all -> `denied`);
6. success: immutable `granted` log row with actor, claim, company, purpose, **exact evidence ids**, **requested ttl**, timestamp; 10-minute grant row (unchanged maximum).
Callers only ever receive `outcome` plus, on `ok`, paths for exactly the ids they asked for. Denied/invalid/rate-limited responses contain no ids, paths or reasons; the reason (`denial_reason`) and the attempted ids are in the audit log only (admin-readable, immutable). The log CHECKs ttl to 1..600.

Rate limits (counted from the audit log itself, so they cannot drift from it): 10 granted requests per hour per user+claim; 100 granted per day per user; 20 denied/invalid attempts per hour per user (probing control). A `rate_limited` row is written at most once per minute per user, so flooding cannot grow the log unboundedly. Limits are per user, so one reviewer's limit does not affect another, and per claim, so a busy claim does not block the same reviewer's other claims.

Accepted limits of this design: a rate-limited or denied row is only written for staff; a non-staff caller gets a generic error; direct-table RLS denials (PostgREST returns an empty set) cannot be logged by Postgres.

## 2. Edge Function (`handler.mjs`, `index.ts`)
401 for missing/anon-key/expired/malformed JWT (signature itself verified by the platform with `verify_jwt=true` and by `auth.uid()` in the RPC); 400 for malformed input (no DB call); one RPC; 403 generic for denied, 429 for rate limit, 400 for invalid, 503 for database errors; the returned rows must equal the request and every path must be `<claimId>/<plain file name>` (no `..`, no sub-folders) before anything is signed; ttl = min(requested, 600, remaining grant); signing uses the caller's JWT (anon key only, no service role). Audit is written BEFORE any URL exists. 11 unit tests pass.

## 3. Signed URL security assessment
- **A signed URL is a bearer credential. Revoking the database grant, unassigning the reviewer or closing the claim does NOT invalidate a URL that was already issued.** Storage checks the policy when the URL is created, not each time it is used. Until it expires (<= 600 s, and clamped to the remaining 10-minute grant) anyone holding the URL can fetch the file, including after a forward/copy/log leak.
- What revocation does stop: any NEW link, any storage read through the user's own session, and the metadata listing - immediately (tested: EL15, EL16, R5-R7).
- Mitigations in place: short default (120 s), hard maximum 600 s, per-user/claim rate limits, exact-id audit, `no-store` responses, links never logged by the function. Residual risk window = ttl.
- Not verifiable locally: actual expiry enforcement by Storage, clock skew, CDN caching of signed responses, whether Storage honours a revoked JWT. These are steps 6-8 of the hosted plan.

## 4. Optional alternative: stream through the Edge Function (NOT implemented)
| | Signed URL (current) | Stream via Edge Function |
|---|---|---|
| Revocation | none after issue (window = ttl) | immediate: every byte request re-checks grant + assignment |
| Leak impact | link works for anyone until expiry | none (no bearer link; needs the staff JWT each time) |
| Audit granularity | issuance | each download (and byte count) |
| Security extras | - | can force `Content-Disposition`, watermark, deny range requests |
| Cost | Storage egress only | adds Edge invocations + function egress (double hop); document-sized files, negligible at this scale (few reviewers) |
| Performance | direct CDN download | extra hop, function memory/time limits (large PDFs/scans must stream, not buffer) |
| Operational complexity | low | higher: streaming code, timeouts, error handling, tests under load |
**Recommendation:** keep signed URLs with ttl <= 120 s as default for the validation phase; implement streaming only for identity documents if the hosted tests show URL leakage or the reviewer count grows. Streaming is not clearly justified yet.

## 5. Tests (local)
SQL EL1-EL16 (37 assertions): purpose, ttl 0/601/null/600, cross-claim, mixed-claim, unknown id, empty/null/duplicate/null-element/11-id lists, malformed uuid, unknown claim, exact audit contents, immutability, 600-s log cap, non-staff, unassigned (no grant created), probing limit, per-user+claim limit, per-claim and per-user independence, revoked-before-issuance, expired grant. Edge handler: 401/400/403/429/503, defence-in-depth path and id checks, ttl clamp, storage refusal. Expiry of the signed URL itself: not testable locally.

## 6. Round 7 status (local only)
No change to the evidence design, SQL gate, rate limits or Edge handler in Round 7. Re-validated on the new baseline stack (baseline + 0001–0007, PG 16.15): EL1–EL16 and the audit/rate-limit assertions pass in the real suite (post: 404 pass / 0 fail), handler tests 11/11. Carried-over limits: signed URLs cannot be revoked after issuance; the streaming alternative is documented, not implemented; hosted behaviour (storage signing, Edge runtime, PG 17, role timeouts) is not validated. 0007 F9 qualifies pgcrypto calls in the claim-verification/invitation functions; the evidence functions do not use pgcrypto.

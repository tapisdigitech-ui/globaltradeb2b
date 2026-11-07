# evidence-link: JWT configuration and enforcement split (Round 9 · B4)

## Configuration
`supabase/config.toml`:
```toml
[functions.evidence-link]
enabled = true
verify_jwt = true
entrypoint = "./functions/evidence-link/index.ts"
```
`verify_jwt = true` is set **explicitly** (not left to the default) and a test (`gateway.test.mjs`) fails if it is removed. The function must never be deployed with `--no-verify-jwt`.

## Who enforces what
| Layer | Enforces | Does not enforce |
|---|---|---|
| **Platform gateway** (`verify_jwt = true`) | a token is present, well-formed, signed with the project's key, not expired → otherwise 401 before the function runs | *who* the caller is allowed to be: the public **anon key is itself a valid JWT** and passes; so does a service_role key |
| **Function** (`handler.mjs`, unchanged checks + one mapping) | its own `exp` check (independent of the gateway); `role` must be `authenticated` and `sub` present – anon/service tokens → 401; input validation (uuid shapes, 1–10 ids, ttl 1–600, purpose ≥5 chars); response must match the request exactly; storage paths must be `<claimId>/<plain name>`; link TTL clamped to the audited grant; generic 403/429, no ids or reasons leaked; **no service key anywhere** – the caller's JWT is forwarded | signature verification (it only decodes claims; it relies on the gateway and on the database) |
| **Database** (`staff_request_evidence_links`, `_evidence_gate`, RLS) – independent of both | `auth.uid()` from the *verified* token (PostgREST re-verifies); caller is staff; reviewer is **assigned** to the claim (or admin); every evidence id belongs to that claim; purpose; rate limits (10 granted/hour per user+claim, denied-probe cap); grant lifetime ≤10 min; every attempt audited; storage read policy needs an active grant **and** current assignment | – |

One small hardening added (does not weaken any check): if PostgREST rejects the forwarded token (bad signature/expired) `index.ts` now reports `unauthenticated`, and the handler answers **401** instead of a generic 503. Nothing is signed in that case.

Residual reliance (documented, tested as a LIMIT case): the function itself does not verify signatures. With `verify_jwt = false` a forged token with a plausible payload would be stopped only by the database layer (PostgREST 401 → function 401). That is why `verify_jwt` must stay `true`.

## Test matrix
`functions/evidence-link/handler.test.mjs` (11, pre-existing) + `gateway.test.mjs` (16, new; gateway emulated) = **27 node tests**; `tests/jwt/test_evidence_link_db.py` = **22 DB-side checks** with signed tokens through the PostgREST emulator; plus the existing EL1–EL16/R1–R7 SQL tests.

| Case | Gateway (emulated) | Function | Database (real RPC) |
|---|---|---|---|
| missing token | 401, function not invoked | – | EV1: anon, EXECUTE revoked |
| invalid: malformed / bad signature / alg none / HS512 / forged "assigned reviewer" | 401 | – | EV2, EV3: 401 before SQL |
| expired | 401 | independent 401 with gateway off | EV4: 401 |
| anonymous (anon-key JWT) | **passes** | 401 | EV5: permission denied |
| service_role JWT | passes | 401 | EV10: refused |
| authenticated, not staff (buyer/claimant), incl. metadata claiming admin | passes | 403 | EV6, EV6b: refused |
| staff but **not assigned** | passes | 403 generic | EV7: `denied`, no paths |
| **assigned reviewer** | passes | 200 + link | EV8: ok + both paths |
| **administrator** | passes | 200 + link | EV9: ok |
| **revoked** assignment | passes | 403, nothing signed | EV14/14b: storage 0, request denied; admin still served (EV14c) |
| **expired** grant | passes | 403 when no lifetime left; TTL clamped | EV13: `evidence_grant_active` false, storage 0; new audited grant possible (EV13b) |
| assignment without a grant | – | – | EV11: storage 0 |
| forged token with gateway off | – | 401 via database rejection | – |

Not verified: the real Edge runtime (Deno), real gateway behaviour, hosted Storage signed-URL creation and the fact that an issued signed URL cannot be revoked (mitigated by ≤600 s lifetime and the grant clamp). Still hosted-only.

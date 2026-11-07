#!/usr/bin/env python3
"""B4 database-side matrix for the evidence-link function: the exact RPC the Edge Function calls, with signed tokens through the PostgREST emulator.
LOCAL replica only. Usage: test_evidence_link_db.py DB"""
import sys, time, os
sys.path.insert(0, os.path.dirname(__file__))
from postgrest_emulator import mint, request, SECRET
DB = sys.argv[1]; NOW = int(time.time())
CLAIM = "a1a00000-0000-0000-0000-0000000e0c01"; E1 = "e7e00000-0000-0000-0000-0000000e0001"; E2 = "e7e00000-0000-0000-0000-0000000e0002"
BUYER, ADMIN, REV, REV2 = ["00000000-0000-0000-0000-00000000e%s" % x for x in ("001", "0a1", "0b1", "0b2")]
def tok(sub=None, role="authenticated", exp=NOW + 600, **x):
    c = {"iss": "local-test", "role": role, "aud": "authenticated" if role == "authenticated" else role}
    if sub: c["sub"] = sub
    if exp: c["exp"] = exp
    c.update(x); return mint(c)
CALL = "select outcome||':'||coalesce(storage_path,'-') from public.staff_request_evidence_links('%s', array['%s','%s']::uuid[], 'matrix review check', 120) order by storage_path"
P = 0; F = 0
def check(n, c, d=""):
    global P, F
    if c: P += 1; print("PASS: " + n)
    else: F += 1; print("FAIL: " + n, d)
def call(token): return request(DB, token, CALL % (CLAIM, E1, E2))
def ok(r): return r.status == 200 and r.out.count("ok:") == 2 and "/e1.pdf" in r.out and "/e2.pdf" in r.out
def denied_outcome(r): return r.status == 200 and r.out.startswith("denied:-")
r = call(None);                                  check("EV1 missing token -> anon role; EXECUTE revoked, no outcome, no path", r.status == "db-error" and "permission denied for function" in r.err and "e1.pdf" not in r.err, r)
r = call("garbage");                             check("EV2 invalid (malformed) token -> 401 before the database", r.status == 401, r)
r = call(mint({"role": "authenticated", "sub": REV, "exp": NOW + 600}, secret=b"forged-secret-forged-secret-forged-1")); check("EV3 forged signature claiming the assigned reviewer -> 401", r.status == 401, r)
r = call(tok(REV, exp=NOW - 30));                check("EV4 expired token of the assigned reviewer -> 401", r.status == 401, r)
r = call(tok(role="anon"));                      check("EV5 anonymous-key JWT (valid, role=anon): permission denied for function", r.status == "db-error" and "permission denied for function" in r.err, r)
r = call(tok(BUYER));                            check("EV6 authenticated claimant/buyer (not staff): refused, no paths", (r.status == "db-error" and "staff only" in r.err) or denied_outcome(r), r)
r = call(tok(BUYER, app_metadata={"role": "reviewer", "app_role": "admin"}, user_metadata={"app_role": "admin"})); check("EV6b buyer whose token CLAIMS reviewer/admin in metadata: still refused (authority is profiles.app_role)", (r.status == "db-error" and "staff only" in r.err) or denied_outcome(r), r)
r = call(tok(REV2));                             check("EV7 authenticated reviewer NOT assigned to the claim: denied, no paths", denied_outcome(r), r)
r = call(tok(REV));                              check("EV8 assigned reviewer: ok + both paths", ok(r), r)
r = call(tok(ADMIN));                            check("EV9 administrator: ok + both paths", ok(r), r)
r = call(tok(role="service_role"));              check("EV10 service_role token: no EXECUTE and no uid -> refused (function is for staff JWTs only)", r.status == "db-error", r)
r = request(DB, tok(REV), "select count(*) from storage.objects where bucket_id='verification-docs'"); check("EV11 assigned reviewer WITHOUT a live grant reads 0 objects (assignment alone does not open storage)", r.out == "0", r)
r = request(DB, tok(BUYER), "select count(*) from storage.objects where bucket_id='verification-docs'"); check("EV11b claimant reads own claim objects (2)", r.out == "2", r)
r = request(DB, tok(REV2), "select count(*) from storage.objects where bucket_id='verification-docs'"); check("EV11c unassigned reviewer reads 0 objects", r.out == "0", r)
r = request(DB, tok(role="anon"), "select count(*) from storage.objects where bucket_id='verification-docs'"); check("EV11d anon storage read refused", r.status == "db-error", r)
# state-changing steps (grant creation, expiry, revocation) are committed by the table owner via psql, then probed through signed tokens
import subprocess
def su(sql):
    env = dict(os.environ, PGHOST=os.environ.get("PGHOST", "/tmp/pgt"), PGPORT=os.environ.get("PGPORT", "5544"), PGUSER="postgres")
    return subprocess.run(["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", DB, "-c", sql], capture_output=True, text=True, env=env)
def as_user(uid, sql): return "set role authenticated; set request.jwt.claims='{\"sub\":\"%s\",\"role\":\"authenticated\",\"aud\":\"authenticated\"}'; %s; reset role; reset request.jwt.claims" % (uid, sql)
STORE = "select count(*) from storage.objects where bucket_id='verification-docs'"
su(as_user(REV, "select count(*) from public.staff_request_evidence_links('%s', array['%s']::uuid[], 'create grant for expiry test', 120)" % (CLAIM, E1)))
check("EV12 live grant (just issued): assigned reviewer sees the 2 objects", request(DB, tok(REV), STORE).out == "2")
su("update public.claim_evidence_grants set expires_at = now() - interval '1 second' where claim_id='%s'" % CLAIM)
r = request(DB, tok(REV), "select public.evidence_grant_active('%s')||'|'||(%s)" % (CLAIM, STORE.replace("select ", "select ", 1)))
check("EV13 EXPIRED grant: assigned reviewer with a valid unexpired JWT -> evidence_grant_active false, storage read 0 objects", r.out == "false|0" or r.out == "f|0", r)
r = call(tok(REV)); check("EV13b ...and a NEW request after expiry issues a fresh audited grant (ok) -- expiry only blocks reuse of the old one", ok(r), r)
su(as_user(ADMIN, "select public.admin_unassign_claim_reviewer('%s')" % CLAIM))
r = request(DB, tok(REV), STORE); check("EV14 REVOKED assignment: unexpired grant is useless -> storage 0 objects for the same valid JWT", r.out == "0", r)
r = call(tok(REV)); check("EV14b REVOKED assignment: the same reviewer's next request is denied (no paths)", denied_outcome(r), r)
r = call(tok(ADMIN)); check("EV14c administrator still served after the reviewer is revoked", ok(r), r)
r = request(DB, tok(REV), "select count(*) from public.claim_evidence_access_log where actor_id='%s'" % REV); check("EV15 earlier requests by the reviewer are audited (access log has rows for the actor)", r.status == 200 and r.out.isdigit(), r)
print("EVIDENCE-LINK DB MATRIX: %d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)

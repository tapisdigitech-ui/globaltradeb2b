#!/usr/bin/env python3
"""JWT-claim behaviour tests against the LOCAL replica via the PostgREST emulator. Usage: test_jwt_claims.py DBNAME
Synthetic HS256 tokens only. Proves how the DB reacts to claims PostgREST would hand it; does NOT prove GoTrue/gateway behaviour."""
import sys, time, os
sys.path.insert(0, os.path.dirname(__file__))
from postgrest_emulator import mint, request, SECRET

DB = sys.argv[1]; NOW = int(time.time())
B1, B2, AD, RV = ["00000000-0000-0000-0000-00000000e%s" % x for x in ("001", "002", "0a1", "0b1")]
def tok(sub=None, role="authenticated", aud="authenticated", exp=NOW + 3600, **extra):
    c = {"iss": "local-test"}
    if role is not None: c["role"] = role
    if aud is not None: c["aud"] = aud
    if sub: c["sub"] = sub
    if exp is not None: c["exp"] = exp
    c.update(extra); return mint(c)
passed = failed = 0
def check(name, cond, detail=""):
    global passed, failed
    if cond: passed += 1; print("PASS: %s" % name)
    else: failed += 1; print("FAIL: %s %s" % (name, detail))
def q(token, sql, **kw): return request(DB, token, sql, **kw)
def val(r): return r.out if r.status == 200 else None
def denied(r): return r.status == "db-error" and ("permission denied" in r.err or "row-level security" in r.err or "must be" in r.err or "not allowed" in r.err or "denied" in r.err.lower())

# ---- J1 claims -> auth.* functions
r = q(tok(B1), "select auth.uid(), auth.role(), current_user, session_user")
check("J1 authenticated token: auth.uid()=sub, auth.role()=authenticated, current_user=authenticated, session_user=authenticator", val(r) == "%s|authenticated|authenticated|authenticator" % B1, r)
r = q(tok(role="anon", aud=None), "select auth.uid() is null, auth.role(), current_user")
check("J2 anon-role token: uid null, role anon, current_user anon", val(r) == "t|anon|anon", r)
r = q(None, "select auth.uid() is null, auth.role() is null, current_user")
check("J3 no token at all: db-anon-role, no claims (auth.role() null)", val(r) == "t|t|anon", r)
r = q(tok(role="service_role", aud=None), "select auth.uid() is null, auth.role(), current_user")
check("J4 service_role token: no sub, auth.role()=service_role, current_user=service_role", val(r) == "t|service_role|service_role", r)
r = q(tok(B1, email="x@jwt-test.invalid"), "select auth.email(), auth.jwt()->>'aud', auth.jwt()->>'sub'")
check("J5 auth.email()/auth.jwt() expose email, aud, sub claims", val(r) == "x@jwt-test.invalid|authenticated|%s" % B1, r)

# ---- gateway-level token rejection (PostgREST never reaches the DB)
check("J6 bad signature rejected (401) before any SQL", q(mint({"role": "authenticated", "sub": B1, "exp": NOW + 99}, secret=b"wrong-secret-wrong-secret-wrong-sec"), "select 1").status == 401)
check("J7 expired token rejected (401)", q(tok(B1, exp=NOW - 5), "select 1").status == 401)
check("J8 alg=none token rejected (401)", q(mint({"role": "service_role", "exp": NOW + 99}, alg="none"), "select 1").status == 401)
check("J9 malformed token rejected (401)", q("not.a.jwt", "select 1").status == 401 and q("abc", "select 1").status == 401)
check("J10 HS512-labelled token rejected (alg allow-list = HS256)", q(mint({"role": "service_role", "exp": NOW + 99}, alg="HS512"), "select 1").status == 401)
check("J11 service_role claim with a forged signature rejected (cannot self-mint privilege)", q(mint({"role": "service_role", "exp": NOW + 99}, secret=b"attacker-secret-attacker-secret-1234"), "select 1").status == 401)
check("J11b token not yet valid (nbf in future) rejected", q(tok(B1, nbf=NOW + 600), "select 1").status == 401)

# ---- role claim handling by the DB role-switch
r = q(tok(B1, role="postgres"), "select 1")
check("J12 validly-signed token claiming role=postgres: authenticator cannot SET ROLE postgres", r.status == "db-error" and "permission denied to set role" in r.err, r)
r = q(tok(B1, role="supabase_admin"), "select 1")
check("J13 role claim naming a non-existent/privileged role fails in the DB", r.status == "db-error", r)
r = q(tok(B1, role=None), "select current_user")
check("J14 token without role claim falls back to db-anon-role", val(r) == "anon", r)
r = q(tok("not-a-uuid"), "select auth.uid()")
check("J15 non-UUID sub: auth.uid() errors (invalid uuid) -> request fails closed", r.status == "db-error" and "invalid input syntax for type uuid" in r.err, r)
r = q(tok(), "select count(*) from public.profiles")
check("J16 authenticated token with NO sub sees 0 profiles (uid null fails closed)", val(r) == "0", r)
r = q(tok(sub=""), "select auth.uid() is null")
check("J16b empty sub treated as null uid", val(r) == "t", r)

# ---- metadata cannot escalate privileges
r = q(tok(B1, app_metadata={"role": "admin", "app_role": "admin"}, user_metadata={"role": "admin", "app_role": "admin", "is_admin": True}), "select public.is_admin(), public.is_staff()")
check("J17 app_metadata/user_metadata claiming admin do NOT make is_admin()/is_staff() true (authority = profiles.app_role)", val(r) == "f|f", r)
r = q(tok(AD), "select public.is_admin(), public.is_staff()")
check("J18 real admin profile: is_admin() and is_staff() true", val(r) == "t|t", r)
r = q(tok(RV), "select public.is_admin(), public.is_staff()")
check("J19 reviewer profile: is_staff() true, is_admin() false", val(r) == "f|t", r)
r = q(tok(B1, role="authenticated", aud="some-other-audience"), "select auth.uid()")
check("J20 aud is NOT checked by the DB (a token with another aud reaches SQL unchanged) -- aud enforcement is a gateway/PostgREST job [hosted-only]", val(r) == B1, r)
r = q(tok(B1, aud="some-other-audience"), "select 1", expected_aud="authenticated")
check("J20b with a gateway that enforces aud=authenticated the same token is rejected (emulator option)", r.status == 401, r)

# ---- RLS through real claims
r = q(tok(B1), "select count(*), min(id::text) from public.profiles")
check("J21 buyer sees only own profile row", val(r) == "1|%s" % B1, r)
r = q(tok(AD), "select count(*) from public.profiles where id in ('%s','%s')" % (B1, B2))
check("J22 admin sees other users' profiles", val(r) == "2", r)
r = q(tok(RV), "select count(*) from public.profiles where id in ('%s','%s')" % (B1, B2))
check("J22b reviewer (is_staff, not admin) CANNOT read buyer profiles (0006 F-R8 hardening); admin can (admin phone read = Round-9 section G proposal)", val(r) == "0", r)
r = q(tok(role="anon", aud=None), "select count(*) from public.profiles")
check("J23 anon: no table privilege on profiles (permission denied)", denied(r), r)
r = q(tok(role="anon", aud=None), "select count(*) from public.companies")
check("J24 anon cannot read base table companies", denied(r), r)
r = q(tok(role="anon", aud=None), "select count(*) from public.categories")
check("J25 anon CAN read categories (public catalogue)", r.status == 200, r)
r = q(tok(role="anon", aud=None), "select public.is_admin()")
check("J26 anon cannot execute is_admin()", denied(r), r)
r = q(tok(B1), "update public.profiles set full_name='JWT Hacked' where id='%s'" % B2)
check("J27 buyer UPDATE of another user's profile affects 0 rows / is blocked", r.status == 200 and r.out == "" or denied(r), r)
r = q(tok(B1), "update public.profiles set app_role='admin' where id='%s' returning app_role" % B1)
check("J28 buyer cannot self-promote to admin via profiles update", (r.status == "db-error") or r.out != "admin", r)
r = q(tok(B1), "update public.profiles set full_name='JWT Buyer One b' where id='%s' returning full_name" % B1)
check("J29 buyer can update own profile (legit path still works)", val(r) == "JWT Buyer One b", r)
r = q(tok(B1), "select count(*) from public.audit_log")
check("J30 buyer cannot read audit_log", (val(r) == "0") or denied(r), r)
r = q(tok(AD), "select count(*) >= 0 from public.audit_log")
check("J31 admin can read audit_log", val(r) == "t", r)

# ---- service role
r = q(tok(role="service_role", aud=None), "select count(*) from public.profiles")
check("J32 service_role (BYPASSRLS) sees all profiles", val(r) is not None and int(val(r)) >= 4, r)
r = q(tok(role="service_role", aud=None), "select public.is_admin()")
check("J33 service_role has NO uid, so is_admin() is false even though it bypasses RLS", val(r) == "f", r)
r = q(tok(role="service_role", aud=None), "select nextval('public.audit_log_id_seq')")
check("J34 service_role has no sequence privilege on audit_log_id_seq after 0008", denied(r), r)


# ---- trusted-session semantics: is_trusted_session() = current_user in (postgres, service_role, supabase_admin)
r = q(tok(role="service_role", aud=None), "select public.is_trusted_session()")
check("J35 service_role token => is_trusted_session() true (current_user=service_role)", val(r) == "t", r)
r = q(tok(AD), "select public.is_trusted_session()")
check("J36 even an ADMIN user's token is not a trusted session (current_user=authenticated)", val(r) == "f", r)
r = q(tok(AD), "update public.companies set claim_status='approved' where slug='synthetic-evidence-co'")
check("J37 admin JWT cannot set a protected company column directly (guard: use the review RPCs)", r.status == "db-error" and "protected company column" in r.err, r)
r = q(tok(role="service_role", aud=None), "update public.companies set name=name where slug='synthetic-evidence-co'")
check("J38 service_role: BYPASSRLS but table ACLs (matching the staging catalogue) give it no UPDATE on companies -> permission denied; trusted writes go through SECURITY DEFINER RPCs", denied(r), r)
r = q(tok(role="service_role", aud=None), "select count(*) from public.companies")
check("J38b service_role can SELECT companies (RLS bypass, ACL select granted)", r.status == 200 and r.out.isdigit(), r)

print("JWT TESTS: %d passed, %d failed" % (passed, failed)); sys.exit(1 if failed else 0)

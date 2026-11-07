#!/usr/bin/env python3
"""LOCAL PostgREST/GoTrue request emulator for JWT-claim tests (stdlib only). NOT Supabase.
Mints synthetic HS256 tokens signed with a throw-away local secret, verifies them the way PostgREST does
(signature, alg, exp, nbf, optional aud), and then executes SQL exactly as PostgREST does per request:
    session_user = authenticator; BEGIN; SET LOCAL ROLE <role claim|anon>; set_config('request.jwt.claims', <payload>, true); <sql>; ROLLBACK
Everything it can't reproduce (GoTrue issuing tokens, key rotation, Kong/gateway, PostgREST pre-request hooks) is listed in docs/JWT_TEST_COVERAGE.md.
"""
import base64, hashlib, hmac, json, subprocess, time, os

SECRET = b"local-throwaway-secret-not-a-supabase-key-0123456789"   # synthetic; never a real key

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=")
def unb64(s): return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def mint(claims, secret=SECRET, alg="HS256", header_extra=None):
    h = {"alg": alg, "typ": "JWT"}; h.update(header_extra or {})
    seg = b64(json.dumps(h, separators=(",", ":")).encode()) + b"." + b64(json.dumps(claims, separators=(",", ":")).encode())
    sig = b"" if alg == "none" else b64(hmac.new(secret, seg, hashlib.sha256).digest())
    return (seg + b"." + sig).decode()

class AuthError(Exception):
    def __init__(self, status, msg): super().__init__(msg); self.status = status; self.msg = msg

def verify(token, secret=SECRET, now=None, expected_aud=None):
    """PostgREST semantics: HS256 only, signature checked, exp/nbf enforced, 'role' read from payload. Returns payload dict."""
    now = now or time.time()
    if token is None: return None            # no Authorization header -> anonymous (db-anon-role)
    parts = token.split(".")
    if len(parts) != 3: raise AuthError(401, "JWSError (CompactDecodeError)")
    try:
        header = json.loads(unb64(parts[0])); payload = json.loads(unb64(parts[1]))
    except Exception: raise AuthError(401, "JWSError (malformed)")
    if header.get("alg") != "HS256": raise AuthError(401, "JWSError (alg %s not accepted)" % header.get("alg"))
    good = b64(hmac.new(secret, (parts[0] + "." + parts[1]).encode(), hashlib.sha256).digest()).decode()
    if not hmac.compare_digest(good, parts[2]): raise AuthError(401, "JWSError JWSInvalidSignature")
    if "exp" in payload and payload["exp"] <= now: raise AuthError(401, "JWT expired")
    if "nbf" in payload and payload["nbf"] > now: raise AuthError(401, "JWT not yet valid")
    if expected_aud is not None and payload.get("aud") != expected_aud: raise AuthError(401, "JWT invalid claim: aud")
    return payload

class Result:
    def __init__(self, status, out="", err=""): self.status, self.out, self.err = status, out.strip(), err.strip()
    def __repr__(self): return "Result(%s, out=%r, err=%r)" % (self.status, self.out[:120], self.err[:160])

def request(db, token, sql, secret=SECRET, expected_aud=None, anon_role="anon", host=None, port=None):
    """Emulate one PostgREST request. Returns Result(status in {200,401,403/42501->'db-error'}, ...)."""
    try: payload = verify(token, secret, expected_aud=expected_aud)
    except AuthError as e: return Result(e.status, err=e.msg)
    role = anon_role if payload is None else payload.get("role", anon_role)
    claims = json.dumps(payload or {})
    q = lambda s: "'" + s.replace("'", "''") + "'"
    script = ("set session authorization authenticator;\nbegin;\n"
              "set local role \"%s\";\n" % role.replace('"', '') +
              "select set_config('request.jwt.claims', %s, true) \\g /dev/null\n" % q(claims) +
              sql.rstrip().rstrip(";") + ";\nrollback;\n")
    env = dict(os.environ, PGHOST=host or os.environ.get("PGHOST", "/tmp/pgt"), PGPORT=str(port or os.environ.get("PGPORT", "5544")), PGUSER="postgres")
    p = subprocess.run(["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", db], input=script, text=True, capture_output=True, env=env)
    if p.returncode != 0: return Result("db-error", p.stdout, p.stderr)
    return Result(200, p.stdout, p.stderr)

#!/usr/bin/env python3
"""Round 9.1: sequence privileges exercised by GENUINE non-owner, non-superuser roles with real JWT claims (PostgREST emulator:
session_user=authenticator -> SET LOCAL ROLE anon|authenticated|service_role). LOCAL replica only. Usage: test_sequence_roles.py DB
Why: tests that run as the table/sequence owner (or a superuser) pass even when a privilege is missing."""
import sys, os, time, subprocess, json
sys.path.insert(0, os.path.dirname(__file__))
from postgrest_emulator import mint, request
DB = sys.argv[1]; NOW = int(time.time())
BUYER, ADMIN = "00000000-0000-0000-0000-00000000e001", "00000000-0000-0000-0000-00000000e0a1"
def tok(sub=None, role="authenticated"):
    c = {"iss": "local-test", "role": role, "aud": role if role != "authenticated" else "authenticated", "exp": NOW + 600}
    if sub: c["sub"] = sub
    return mint(c)
PRINCIPALS = {"anon": tok(role="anon"), "authenticated(buyer)": tok(BUYER), "authenticated(admin)": tok(ADMIN), "service_role": tok(role="service_role")}
P = F = 0
def check(n, c, d=""):
    global P, F
    if c: P += 1; print("PASS: " + n)
    else: F += 1; print("FAIL: " + n, d)
def su(sql, tuples=True):
    env = dict(os.environ, PGHOST=os.environ.get("PGHOST", "/tmp/pgt"), PGPORT=os.environ.get("PGPORT", "5544"), PGUSER="postgres")
    p = subprocess.run(["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", DB, "-c", sql], capture_output=True, text=True, env=env)
    return p
def su_script(sql):
    env = dict(os.environ, PGHOST=os.environ.get("PGHOST", "/tmp/pgt"), PGPORT=os.environ.get("PGPORT", "5544"), PGUSER="postgres")
    return subprocess.run(["psql", "-X", "-q", "-At", "-d", DB], input=sql, capture_output=True, text=True, env=env)
SEQS = [l for l in su("select relname from pg_class where relkind='S' and relnamespace='public'::regnamespace order by 1").stdout.split() if l]
TBLS = {l.split("|")[0]: l.split("|")[1] for l in su("""select c.relname, a.attname from pg_class c join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  where c.relnamespace='public'::regnamespace and c.relkind='r' and (a.attidentity<>'' or exists(select 1 from pg_attrdef d where d.adrelid=c.oid and d.adnum=a.attnum and pg_get_expr(d.adbin,d.adrelid) like 'nextval(%')) order by 1""").stdout.split()}
check("T0 inventory: 13 sequences, 13 tables with identity/serial columns", len(SEQS) == 13 and len(TBLS) == 13, (len(SEQS), len(TBLS)))

# ---- run-as proof (item 9): the principals are not owners and not superusers
for name, t in PRINCIPALS.items():
    r = request(DB, t, "select current_user, session_user, (select rolsuper or rolbypassrls from pg_roles where rolname=current_user and rolname<>'service_role'), (select count(*) from pg_class where relnamespace='public'::regnamespace and pg_get_userbyid(relowner)=current_user)")
    u, s, sup, owned = (r.out.split("|") + ["", "", "", ""])[:4]
    check("R0 %s runs as non-owner, non-superuser (current_user=%s, session_user=%s, owns %s public relations)" % (name, u, s, owned), r.status == 200 and s == "authenticator" and owned == "0" and sup in ("f", ""), r)

# ---- sequence access matrix, genuine roles
def seq_ops(seq):
    q = "public." + seq
    return [("nextval", "select nextval('%s')" % q), ("currval", "select nextval('%s'); select currval('%s')" % (q, q)), ("setval", "select setval('%s', 1)" % q), ("select", "select last_value from %s" % q)]
for name, t in PRINCIPALS.items():
    bad = []
    for sq in SEQS:
        for op, sql in seq_ops(sq):
            r = request(DB, t, sql)
            allowed = r.status == 200
            expect = name.startswith("authenticated") and sq == "categories_id_seq" and op in ("nextval", "currval")
            if allowed != expect: bad.append("%s:%s" % (sq, op))
    check("S1 %s: nextval/currval/setval/SELECT on all 13 sequences refused (except authenticated nextval/currval on categories_id_seq) [violations: %s]" % (name, ", ".join(bad) or "none"), not bad)

# ---- direct INSERT matrix: which principal can write which table at all
res = {}
for name, t in PRINCIPALS.items():
    ok_tables, denied_tbl, other = [], 0, []
    for tb in TBLS:
        r = request(DB, t, "insert into public.%s default values" % tb)
        if r.status == 200: ok_tables.append(tb)
        elif "permission denied for table" in r.err: denied_tbl += 1
        else: other.append("%s(%s)" % (tb, r.err.split("\n")[0][:60]))
    res[name] = (ok_tables, denied_tbl, other)
check("S2 anon: no INSERT privilege on any of the 13 tables (13/13 'permission denied for table')", res["anon"][1] == 13 and not res["anon"][0], res["anon"])
sr_ok, sr_den, sr_oth = res["service_role"]
if sr_den == 13:
    check("S2b service_role: NO INSERT privilege on any of the 13 tables (staging ACL: public default gives service_role only D/x/t) -> no direct service-role insert workflow exists; its writes are SECURITY DEFINER RPCs", True)
else:
    # classic-default platform simulation: later-created tables carry ALL for service_role. Inserts must get past the ACL and fail only on column constraints, never on a sequence.
    seqdenied = [o for o in sr_oth if "sequence" in o]
    check("S2b (classic-default platform) service_role HAS table INSERT on %d tables; none of those inserts is stopped by a sequence ('permission denied for sequence') [%s]" % (len(sr_oth), seqdenied or "none"), not seqdenied and not sr_ok and all(("null value" in o or "violates" in o) for o in sr_oth), res["service_role"])
check("S2c authenticated(buyer): 12/13 table-privilege refusals; the 13th (categories) is stopped by RLS, not by a sequence", res["authenticated(buyer)"][1] == 12 and not res["authenticated(buyer)"][0] and len(res["authenticated(buyer)"][2]) == 1 and "categories" in res["authenticated(buyer)"][2][0], res["authenticated(buyer)"])
r = request(DB, PRINCIPALS["authenticated(admin)"], "insert into public.categories(slug,name) values ('seq9-admin-cat','SYNTHETIC admin category') returning id")
check("S3 genuine non-owner admin (authenticated role) INSERT into categories succeeds through the sequence default (the ONLY direct sequence use)", r.status == 200 and r.out.isdigit() and int(r.out) > 14, r)

# ---- invariants over actual ACLs (catches a missing privilege AND an unneeded one)
rows = su("""select r.rolname, c.relname, a.attname, coalesce(pg_get_serial_sequence(format('public.%I',c.relname), a.attname), s.seqname) seq, a.attidentity::text
  from (values ('anon'),('authenticated'),('service_role')) r(rolname)
  cross join pg_class c join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join lateral (select substring(pg_get_expr(d.adbin,d.adrelid) from 'nextval\\(''([^'']+)''') seqname from pg_attrdef d where d.adrelid=c.oid and d.adnum=a.attnum) s on true
  where c.relnamespace='public'::regnamespace and c.relkind='r' and has_table_privilege(r.rolname,c.oid,'insert') and (a.attidentity<>'' or s.seqname is not null) order by 1,2""").stdout.split()
missing = []
for l in rows:
    role, tb, col, seq, ident = (l.split("|") + [""] * 5)[:5]
    if ident == "" and seq:                      # serial default: INSERT needs USAGE on the sequence
        sq = seq.split(".")[-1].strip('"')
        if su("select has_sequence_privilege('%s','public.%s','USAGE')" % (role, sq)).stdout.strip() != "t": missing.append("%s->%s" % (role, sq))
check("I1 invariant: every role holding INSERT on a serial-default table has USAGE on that sequence (nothing is broken) [missing: %s]" % (", ".join(missing) or "none"), not missing)
extra = su("""select r.rolname||'->'||c.relname from (values ('anon'),('authenticated'),('service_role')) r(rolname) cross join pg_class c
  where c.relkind='S' and c.relnamespace='public'::regnamespace and (has_sequence_privilege(r.rolname,c.oid,'USAGE') or has_sequence_privilege(r.rolname,c.oid,'SELECT') or has_sequence_privilege(r.rolname,c.oid,'UPDATE'))
  and not exists (select 1 from pg_attribute a join pg_class t on t.oid=a.attrelid left join pg_attrdef d on d.adrelid=t.oid and d.adnum=a.attnum
        where a.attnum>0 and has_table_privilege(r.rolname,t.oid,'insert') and (pg_get_expr(d.adbin,d.adrelid) like '%'||c.relname||'%' or (a.attidentity<>'' and pg_get_serial_sequence(format('public.%I',t.relname),a.attname)='public.'||c.relname)))""").stdout.split()
check("I2 invariant: no role holds a sequence privilege without INSERT on a table that uses it (nothing unneeded) [extra: %s]" % (", ".join(extra) or "none"), not extra)

# ---- what-if control: would the sequence ACL matter if a role were later given INSERT?
sr_serial, sr_ident = [], []
for tb, col in TBLS.items():
    out = su_script("begin;\ngrant insert on public.%s to service_role;\nset local role service_role;\ninsert into public.%s default values;\nrollback;\n" % (tb, tb)).stderr
    kind = "serial" if su("select attidentity='' from pg_attribute where attrelid='public.%s'::regclass and attname='%s'" % (tb, col)).stdout.strip() == "t" else "identity"
    got_seq_denial = "permission denied for sequence" in out
    (sr_serial if kind == "serial" else sr_ident).append((tb, got_seq_denial, out.strip().split("\n")[-1][:80]))
check("W1 what-if: if service_role were later granted INSERT on a SERIAL-default table, the closed sequence ACL would refuse it ('permission denied for sequence') -> the rule 'grant USAGE together with INSERT' is enforced by I1", all(d for _, d, _ in sr_serial) and len(sr_serial) == 6, sr_serial)
check("W2 what-if: for IDENTITY columns PostgreSQL does not check sequence privileges on INSERT -> the 0008 revoke on the 7 identity sequences blocks only direct nextval/setval, never a table insert", not any(d for _, d, _ in sr_ident) and len(sr_ident) == 7, sr_ident)

# ---- legitimate definer workflows run by genuine non-owner principals (write + read-back as owner afterwards)
def as_role(role, claims, call, check_sql):
    s = "begin;\nset local role %s;\nselect set_config('request.jwt.claims', '%s', true) \\g /dev/null\n%s;\nreset role;\n%s;\nrollback;\n" % (role, claims, call, check_sql)
    return su_script(s)
SR = json.dumps({"role": "service_role"}); BU = json.dumps({"sub": BUYER, "role": "authenticated", "aud": "authenticated"}); AD = json.dumps({"sub": ADMIN, "role": "authenticated", "aud": "authenticated"})
p = as_role("service_role", SR, "select public.record_product_view('d0000000-0000-0000-0000-0000000e5e01','0123456789abcdef0123456789abcdef')", "select count(*) from public.product_view_events where viewer_hash='0123456789abcdef0123456789abcdef'")
check("F1 service_role calls record_product_view (SECURITY DEFINER; writes product_view_events via serial sequence it has no privilege on) -> row written", p.stdout.strip().endswith("1") and not p.stderr, (p.stdout, p.stderr))
p = as_role("authenticated", BU, "select public.create_company_request('SYNTHETIC Seq9 Co (not a supplier)','Manufacturer','Nowhere','synthetic')", "select count(*) from public.rate_events where user_id='%s' and action like '%%'" % BUYER)
check("F2 authenticated buyer: create_company_request -> check_rate writes rate_events through a definer path", not p.stderr and int((p.stdout.strip().split() or ['0'])[-1]) >= 1, (p.stdout, p.stderr))
p = as_role("service_role", SR, "select public.import_apply('00000000-0000-0000-0000-000000000000')", "select 1")
check("F3 service_role cannot drive import_apply (is_admin() needs a real admin uid): refused, nothing written", "admin only" in p.stderr, p.stderr)
p = as_role("service_role", SR, "select * from public.reveal_buyer_contact('00000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-000000000000')", "select 1")
check("F4 service_role cannot drive reveal_buyer_contact (needs a member uid): refused", p.stderr != "" and "ERROR" in p.stderr, p.stderr)
p = as_role("authenticated", AD, "select public.admin_assign_claim_reviewer('a1a00000-0000-0000-0000-0000000e0c01','00000000-0000-0000-0000-00000000e0b1')", "select count(*) from public.audit_log where actor_id='%s'" % ADMIN)
check("F5 admin (authenticated role) staff RPC writes audit_log via definer path", not p.stderr and int((p.stdout.strip().split() or ['0'])[-1]) >= 1, (p.stdout, p.stderr))

# ---- SECURITY DEFINER ownership / search_path safety (item 8)
q = lambda s: su(s).stdout.strip()
check("D1 every public function and every sequence/table is owned by one non-application role (postgres)", q("select string_agg(distinct pg_get_userbyid(o),',') from (select proowner o from pg_proc where pronamespace='public'::regnamespace union select relowner from pg_class where relnamespace='public'::regnamespace and relkind in ('r','S','v','p')) x") == "postgres")
check("D2 no SECURITY DEFINER function is owned by anon/authenticated/service_role", q("select count(*) from pg_proc where pronamespace='public'::regnamespace and prosecdef and pg_get_userbyid(proowner) in ('anon','authenticated','service_role','authenticator')") == "0")
check("D3 every SECURITY DEFINER function pins search_path", q("select count(*) from pg_proc where pronamespace='public'::regnamespace and prosecdef and not exists(select 1 from unnest(coalesce(proconfig,'{}')) c where c like 'search_path=%')") == "0")
check("D4 pinned paths contain only public/pg_temp/pg_catalog (no extensions, no $user), pg_temp never first", q("""select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%' and (c ~ '(extensions|\\$user|auth|storage)' or c ~ '^search_path=("?pg_temp"?)(,|$)'))""") == "0")
check("D5 anon/authenticated/service_role cannot CREATE in schema public (no object-shadowing path)", q("select bool_or(has_schema_privilege(r,'public','CREATE')) from unnest(array['anon','authenticated','service_role']) r") == "f")
check("D6 the writer functions of all 13 tables run as the sequence owner (owner of every writer = owner of every sequence)", q("select count(distinct o) from (select pg_get_userbyid(proowner) o from pg_proc where prosecdef and pronamespace='public'::regnamespace and pg_get_functiondef(oid) ~* 'insert\\s+into\\s+(public\\.)?(audit_log|categories|company_membership_audit|enquiry_contact_access|product_view_events|rate_events|buyer_contact_access_log|claim_evidence_access_log|company_import_audit|contact_access_log|lead_distribution_events|lead_status_history|staff_comms_access_log)\\y' union select pg_get_userbyid(relowner) from pg_class where relkind='S' and relnamespace='public'::regnamespace) x") == "1")
print("SEQUENCE ROLE TESTS: %d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)

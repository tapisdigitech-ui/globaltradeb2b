#!/usr/bin/env python3
"""Builds supabase/migrations_draft/baseline/0000_baseline_reconstructed.sql from the git-ignored read-only staging schema extract
(supabase/staging_schema/real_0*.sql). Platform stubs, local-only grants, extension objects and data are NOT included.
Grants are generated from the catalogue of a replica built by the legacy loader (staging_schema/load_real.sh), whose ACLs are then
verified against staging by baseline/compare (aclexplode fingerprints). Usage: python3 baseline/build_baseline.py"""
import re, subprocess, os, sys
os.environ.update(PGHOST='/tmp/pgt', PGPORT='5544', PGUSER='postgres')
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__))); ex=f'{root}/staging_schema'
def rd(f): return open(f'{ex}/{f}').read()
def strip_comments(t): return '\n'.join(l for l in t.split('\n') if not l.startswith('--'))
# 01: enums, sequences, tables (drop everything before the first public type: platform stubs)
b1=rd('real_01_base.sql'); b1=b1[b1.index('create type public.'):]
# 02: functions; keep one definition per signature (later "real body" blocks override earlier stubs), keep first position
f2=strip_comments(rd('real_02_functions.sql'))
parts=re.split(r'(?im)^(?=create or replace function )',f2)
order=[];defs={}
for p in parts:
    if not p.strip(): continue
    m=re.match(r'(?is)create or replace function\s+(public\.\w+)\s*\((.*?)\)\s*(returns|\n\s*returns)',p)
    key=(m.group(1).lower(),re.sub(r'\s+',' ',m.group(2)).lower()) if m else p[:80]
    if key not in defs: order.append(key)
    defs[key]=p.rstrip()+'\n'
f2=''.join(defs[k] for k in order)
c3=strip_comments(rd('real_03a_constraints.sql'))
r3=strip_comments(rd('real_03b_rls.sql'))
t3=rd('real_03c_triggers_views_grants.sql'); t3=strip_comments(t3[:t3.index('-- GRANTS as recorded')])
# explicit grants from a replica built by the legacy loader
subprocess.check_call(['bash',f'{ex}/load_real.sh','bl_acl_src'],stdout=subprocess.DEVNULL)
def q(sql): return subprocess.check_output(['psql','-d','bl_acl_src','-AtF','|','-c',sql]).decode().strip().split('\n')
PR={'a':'insert','r':'select','w':'update','d':'delete','D':'truncate','x':'references','t':'trigger','U':'usage','X':'execute'}
def parse(acl):
    out=[]
    for ent in acl.strip('{}').split(','):
        if not ent: continue
        who,rest=ent.split('=',1); privs=rest.split('/')[0]
        if who in ('postgres',''): continue
        out.append((who,[PR[c] for c in privs if c in PR]))   # 'm' (MAINTAIN) is PG17-only: omitted, documented
    return out
g=['-- ===== grants (generated from the verified ACL catalogue; PG17 MAINTAIN privilege omitted for PG16 reproducibility) ====='];
for rel,kind,acl in [r.split('|') for r in q("select c.relname,c.relkind,coalesce(c.relacl::text,'') from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','v','S') order by 1")]:
    obj={'r':'table','v':'table','S':'sequence'}[kind]
    g.append(f'revoke all on {obj} public.{rel} from anon, authenticated, service_role;')
    if kind=='S':   # sequence ACLs: the legacy replica was over-permissive; staging catalogue shows {postgres=rwU, authenticated=rU} for all six
        g.append(f'grant select, usage on sequence public.{rel} to authenticated;'); continue
    for who,pv in parse(acl):
        if pv: g.append(f'grant {", ".join(pv)} on {obj} public.{rel} to {who};')
g.append('revoke all on all functions in schema public from public, anon, authenticated, service_role;')
for sig,acl in [r.split('|') for r in q("select p.oid::regprocedure::text,coalesce(p.proacl::text,'') from pg_proc p where p.pronamespace='public'::regnamespace order by 1")]:
    for who,pv in parse(acl):
        if pv: g.append(f'grant execute on function public.{sig} to {who};')
buckets=q("select id,name,public,file_size_limit,allowed_mime_types::text from storage.buckets order by id")
bk=['-- ===== storage buckets (configuration rows; storage objects are never part of a baseline) =====','insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values']
bk.append(',\n'.join("  ('%s','%s','%s'::boolean,%s,'%s'::text[])"%tuple(b.split('|')[i] for i in range(5)) for b in buckets)+'\non conflict (id) do nothing;')
hdr='''-- PROPOSED BASELINE (reconstructed from a read-only catalogue extract of globaltradeb2b-staging). DRAFT - NOT APPLIED ANYWHERE.
-- Purpose: give a Supabase branch a schema (staging has an EMPTY migration history). Separate from migrations 0001-0006.
-- Excluded: auth/storage platform objects, extension objects, roles, secrets, all row data (categories seed = 14 rows, names not captured),
-- PG17 MAINTAIN privilege. Run with search_path = public, extensions (the Supabase default) so gin_trgm_ops resolves.
begin;
set local search_path = public, extensions;
'''
body='\n'.join([hdr,'-- ===== types, sequences, tables =====',b1,'-- ===== functions =====',f2,'-- ===== constraints and indexes =====',c3,'-- ===== row level security and policies =====',r3,'-- ===== triggers and views =====',t3,'\n'.join(g),'-- ===== table comments (data-classification notes present in staging) =====\n'+open(f'{root}/baseline/table_comments.sql').read(),'\n'.join(bk),'commit;\n'])
body=re.sub(r'\n{3,}','\n\n',body)
open(f'{root}/migrations_draft/baseline/0000_baseline_reconstructed.sql','w').write(body)
print('baseline lines:',body.count('\n'),'functions:',len(order),'grant stmts:',len(g))

-- B5 sequence privilege tests. Run after baseline+0001-0008 on a LOCAL DB (default OR classic-default-ACL platform simulation).
\set ON_ERROR_STOP off
create or replace function pg_temp.t(n text, c boolean) returns void language plpgsql as $$ begin if c then raise notice 'PASS: %', n; else raise notice 'FAIL: %', n; end if; end $$;
create temp table seqs as select c.oid as seqid, c.relname, d.refobjid::regclass::text as owned_by, (d.deptype='i') as is_identity
  from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_depend d on d.objid=c.oid and d.classid='pg_class'::regclass and d.refclassid='pg_class'::regclass and d.deptype in ('a','i')
  where c.relkind='S' and n.nspname='public';
grant select on seqs to public;
select pg_temp.t('SQ1 inventory: 13 sequences in public (7 identity + 6 serial-style, the six NOT marked OWNED BY, as in the hosted baseline), each backing a column', (select count(*)=13 and count(*) filter (where is_identity)=7 and count(*) filter (where not coalesce(is_identity,false) and exists(select 1 from pg_depend dd join pg_attrdef ad on ad.oid=dd.objid where dd.classid='pg_attrdef'::regclass and dd.refobjid=seqid))=6 from seqs));
select pg_temp.t('SQ2 ACL: anon holds NO privilege (USAGE/SELECT/UPDATE) on ANY sequence', (select not bool_or(has_sequence_privilege('anon',seqid,'USAGE') or has_sequence_privilege('anon',seqid,'SELECT') or has_sequence_privilege('anon',seqid,'UPDATE')) from seqs));
select pg_temp.t('SQ3 ACL: service_role holds NO privilege on ANY sequence (all writers are SECURITY DEFINER / owner-run)', (select not bool_or(has_sequence_privilege('service_role',seqid,'USAGE') or has_sequence_privilege('service_role',seqid,'SELECT') or has_sequence_privilege('service_role',seqid,'UPDATE')) from seqs));
select pg_temp.t('SQ4 ACL: authenticated holds USAGE only on categories_id_seq and nothing else', (select bool_and(case when relname='categories_id_seq' then has_sequence_privilege('authenticated',seqid,'USAGE') and not has_sequence_privilege('authenticated',seqid,'SELECT') and not has_sequence_privilege('authenticated',seqid,'UPDATE')
        else not (has_sequence_privilege('authenticated',seqid,'USAGE') or has_sequence_privilege('authenticated',seqid,'SELECT') or has_sequence_privilege('authenticated',seqid,'UPDATE')) end) from seqs));
select pg_temp.t('SQ5 ACL: PUBLIC pseudo-role holds nothing (aclitem grantee 0)', (select count(*)=0 from pg_class c, aclexplode(c.relacl) a where c.oid in (select seqid from seqs) and a.grantee=0));
select pg_temp.t('SQ6 raw ACL: only owner + authenticated(on categories_id_seq) appear in relacl', (select count(*)=0 from pg_class c, aclexplode(c.relacl) a where c.oid in (select seqid from seqs) and a.grantee not in (c.relowner) and not (c.relname='categories_id_seq' and a.grantee='authenticated'::regrole and a.privilege_type='USAGE')));
select pg_temp.t('SQ7 default privileges: no default ACL on sequences grants anon/authenticated/service_role in schema public', (select count(*)=0 from pg_default_acl d, aclexplode(d.defaclacl) a where d.defaclobjtype='S' and (d.defaclnamespace=0 or d.defaclnamespace='public'::regnamespace) and a.grantee in ('anon'::regrole,'authenticated'::regrole,'service_role'::regrole)));
create or replace function pg_temp.denied_msg(q text) returns text language plpgsql as $$ begin execute q; return 'ALLOWED'; exception when others then return sqlerrm; end $$;
grant execute on function pg_temp.denied_msg(text) to public;
-- attempts (each role, each sequence): all must fail except authenticated->categories
do $$ declare r record; who text; ok int; bad text := ''; begin
  for who in select unnest(array['anon','service_role','authenticated']) loop
    execute format('set local role %I', who);
    for r in select relname from seqs order by 1 loop
      begin perform nextval(format('public.%I', r.relname)::regclass); ok := 1; exception when insufficient_privilege then ok := 0; end;
      if (ok=1) <> (who='authenticated' and r.relname='categories_id_seq') then bad := bad || who||':nextval:'||r.relname||' '; end if;
      begin perform currval(format('public.%I', r.relname)::regclass); ok := 1; exception when insufficient_privilege then ok := 0; when object_not_in_prerequisite_state then ok := 1; end;
      if (ok=1) <> (who='authenticated' and r.relname='categories_id_seq') then bad := bad || who||':currval:'||r.relname||' '; end if;
      begin perform setval(format('public.%I', r.relname)::regclass, 1); ok := 1; exception when insufficient_privilege then ok := 0; end;
      if ok=1 then bad := bad || who||':setval:'||r.relname||' '; end if;
      begin perform last_value from pg_sequences where false; execute format('select last_value from public.%I', r.relname); ok := 1; exception when insufficient_privilege then ok := 0; end;
      if ok=1 then bad := bad || who||':select:'||r.relname||' '; end if;
    end loop;
    reset role;
  end loop;
  perform pg_temp.t('SQ8 attempts: nextval/currval/setval/direct SELECT by anon, service_role, authenticated on all 13 sequences are refused (only authenticated nextval/currval on categories_id_seq allowed) [violations: '||coalesce(nullif(bad,''),'none')||']', bad='');
end $$;
-- pg_sequences visibility: last_value is NULL (hidden) for roles without privilege
set role anon; select pg_temp.t('SQ9 pg_sequences.last_value hidden from anon (null)', (select bool_and(last_value is null) from pg_sequences where schemaname='public')); reset role;
-- legitimate inserts still work through the real paths
reset role; insert into auth.users(id,email) values ('00000000-0000-0000-0000-00000000e0a1','seq-admin@seq-test.invalid'),('00000000-0000-0000-0000-00000000e001','seq-buyer@seq-test.invalid') on conflict do nothing;
alter table public.profiles disable trigger user; update public.profiles set app_role='admin' where id='00000000-0000-0000-0000-00000000e0a1'; alter table public.profiles enable trigger user;
set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000e0a1","role":"authenticated","aud":"authenticated"}';
do $$ declare i int; begin insert into public.categories(slug,name) values ('seq-test-cat','Seq Test Category') returning id into i; perform pg_temp.t('SQ10 admin (authenticated role) INSERT into categories uses the sequence default and succeeds', i>0); exception when others then raise notice 'FAIL: SQ10 (%)', sqlerrm; end $$;
reset role; reset request.jwt.claims;
set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000e001","role":"authenticated","aud":"authenticated"}';
select pg_temp.t('SQ11 non-admin INSERT into categories still refused by RLS (not by sequence ACL)', (select pg_temp.denied_msg($q$insert into public.categories(slug,name) values ('seq-bad','x')$q$) like '%row-level security%'));
update public.profiles set full_name='Seq Buyer' where id='00000000-0000-0000-0000-00000000e001';
reset role; reset request.jwt.claims;
set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000e001","role":"authenticated","aud":"authenticated"}';
select pg_temp.t('SQ12 authenticated buyer RPC create_company_request (SECURITY DEFINER; inserts company, claim, membership + audit rows using sequences the caller cannot touch) succeeds', (select public.create_company_request('SYNTHETIC Seq Co (not a supplier)','Manufacturer','Nowhere','synthetic test') is not null));
reset role; reset request.jwt.claims;
select pg_temp.t('SQ12b ...and the company + claim rows it created exist', (select count(*)>=1 from public.companies where name like 'SYNTHETIC Seq Co%'));
select pg_temp.t('SQ12c create_company_request internally called check_rate(), a SECURITY DEFINER helper that inserted into rate_events via rate_events_id_seq (authenticated has no privilege on it): the rate_events row exists', (select count(*)>=1 from public.rate_events where user_id='00000000-0000-0000-0000-00000000e001'));
do $$ declare i bigint; begin insert into public.rate_events(user_id,action) values ('00000000-0000-0000-0000-00000000e001','seq-test') returning id into i; perform pg_temp.t('SQ13 OWNER-CONTROL ONLY (runs as the table owner, proves nothing about application privileges; see test_sequence_roles.py for genuine-role checks)', i>0); exception when others then raise notice 'FAIL: SQ13 (%)', sqlerrm; end $$;
-- the legitimate application path to rate_events: the SECURITY DEFINER rate-limit helper called as authenticated
select pg_temp.t('SQ14 rate_events and product_view_events are written only by SECURITY DEFINER functions (no direct table INSERT for authenticated)', (select not has_table_privilege('authenticated','public.rate_events','INSERT') and not has_table_privilege('authenticated','public.product_view_events','INSERT')));

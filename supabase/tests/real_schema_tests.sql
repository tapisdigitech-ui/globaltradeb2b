-- REAL-SCHEMA TEST SUITE
-- ENVIRONMENT: disposable LOCAL PostgreSQL 16 built from a read-only schema extract of globaltradeb2b-staging
-- (auth/storage platform schemas and 16 unrelated RPC bodies are stubs). THIS IS NOT STAGING. NOT PG17.
-- Usage: psql -v phase=pre|post -v post=0|1 -f tests/real_schema_tests.sql
--   pre  = replica + migrations 0001-0005 (exposure tests record existing gaps as controls)
--   post = replica + migrations 0001-0006 (same tests must show the gaps closed)
\set ON_ERROR_STOP on
\i tests/helpers.sql
select set_config('t.phase', :'phase', false);
create or replace function pg_temp.try(stmt text) returns boolean language plpgsql as $$ begin execute stmt; return true; exception when others then return false; end $$;
create or replace function pg_temp.gap(name text, exposed boolean) returns void language plpgsql as $$
begin
  if current_setting('t.phase')='pre' then raise notice '%: %', case when exposed then 'EXPOSED (pre-0006 control)' else 'not exposed (pre-0006)' end, name;
  elsif exposed then raise exception 'FAIL (still exposed after 0006): %', name;
  else raise notice 'PASS (closed): %', name; end if;
end $$;

-- stub fidelity: real Supabase grants authenticated access to storage.objects (RLS-governed)
grant select on storage.objects to authenticated;
-- ===== fixtures (superuser) =====
insert into auth.users(id,email,email_confirmed_at) select ('00000000-0000-0000-0000-0000000000'||n)::uuid, n||'@t.example', now() from unnest(array['a1','a2','a3','b1','b2','c1','c2','c5']) n;
update profiles set app_role='admin'    where id='00000000-0000-0000-0000-0000000000a1';
update profiles set app_role='reviewer' where id in ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000a3');
update profiles set app_role='seller'   where id in ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000c5');
insert into categories(id,slug,name) values (1,'rugs','Rugs'),(2,'chem','Chemicals');
insert into companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status) values
 ('c0000000-0000-0000-0000-000000000001','c1','C1 Verified Rugs','Bhadohi','India','draft','approved','verified','pending'),
 ('c0000000-0000-0000-0000-000000000002','c2','C2 Claimed Unverified','Delhi','India','draft','approved','not_verified','pending'),
 ('c0000000-0000-0000-0000-000000000003','c3','C3 Unclaimed','Jaipur','India','draft','unclaimed','not_verified','pending'),
 ('c0000000-0000-0000-0000-000000000005','c5','C5 Restricted','Agra','India','draft','approved','verified','pending'),
 ('c0000000-0000-0000-0000-000000000006','c6','C6 Suspended','Agra','India','draft','approved','verified','pending'),
 ('c0000000-0000-0000-0000-0000000000f1','cx','CX Contested','Pune','India','draft','claim_submitted','not_verified','pending');
insert into company_sources(company_id,field_name,source_type,source_name,source_url,collected_at) select id,'name','official_website','test','https://x.example',now() from companies;
update companies set data_review_status='approved', directory_status='published';
update companies set directory_status='suspended' where slug='c6';
update companies set lead_delivery_blocked=true where slug='c5';
insert into company_categories(company_id,category_id) select id,1 from companies;
insert into company_members(company_id,user_id,role,status) values
 ('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','owner','active'),
 ('c0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000c2','owner','active'),
 ('c0000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-0000000000c5','owner','active');
insert into company_contacts(company_id,kind,value,status,source_type,source_name,last_verified_at)
 select c.id,k,k||'-'||c.slug||'@x.example','verified','official_website','test',now() from companies c cross join unnest(array['email','phone']) k where c.claim_status='approved';
insert into company_private(company_id,phone,email,address) values ('c0000000-0000-0000-0000-000000000001','+91 98 SECRET','secret@c1.example','Private address 1');
insert into company_claims(id,company_id,claimant_id,statement,status) values
 ('a1a00000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b1','claim one','claim_submitted'),
 ('a1a00000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b2','claim two','claim_submitted');
set app.uid='00000000-0000-0000-0000-0000000000b1';
insert into company_claim_evidence(claim_id,storage_path,uploaded_by) values ('a1a00000-0000-0000-0000-000000000001','a1a00000-0000-0000-0000-000000000001/doc1.pdf','00000000-0000-0000-0000-0000000000b1');
set app.uid='00000000-0000-0000-0000-0000000000b2';
insert into company_claim_evidence(claim_id,storage_path,uploaded_by) values ('a1a00000-0000-0000-0000-000000000002','a1a00000-0000-0000-0000-000000000002/doc2.pdf','00000000-0000-0000-0000-0000000000b2');
reset app.uid;
insert into storage.objects(bucket_id,name) values ('verification-docs','a1a00000-0000-0000-0000-000000000001/doc1.pdf'),('verification-docs','a1a00000-0000-0000-0000-000000000002/doc2.pdf');
\if :post
  set app.uid='00000000-0000-0000-0000-0000000000a1';
  select public.admin_assign_claim_reviewer('a1a00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a2');
  reset app.uid;
\endif

-- ===== buyer requirement (real two-step flow) =====
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('buyer: submit_enquiry(requirement) stores, delivers to nobody', (select delivery::text from public.submit_enquiry('requirement',null,null,1,'Rugs 500 pcs',500,'Piece','need rugs','Bhadohi','Buyer One','+91 90000 11111','b1@example.com','BuyCo',true,'v1'))='stored');
reset role;
select id as r1 from enquiries where subject='Rugs 500 pcs' \gset
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('buyer: create_requirement matches', public.create_requirement(:'r1','Hand Tufted Rugs','wool','8x10','export','handmade','USA','60d','x') is not null);
select pg_temp.denied('duplicate requirement rejected', format($$select public.create_requirement(%L,'Hand  Tufted Rugs','wool','8x10','export','handmade','USA','60d','x')$$, :'r1'));
reset role; reset app.uid;

-- ===== routing (both phases) =====
select pg_temp.ok('C1 verified+eligible -> direct', (select route::text from requirement_matches where enquiry_id=:'r1' and company_id='c0000000-0000-0000-0000-000000000001')='direct');
select pg_temp.ok('C2 claimed-unverified -> admin desk', (select route::text from requirement_matches where enquiry_id=:'r1' and company_id='c0000000-0000-0000-0000-000000000002')='admin');
select pg_temp.ok('C3 unclaimed -> admin desk', (select route::text from requirement_matches where enquiry_id=:'r1' and company_id='c0000000-0000-0000-0000-000000000003')='admin');
select pg_temp.ok('C5 restricted never direct', coalesce((select route::text from requirement_matches where enquiry_id=:'r1' and company_id='c0000000-0000-0000-0000-000000000005'),'none')<>'direct');
select pg_temp.ok('C6 suspended never matched', (select count(*) from requirement_matches where company_id='c0000000-0000-0000-0000-000000000006')=0);
select pg_temp.ok('rules: cap 5, freshness 365d, verified email+phone required', (select max_direct_per_requirement=5 and contact_max_age_days=365 and require_verified_email and require_verified_phone from lead_routing_settings));
select pg_temp.ok('eligibility fn: C1 yes, C2 no, C3 no, C5 no, C6 no',
  public._company_lead_eligible('c0000000-0000-0000-0000-000000000001',1)
  and not public._company_lead_eligible('c0000000-0000-0000-0000-000000000002',1)
  and not public._company_lead_eligible('c0000000-0000-0000-0000-000000000003',1)
  and not public._company_lead_eligible('c0000000-0000-0000-0000-000000000005',1)
  and not public._company_lead_eligible('c0000000-0000-0000-0000-000000000006',1));
update company_contacts set last_verified_at=now()-interval '400 days' where company_id='c0000000-0000-0000-0000-000000000001';
select pg_temp.ok('stale contact (>365d) makes C1 ineligible', not public._company_lead_eligible('c0000000-0000-0000-0000-000000000001',1));
update company_contacts set last_verified_at=now() where company_id='c0000000-0000-0000-0000-000000000001';
select pg_temp.ok('fresh contacts restore eligibility', public._company_lead_eligible('c0000000-0000-0000-0000-000000000001',1));
select pg_temp.ok('no-category supplier ineligible', not public._company_lead_eligible('c0000000-0000-0000-0000-000000000001',2));

-- ===== cap of 5 direct deliveries per requirement (both phases) =====
insert into companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status)
 select ('c0000000-0000-0000-0000-0000000001'||lpad(n::text,2,'0'))::uuid,'k'||n,'K'||n||' Verified','Bhadohi','India','draft','approved','verified','pending' from generate_series(1,6) n;
insert into company_sources(company_id,field_name,source_type,source_name,source_url,collected_at) select id,'name','official_website','test','https://x.example',now() from companies where slug like 'k%';
update companies set data_review_status='approved', directory_status='published' where slug like 'k%';
insert into company_categories(company_id,category_id) select id,1 from companies where slug like 'k%';
insert into company_members(company_id,user_id,role,status) select id,'00000000-0000-0000-0000-0000000000c1','owner','active' from companies where slug like 'k%';
insert into company_contacts(company_id,kind,value,status,source_type,source_name,last_verified_at) select c.id,k,k||'-'||c.slug||'@x.example','verified','official_website','test',now() from companies c cross join unnest(array['email','phone']) k where c.slug like 'k%';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.ok('buyer2 requirement stored', (select delivery::text from public.submit_enquiry('requirement',null,null,1,'Rugs 900 pcs',900,'Piece','more rugs','Agra','Buyer Two','+91 90000 22222','b2@example.com','BuyCo2',true,'v1'))='stored');
reset role;
select id as r2 from enquiries where subject='Rugs 900 pcs' \gset
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.ok('buyer2 create_requirement', public.create_requirement(:'r2','Tufted Rugs','wool','6x9','export','handmade','UK','30d','x') is not null);
reset role; reset app.uid;
select pg_temp.ok('7 eligible suppliers -> exactly 5 direct (cap)', (select count(*) from requirement_matches where enquiry_id=:'r2' and route='direct')=5);
select pg_temp.ok('surplus eligible suppliers are not direct (routed to admin)', (select count(*) from requirement_matches where enquiry_id=:'r2' and route<>'direct' and company_id in (select id from companies where slug like 'k%' or slug='c1'))=2);
select pg_temp.ok('duplicate delivery impossible (unique enquiry+company)', not pg_temp.try(format($$insert into requirement_matches(enquiry_id,company_id,score,reasons,route) select enquiry_id,company_id,score,reasons,route from requirement_matches where enquiry_id=%L limit 1$$, :'r2')));

-- ===== EXPOSURE TESTS (pre: record; post: must be closed) =====
-- E1/E2: unverified claimed seller C2 acting on a lead it was never delivered
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c2';
select pg_temp.gap('E2 unverified seller responds to a lead (respond_to_lead)', pg_temp.try(format($$select public.respond_to_lead(%L,'c0000000-0000-0000-0000-000000000002')$$, :'r1')));
select pg_temp.gap('E1 unverified seller reveals buyer name/phone/email (reveal_buyer_contact, after respond_to_lead)', pg_temp.try(format($$select public.reveal_buyer_contact(%L,'c0000000-0000-0000-0000-000000000002')$$, :'r1')));
select pg_temp.gap('E3 unverified seller can see requirement in enquiries/notifications', (select count(*) from public.enquiries where id=:'r1')>0 or (select count(*) from public.notifications where kind='lead')>0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c5';
select pg_temp.try($$update public.companies set lead_delivery_blocked=false where slug='c5'$$);
select pg_temp.gap('E4 restricted seller clears own lead_delivery_blocked flag', (select count(*) from public.companies where slug='c5' and not lead_delivery_blocked)>0);
reset role; reset app.uid;
update companies set lead_delivery_blocked=true where slug='c5';
-- E5: seller-member (non owner/manager) reads private company contact vault columns
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c2';
select pg_temp.gap('E5 seller of ANOTHER company reads company_private of C1', (select count(*) from public.company_private)>0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.gap('E6 reviewer reads company_private directly', (select count(*) from public.company_private)>0);
select pg_temp.gap('E7 reviewer lists all profiles (incl buyer phone)', (select count(*) from public.profiles where app_role='buyer' or id='00000000-0000-0000-0000-0000000000b1')>0);
-- E8: reviewer a3 (not assigned to claim 1) reads that claim's evidence directly and decides it
select pg_temp.gap('E8 unassigned reviewer reads another claim''s evidence rows', (select count(*) from public.company_claim_evidence where claim_id='a1a00000-0000-0000-0000-000000000001')>0);
select pg_temp.gap('E9 unassigned reviewer reads evidence file object', (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000001/%')>0);
select pg_temp.gap('E10 unassigned reviewer can decide a claim (review_claim)', pg_temp.try($$select public.review_claim('a1a00000-0000-0000-0000-000000000001','evidence_requested','need docs')$$));
reset role; reset app.uid;

-- ===== claim approval gate (both phases) =====
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.denied('approval blocked while claimant email unverified (competing-claim block covered by 0004 gate; see report)', $$select public.review_claim('a1a00000-0000-0000-0000-000000000001','approved','try')$$);
reset role; reset app.uid;

-- ===== direct table access / function ACL (both phases) =====
set role anon;
select pg_temp.ok('anon cannot execute reveal_buyer_contact', not has_function_privilege('anon','public.reveal_buyer_contact(uuid,uuid)','execute'));
select pg_temp.ok('anon cannot execute respond_to_lead', not has_function_privilege('anon','public.respond_to_lead(uuid,uuid)','execute'));
select pg_temp.ok('anon cannot execute review_claim', not has_function_privilege('anon','public.review_claim(uuid,claim_status,text)','execute'));
select pg_temp.ok('anon cannot execute set_verification', not has_function_privilege('anon','public.set_verification(uuid,verification_status,text)','execute'));
select pg_temp.ok('anon has no read access to enquiries/company_claims/company_contacts/lead_cases', not pg_temp.try('select 1 from public.enquiries') and not pg_temp.try('select 1 from public.company_claims') and not pg_temp.try('select 1 from public.company_contacts') and not pg_temp.try('select 1 from public.lead_cases'));
reset role;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.denied('buyer cannot call set_verification', $$select public.set_verification('c0000000-0000-0000-0000-000000000002','verified','x')$$);
select pg_temp.denied('buyer cannot call review_claim', $$select public.review_claim('a1a00000-0000-0000-0000-000000000002','approved','x')$$);
select pg_temp.denied('buyer cannot self-promote to admin', $$update public.profiles set app_role='admin' where id=auth.uid()$$) ;
reset role; reset app.uid;
select pg_temp.ok('buyer role unchanged after attempt', (select app_role::text from profiles where id='00000000-0000-0000-0000-0000000000b2')<>'admin');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
set app.uid='00000000-0000-0000-0000-0000000000c2'; select pg_temp.try($$update public.companies set verification_status='verified' where slug='c2'$$);
reset role; select pg_temp.ok('seller cannot self-verify own company (status unchanged)', (select verification_status::text from companies where slug='c2')='not_verified'); set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
select pg_temp.denied('seller cannot call set_verification', $$select public.set_verification('c0000000-0000-0000-0000-000000000001','verified','x')$$);
select pg_temp.denied('seller cannot write requirement_matches', $$insert into public.requirement_matches(enquiry_id,company_id,score,reasons,route) values (gen_random_uuid(),'c0000000-0000-0000-0000-000000000001',50,'{}','direct')$$);
select pg_temp.denied('seller cannot insert lead_cases', $$insert into public.lead_cases(enquiry_id,queue) values (gen_random_uuid(),'unmatched')$$);
reset role; reset app.uid;

-- ===== buyer contact privacy (both phases): verified delivered seller C1 =====
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
select pg_temp.ok('C1 (delivered, eligible) can see the requirement match', (select count(*) from public.requirement_matches where enquiry_id=:'r1' and company_id='c0000000-0000-0000-0000-000000000001')=1);
select pg_temp.ok('C1 cannot read buyer phone from profiles directly', (select count(*) from public.profiles where id='00000000-0000-0000-0000-0000000000b1')=0);
select pg_temp.ok('C1 cannot read enquiry_private directly', pg_temp.cnt('select 1 from public.enquiry_private')=0);
reset role; reset app.uid;

-- ===== POST-ONLY: evidence access control =====
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('assigned reviewer a2 reads claim 1 evidence through audited RPC', (select count(*) from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000001','verify docs'))=1);
select pg_temp.ok('assigned reviewer a2 reads storage object only after grant', (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000001/%')=1);
select pg_temp.denied('assigned reviewer a2 cannot open claim 2 (not assigned)', $$select * from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000002','peek')$$);
select pg_temp.ok('a2 cannot read claim 2 storage object', (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000002/%')=0);
select pg_temp.denied('purpose required', $$select * from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000001','')$$, 'purpose');
select pg_temp.ok('a2 sees only its assigned claim', (select count(*) from public.company_claims where company_id='c0000000-0000-0000-0000-0000000000f1')=1);
select pg_temp.denied('audit log is not writable by staff', $$insert into public.claim_evidence_access_log(actor_id,claim_id,company_id,purpose,evidence_count) values (auth.uid(),gen_random_uuid(),gen_random_uuid(),'forged entry',0)$$, 'permission denied');
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('unassigned reviewer a3 denied RPC on claim 1', $$select * from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000001','peek')$$);
select pg_temp.ok('a3 sees zero contested claims', (select count(*) from public.company_claims where company_id='c0000000-0000-0000-0000-0000000000f1')=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('admin reads claim 2 evidence through RPC', (select count(*) from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000002','admin review'))=1);
select pg_temp.ok('admin reads claim audit log', (select count(*) from public.claim_evidence_access_log)>=2);
select pg_temp.denied('audit log update blocked even for admin', $$update public.claim_evidence_access_log set purpose='tampered'$$);
select pg_temp.denied('audit log delete blocked even for admin', $$delete from public.claim_evidence_access_log$$);
reset role; reset app.uid;
select pg_temp.ok('every RPC read logged (a2 claim1, admin claim2)', (select count(*) from claim_evidence_access_log where purpose in ('verify docs','admin review'))=2);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('claimant still reads own evidence', (select count(*) from public.company_claim_evidence where claim_id='a1a00000-0000-0000-0000-000000000001')=1);
select pg_temp.ok('other claimant cannot read claim 1 evidence', (select count(*) from public.company_claim_evidence where claim_id='a1a00000-0000-0000-0000-000000000002')=0);
reset role; reset app.uid;
\endif
\echo ALL REAL-SCHEMA TESTS COMPLETED (phase=:phase) ON LOCAL REPLICA

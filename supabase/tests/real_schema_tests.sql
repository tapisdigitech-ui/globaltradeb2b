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
insert into products(id,company_id,category_id,name,directory_status,data_review_status) values
 ('d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001',1,'Rug A','draft','pending'),
 ('d0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000002',1,'Rug B','draft','pending');
update products set data_review_status='approved', directory_status='published';
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

-- ===== DECISION 3: evidence upload / read / expiry / revoke / cross-claim (real schema) =====
grant insert on storage.objects to authenticated;   -- stub fidelity: real Supabase grants this; RLS policies (extracted from staging) decide
select pg_temp.ok('U0 verification-docs bucket is private and no policy grants it to anon/public',
  (select not public from storage.buckets where id='verification-docs')
  and not exists(select 1 from pg_policy p where p.polrelid='storage.objects'::regclass and pg_get_expr(coalesce(p.polqual,p.polwithcheck),p.polrelid) like '%verification-docs%' and (p.polroles='{0}' or exists(select 1 from pg_roles r where r.oid=any(p.polroles) and r.rolname='anon'))));
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('U1 claimant uploads evidence into their own open claim folder', pg_temp.try($$insert into storage.objects(bucket_id,name) values ('verification-docs','a1a00000-0000-0000-0000-000000000001/extra.pdf')$$));
select pg_temp.denied('U2 claimant cannot upload into another claimant''s claim folder', $$insert into storage.objects(bucket_id,name) values ('verification-docs','a1a00000-0000-0000-0000-000000000002/forged.pdf')$$);
select pg_temp.denied('U3 claimant cannot overwrite/replace an existing object (no update policy)', $$update storage.objects set name=name where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000001/%'$$) ;
reset role; reset app.uid;
select pg_temp.ok('U3b existing object untouched', (select count(*) from storage.objects where name='a1a00000-0000-0000-0000-000000000001/doc1.pdf')=1);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.denied('U4 assigned reviewer cannot upload evidence into the claim', $$insert into storage.objects(bucket_id,name) values ('verification-docs','a1a00000-0000-0000-0000-000000000001/staff.pdf')$$);
reset role; reset app.uid;
set role anon;
select pg_temp.denied('U5 anon cannot upload', $$insert into storage.objects(bucket_id,name) values ('verification-docs','a1a00000-0000-0000-0000-000000000001/anon.pdf')$$);
select pg_temp.ok('U5b anon cannot read evidence objects', not pg_temp.try($$select 1 from storage.objects where bucket_id='verification-docs'$$));
reset role;
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('R1 assigned reviewer with active grant reads claim-1 objects incl. the new upload (2 objects) and none of claim 2', (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000001/%')=2 and (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000002/%')=0);
select pg_temp.ok('R2 grant lifetime <= 10 minutes and signed-URL ceiling <= 600 s', (select max(access_expires_at) <= now()+interval '10 minutes 5 seconds' and max(max_signed_url_seconds) <= 600 from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000001','re-open to test ttl')));
reset role; reset app.uid;
update claim_evidence_grants set expires_at = now() - interval '1 minute' where claim_id='a1a00000-0000-0000-0000-000000000001';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('R3 expired grant: storage read denied again', (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000001/%')=0);
select pg_temp.ok('R4a re-opening is an audited RPC call returning the evidence row', (select count(*) from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000001','second review pass'))=1);
select pg_temp.ok('R4b after re-opening, storage read works again', (select count(*) from storage.objects where bucket_id='verification-docs' and name like 'a1a00000-0000-0000-0000-000000000001/%')=2);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('R5 unassigned reviewer cannot use a forged/planted grant', (select count(*) from storage.objects where bucket_id='verification-docs')=0);
reset role; reset app.uid;
insert into claim_evidence_grants(claim_id,staff_id,expires_at) values ('a1a00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a3',now()+interval '10 minutes');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('R5b planted grant without assignment still denied (storage + rows)', (select count(*) from storage.objects where bucket_id='verification-docs')=0 and (select count(*) from public.company_claim_evidence)=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('R6 admin revokes the reviewer assignment', pg_temp.try($$select public.admin_unassign_claim_reviewer('a1a00000-0000-0000-0000-000000000001')$$));
reset role; reset app.uid;
select pg_temp.ok('R6b grants for that claim deleted', (select count(*) from claim_evidence_grants where claim_id='a1a00000-0000-0000-0000-000000000001')=0);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('R7 revoked reviewer: storage read denied and RPC denied immediately', (select count(*) from storage.objects where bucket_id='verification-docs')=0 and not pg_temp.try($$select * from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000001','still trying')$$));
reset role; reset app.uid;
\endif

-- ===== seller notification rules (post; in-app rows only, nothing is sent) =====
\if :post
select pg_temp.ok('N1 eligible verified seller C1 has exactly one notification for requirement r1', (select count(*) from notifications where user_id='00000000-0000-0000-0000-0000000000c1' and kind='lead' and body='Hand Tufted Rugs')=1);
select pg_temp.ok('N2 claimed-but-unverified seller C2 has zero seller notifications', (select count(*) from notifications where user_id='00000000-0000-0000-0000-0000000000c2' and kind in ('lead','enquiry'))=0);
select pg_temp.ok('N3 restricted seller C5 has zero seller notifications', (select count(*) from notifications where user_id='00000000-0000-0000-0000-0000000000c5' and kind in ('lead','enquiry'))=0);
select pg_temp.ok('N4 unclaimed C3 has no members, so no notification target', (select count(*) from company_members where company_id='c0000000-0000-0000-0000-000000000003')=0);
select pg_temp.ok('N5 every lead notification matches a delivered_direct event', not exists(select 1 from notifications n where n.kind='lead' and not exists(select 1 from lead_distribution_events e where e.event='delivered_direct' and e.company_id=n.company_id)));
select pg_temp.ok('N6 notification count equals actual direct deliveries (r1:1 + r2:5 events, one per member)', (select count(*) from notifications where kind='lead')= (select count(*) from lead_distribution_events e join company_members m on m.company_id=e.company_id and m.role='owner' and m.status='active' where e.event='delivered_direct'));
\endif

-- ===== staff assignment isolation (real schema) =====
\if :post
select case_id1 from (select id as case_id1 from lead_cases where enquiry_id=:'r1') q \gset
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('admin assigns r1 case to reviewer a2', pg_temp.try(format($$select public.admin_assign_lead(%L,'00000000-0000-0000-0000-0000000000a2')$$, :'case_id1')));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('a2 sees exactly its assigned case and enquiry', (select count(*) from public.lead_cases)=1 and (select count(*) from public.enquiries where id=:'r1')=1);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('a3 sees no leads, no enquiries, no buyer-private rows of a2''s lead', (select count(*) from public.lead_cases)=0 and (select count(*) from public.enquiries)=0 and (select count(*) from public.enquiry_private)=0);
select pg_temp.denied('a3 cannot update a2''s case', format($$select public.staff_update_lead(%L,'contacted','x',null)$$, :'case_id1'));
select pg_temp.denied('a3 cannot mark a2''s enquiry', format($$select public.staff_mark_enquiry(%L,'awaiting_admin','x')$$, :'r1'));
reset role; reset app.uid;
\endif

-- ===== delivered seller vs others: buyer contact privacy (real schema) =====
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
select pg_temp.ok('V1 verified seller C1 responds to its delivered lead', pg_temp.try(format($$select public.respond_to_lead(%L,'c0000000-0000-0000-0000-000000000001')$$, :'r1')));
select pg_temp.ok('V2 and then reveals buyer contact (audited)', (select count(*) from public.reveal_buyer_contact(:'r1','c0000000-0000-0000-0000-000000000001'))=1);
reset role; reset app.uid;
select pg_temp.ok('V3 reveal wrote an access-log row', (select count(*) from enquiry_contact_access where enquiry_id=:'r1' and accessor_id='00000000-0000-0000-0000-0000000000c1')>=1);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c2';
select pg_temp.denied('V4 unverified seller C2 denied reveal for its own company', format($$select * from public.reveal_buyer_contact(%L,'c0000000-0000-0000-0000-000000000002')$$, :'r1'));
select pg_temp.denied('V5 seller C2 cannot reveal as C1 (another seller''s contacts)', format($$select * from public.reveal_buyer_contact(%L,'c0000000-0000-0000-0000-000000000001')$$, :'r1'));
select pg_temp.denied('V6 seller C2 cannot respond as C1', format($$select public.respond_to_lead(%L,'c0000000-0000-0000-0000-000000000001')$$, :'r1'));
select pg_temp.ok('V7 seller C2 sees zero enquiries, zero buyer-private rows', (select count(*) from public.enquiries)=0 and (select count(*) from public.enquiry_private)=0);
reset role; reset app.uid;
-- r2 (cap run): C1 is member only of C1 + K companies; C5 user is restricted
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c5';
select pg_temp.denied('V8 restricted seller C5 cannot reveal buyer contact', format($$select * from public.reveal_buyer_contact(%L,'c0000000-0000-0000-0000-000000000005')$$, :'r2'));
reset role; reset app.uid;
\endif

-- ===== product enquiries -> Admin Lead Desk workflow (post) =====
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.ok('P1 enquiry to claimed-unverified C2 is held for admin (not delivered)', (select delivery::text from public.submit_enquiry('product','d0000000-0000-0000-0000-000000000002',null,null,'Rug B price',10,'Piece','price?','Agra','Buyer Two','+91 90000 22222','b2@example.com','BuyCo2',true,'v1'))='awaiting_admin');
select pg_temp.ok('P2 enquiry to verified-eligible C1 is visible to seller', (select delivery::text from public.submit_enquiry('product','d0000000-0000-0000-0000-000000000001',null,null,'Rug A price',10,'Piece','price?','Agra','Buyer Two','+91 90000 22222','b2@example.com','BuyCo2',true,'v1'))='visible_to_seller');
reset role; reset app.uid;
select id as pe1 from enquiries where subject='Rug B price' \gset
select pg_temp.ok('P3 held enquiry has an Admin Lead Desk case (product_enquiry_review)', (select count(*) from lead_cases where enquiry_id=:'pe1' and queue='product_enquiry_review')=1);
select pg_temp.ok('P4 delivered enquiry has no desk case', (select count(*) from lead_cases lc join enquiries e on e.id=lc.enquiry_id where e.subject='Rug A price')=0);
select pg_temp.ok('P5 C1 seller notified of delivered enquiry only; C2 seller got nothing', (select count(*) from notifications where user_id='00000000-0000-0000-0000-0000000000c1' and kind='enquiry')=1 and (select count(*) from notifications where user_id='00000000-0000-0000-0000-0000000000c2' and kind='enquiry')=0);
select pg_temp.ok('P6 admins (not sellers) got the internal hold alert', (select count(*) from notifications where kind='admin' and user_id='00000000-0000-0000-0000-0000000000a1')>=1 and (select count(*) from notifications where kind='admin' and user_id in (select id from profiles where app_role='seller'))=0);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c2';
select pg_temp.ok('P7 C2 seller cannot see the held enquiry', (select count(*) from public.enquiries where id=:'pe1')=0);
reset role; reset app.uid;
select id as pc1 from lead_cases where enquiry_id=:'pe1' \gset
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('P8 admin assigns the held enquiry to reviewer a3', pg_temp.try(format($$select public.admin_assign_lead(%L,'00000000-0000-0000-0000-0000000000a3')$$, :'pc1')));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('P9 other staff (a2) cannot see a3''s held enquiry', (select count(*) from public.enquiries where id=:'pe1')=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('P10 assigned staff a3 sees the held enquiry', (select count(*) from public.enquiries where id=:'pe1')=1);
select pg_temp.denied('P11 release refused while supplier ineligible (cannot fake delivery)', format($$select public.staff_mark_enquiry(%L,'visible_to_seller','try')$$, :'pe1'), 'not eligible');
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.denied('P12 even admin cannot mark a requirement visible_to_seller manually', format($$select public.staff_mark_enquiry(%L,'visible_to_seller','try')$$, :'r1'), 'supplier matching');
reset role; reset app.uid;
select pg_temp.ok('P13 buyer-facing state still honest after refused release', (select delivery::text from enquiries where id=:'pe1')='awaiting_admin');
-- supplier completes verification later (simulated by superuser) then staff releases
update companies set verification_status='verified' where slug='c2';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('P14 after supplier becomes eligible, assigned staff releases', pg_temp.try(format($$select public.staff_mark_enquiry(%L,'visible_to_seller','released after verification')$$, :'pe1')));
reset role; reset app.uid;
select pg_temp.ok('P15 release notifies the seller once and closes the desk case', (select count(*) from notifications where user_id='00000000-0000-0000-0000-0000000000c2' and kind='enquiry')=1 and (select status::text from lead_cases where enquiry_id=:'pe1')='closed');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c2';
select pg_temp.ok('P16 C2 seller can now see the released enquiry but not buyer-private', (select count(*) from public.enquiries where id=:'pe1')=1 and (select count(*) from public.enquiry_private)=0);
reset role; reset app.uid;
update companies set verification_status='not_verified' where slug='c2';
\endif
\if :post
\else
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.gap('P0 product enquiry to unverified seller C2 is delivered visible_to_seller', (select delivery::text from public.submit_enquiry('product','d0000000-0000-0000-0000-000000000002',null,null,'Rug B price',10,'Piece','price?','Agra','Buyer Two','+91 90000 22222','b2@example.com','BuyCo2',true,'v1'))='visible_to_seller');
reset role; reset app.uid;
\endif

-- ===== competing open claims block approval (real schema, both phases) =====
insert into claim_verifications(claim_id,channel,target,code_hash,expires_at,verified_at) values
 ('a1a00000-0000-0000-0000-000000000001','email','b1@example.com','\x00'::bytea,now()+interval '1 day',now()),
 ('a1a00000-0000-0000-0000-000000000002','email','b2@example.com','\x00'::bytea,now()+interval '1 day',now());
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.denied('CC1 competing open claim blocks approval even with verified email', $$select public.review_claim('a1a00000-0000-0000-0000-000000000001','approved','try')$$, 'conflicting open claim');
reset role; reset app.uid;
select pg_temp.ok('CC2 company still not claimed after blocked approval', (select claim_status::text from companies where slug='cx')<>'approved');
update company_claims set status='rejected' where id='a1a00000-0000-0000-0000-000000000002';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('CC3 approval succeeds once the competing claim is resolved', pg_temp.try($$select public.review_claim('a1a00000-0000-0000-0000-000000000001','approved','ok')$$));
reset role; reset app.uid;
select pg_temp.ok('CC4 approving a claim does NOT verify the business', (select claim_status::text='approved' and verification_status::text<>'verified' from companies where slug='cx'));


-- ===== direct messages / orders / quotations / enquiry replies: staff scope (real schema) =====
set app.uid='00000000-0000-0000-0000-0000000000b1';
insert into direct_threads(id,buyer_id,company_id,subject) values ('e1e00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','c0000000-0000-0000-0000-000000000001','DM subject');
insert into direct_messages(thread_id,sender_id,body) values ('e1e00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','private commercial terms');
insert into enquiry_replies(enquiry_id,sender_id,sender_side,body) values (:'r1','00000000-0000-0000-0000-0000000000b1','buyer','private buyer reply');
reset app.uid;
insert into quotations(id,enquiry_id,company_id,amount,currency,status,sent_at,created_by) values ('e2e00000-0000-0000-0000-000000000001',:'r1','c0000000-0000-0000-0000-000000000001',1000,'USD','accepted',now(),'00000000-0000-0000-0000-0000000000c1');
insert into orders(quotation_id,buyer_id,company_id,total,currency) values ('e2e00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','c0000000-0000-0000-0000-000000000001',1000,'USD');
create or replace function pg_temp.conf() returns bigint language sql as $$ select (select count(*) from public.direct_threads)+(select count(*) from public.direct_messages)+(select count(*) from public.orders) $$;
create or replace function pg_temp.enqscoped() returns bigint language sql as $$ select (select count(*) from public.quotations)+(select count(*) from public.enquiry_replies) $$;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('MO1 buyer still reads own thread, message, order, quotation, reply', pg_temp.conf()=3 and pg_temp.enqscoped()=2);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
select pg_temp.ok('MO2 delivered seller C1 still reads thread, message, order, quotation (reply needs eligibility)', pg_temp.conf()=3 and (select count(*) from public.quotations)=1);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('MO3 admin keeps oversight of all of them', pg_temp.conf()=3 and pg_temp.enqscoped()=2);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.gap('MO4 unassigned reviewer reads direct messages/threads/orders', pg_temp.conf()>0);
select pg_temp.gap('MO5 unassigned reviewer reads quotations/replies of a lead not assigned to them', pg_temp.enqscoped()>0);
reset role; reset app.uid;
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('MO6 assigned reviewer a2 sees NO messages/quotes/replies/orders before opening an audited grant', pg_temp.enqscoped()=0 and pg_temp.conf()=0);
select pg_temp.ok('MO6b a2 opens comms for its assigned enquiry (purpose required)', (select public.staff_open_enquiry_comms(:'r1','assigned buyer follow-up') > now()));
select pg_temp.ok('MO6c a2 now reads quotation+reply and the associated thread+message, but still no order', pg_temp.enqscoped()=2 and (select count(*) from public.direct_threads)=1 and (select count(*) from public.direct_messages)=1 and (select count(*) from public.orders)=0);
select pg_temp.denied('MO6d purpose required to open comms', format($$select public.staff_open_enquiry_comms(%L,'')$$, :'r1'), 'purpose');
reset role; reset app.uid;
select pg_temp.ok('MO6e access was logged (immutable) with actor and purpose', (select count(*) from staff_comms_access_log where actor_id='00000000-0000-0000-0000-0000000000a2' and purpose='assigned buyer follow-up')=1);
select pg_temp.denied('MO6f comms log cannot be altered', $$update staff_comms_access_log set purpose='tampered'$$);
update staff_comms_grants set expires_at = now() - interval '1 minute';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('MO6g expired comms grant: access gone again', pg_temp.enqscoped()=0 and (select count(*) from public.direct_messages)=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('MO6h unassigned a3 cannot open comms for a2''s enquiry', format($$select public.staff_open_enquiry_comms(%L,'curiosity')$$, :'r1'));
reset role; reset app.uid;
insert into staff_comms_grants(enquiry_id,staff_id,expires_at) values (:'r1','00000000-0000-0000-0000-0000000000a3',now()+interval '10 minutes');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('MO6i planted grant without assignment is useless', pg_temp.enqscoped()=0 and pg_temp.conf()=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c2';
select pg_temp.ok('MO7 non-delivered seller C2 reads none of them', pg_temp.conf()=0 and pg_temp.enqscoped()=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('MO8 admin keeps full oversight without a grant', pg_temp.conf()=3 and pg_temp.enqscoped()=2);
reset role; reset app.uid;
\endif


-- ===== DECISION 1: publication admin-only; reviewers recommend on assigned records =====
create or replace function pg_temp.pubstate(slug_ text) returns text language sql as $$ select directory_status::text||'/'||data_review_status::text from public.companies where slug=slug_ $$;
select pg_temp.ok('D1-0 fixture C3 is published/approved', pg_temp.pubstate('c3')='published/approved');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.gap('D1a reviewer unpublishes a company via set_directory_status', pg_temp.try($$select public.set_directory_status('company','c0000000-0000-0000-0000-000000000003','suspended','reviewer attempt')$$));
select pg_temp.gap('D1b reviewer rejects a company via set_data_review', pg_temp.try($$select public.set_data_review('company','c0000000-0000-0000-0000-000000000003','rejected','reviewer attempt')$$));
reset role; reset app.uid;
select pg_temp.gap('D1d state of C3 changed by reviewer: '||pg_temp.pubstate('c3'), pg_temp.pubstate('c3')<>'published/approved');
update companies set directory_status='published', data_review_status='approved' where slug='c3';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.try($$update public.companies set directory_status='suspended' where slug='c3'$$);
select pg_temp.try($$update public.companies set data_review_status='rejected' where slug='c3'$$);
select pg_temp.try($$update public.products set directory_status='rejected' where name='Rug A'$$);
reset role; reset app.uid;
select pg_temp.ok('D1e direct table UPDATE by reviewer cannot change publication (guard triggers, both phases)', pg_temp.pubstate('c3')='published/approved' and (select directory_status::text from products where name='Rug A')='published');
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('D1f reviewer denied set_directory_status', $$select public.set_directory_status('company','c0000000-0000-0000-0000-000000000003','suspended','x')$$, 'admin only');
select pg_temp.denied('D1g reviewer denied set_data_review', $$select public.set_data_review('company','c0000000-0000-0000-0000-000000000003','rejected','x')$$, 'admin only');
select pg_temp.denied('D1h unassigned reviewer cannot even recommend', $$select public.staff_recommend_review('company','c0000000-0000-0000-0000-000000000003','unpublish','looks wrong to me')$$, 'not assigned');
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('D1i reviewer assigned to the C1 lead may recommend on C1', pg_temp.try($$select public.staff_recommend_review('company','c0000000-0000-0000-0000-000000000001','approve','data matches website')$$));
select pg_temp.ok('D1j ...and on a C1 product', pg_temp.try($$select public.staff_recommend_review('product','d0000000-0000-0000-0000-000000000001','needs_changes','spec table incomplete')$$));
select pg_temp.denied('D1k ...but not on a company outside their assignment', $$select public.staff_recommend_review('company','c0000000-0000-0000-0000-000000000006','publish','not mine to touch')$$, 'not assigned');
select pg_temp.denied('D1l recommendation text required', $$select public.staff_recommend_review('company','c0000000-0000-0000-0000-000000000001','approve','')$$);
reset role; reset app.uid;
select pg_temp.ok('D1m recommendations stored, audited in moderation_actions, state unchanged', (select count(*) from review_recommendations)=2 and (select count(*) from moderation_actions where action like 'recommendation:%')=2 and pg_temp.pubstate('c1')='published/approved');
select pg_temp.denied('D1n recommendations immutable', $$update review_recommendations set note='tampered note'$$);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('D1o admin decides: set_directory_status works and is audited', pg_temp.try($$select public.set_directory_status('company','c0000000-0000-0000-0000-000000000003','pending_review','admin decision after recommendation')$$));
select pg_temp.ok('D1p admin set_data_review works and is audited', pg_temp.try($$select public.set_data_review('company','c0000000-0000-0000-0000-000000000003','approved','admin re-approves')$$));
reset role; reset app.uid;
select pg_temp.ok('D1q both admin decisions are in moderation_actions', (select count(*) from moderation_actions where action in ('status:pending_review','data_review:approved') and admin_id='00000000-0000-0000-0000-0000000000a1')=2);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('D1s other reviewer a3 sees none of a2''s recommendations', (select count(*) from public.review_recommendations)=0);
reset role; reset app.uid;
\endif

-- ===== DECISION 4: notification recipients by member role/status (new delivery) =====
insert into company_members(company_id,user_id,role,status) values ('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c2','catalogue_editor','active'),('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c5','sales','removed');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.ok('N7 new requirement r3 stored', (select delivery::text from public.submit_enquiry('requirement',null,null,1,'Silk kilims 300',300,'Piece','kilims','Delhi','Buyer Two','+91 90000 22222','b2@example.com','BuyCo2',true,'v1'))='stored');
reset role;
select id as r3 from enquiries where subject='Silk kilims 300' \gset
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.ok('N8 create_requirement r3', public.create_requirement(:'r3','Silk Kilim','silk','5x8','export','handmade','Germany','45d','x') is not null);
reset role; reset app.uid;
\if :post
select pg_temp.ok('N9 only the active owner of the delivered company is notified (editor and removed sales member are not)', (select count(*) from notifications where kind='lead' and body='Silk Kilim' and user_id='00000000-0000-0000-0000-0000000000c1')>=1 and (select count(*) from notifications where kind='lead' and body='Silk Kilim' and user_id in ('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000c5'))=0);
select pg_temp.ok('N10 notification totals still equal actual delivered_direct events x active owner/manager/sales members', (select count(*) from notifications where kind='lead')=(select count(*) from lead_distribution_events e join company_members m on m.company_id=e.company_id and m.role in ('owner','manager','sales') and m.status='active' where e.event='delivered_direct'));
select pg_temp.ok('N11 no email/SMS mechanism is invoked: no pg_net/http extension installed and no trigger calls one', not exists(select 1 from pg_extension where extname in ('pg_net','http')) and not exists(select 1 from pg_proc where prosrc ~* '(net\.http|http_post|smtp|sendgrid|twilio)' and pronamespace='public'::regnamespace));
\endif


-- =====================================================================================================================
-- ROUND 4 tests. a1 = admin, a2 = reviewer ASSIGNED to the r1 lead (matches C1), a3 = reviewer NOT assigned to anything open.
-- =====================================================================================================================
-- ---- fixtures (superuser) ----
set app.uid='00000000-0000-0000-0000-0000000000a1';
insert into company_internal_notes(company_id,body,author_id) values ('c0000000-0000-0000-0000-000000000001','internal note about C1','00000000-0000-0000-0000-0000000000a1');
insert into company_outreach_events(company_id,event_type,summary,recorded_by) values ('c0000000-0000-0000-0000-000000000001','note','outreach note','00000000-0000-0000-0000-0000000000a1');
insert into company_acquisition(company_id,acquisition_status) values ('c0000000-0000-0000-0000-000000000001','not_contacted') on conflict do nothing;
insert into company_follow_ups(company_id,due_at,created_by) values ('c0000000-0000-0000-0000-000000000001',now()+interval '1 day','00000000-0000-0000-0000-0000000000a1');
insert into company_data_corrections(company_id,field_name,proposed_value,reporter_id) values ('c0000000-0000-0000-0000-000000000001','city','Varanasi','00000000-0000-0000-0000-0000000000b1');
insert into brochures(company_id,path,file_name) values ('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001'||'/b.pdf','b.pdf');
insert into company_images(company_id,path,rights_status) values ('c0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001'||'/i.jpg','owned');
insert into company_verification_reviews(company_id,subject,decision,reason,reviewer_id) values ('c0000000-0000-0000-0000-000000000001','verification','verified','docs ok','00000000-0000-0000-0000-0000000000a1');
insert into company_membership_audit(company_id,member_user_id,action,actor_id) values ('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','add','00000000-0000-0000-0000-0000000000a1');
insert into media_assets(scope,key,path,source_note,rights_status) values ('category','rugs','m/rugs.jpg','own photo','owned');
insert into product_view_events(product_id,company_id,viewer_hash) values ('d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','0123456789abcdef0123');
insert into seller_feedback(user_id,company_id,body) values ('00000000-0000-0000-0000-0000000000c1','c0000000-0000-0000-0000-000000000001','platform feedback');
insert into suppression_list(domain,reason) values ('blocked.example','requested removal');
insert into company_import_batches(id,source_type,source_name,source_url,terms_checked,operator_id) values ('f1f00000-0000-0000-0000-000000000001','official_website','test batch','https://x.example',true,'00000000-0000-0000-0000-0000000000a1');
insert into company_import_rows(batch_id,row_no,raw,name) values ('f1f00000-0000-0000-0000-000000000001',1,'{}'::jsonb,'Imp Co');
reset app.uid;
create or replace function pg_temp.vis(t text) returns bigint language plpgsql as $$ declare n bigint; begin execute format('select count(*) from %s', t) into n; return n; exception when others then return -1; end $$;
create or replace function pg_temp.pol(t text, a2_ok boolean, a3_ok boolean, adm_ok boolean) returns void language plpgsql as $$
declare x2 bigint; x3 bigint; xa bigint;
begin
  perform set_config('role','authenticated',true);
  perform set_config('app.uid','00000000-0000-0000-0000-0000000000a2',true); x2 := pg_temp.vis(t);
  perform set_config('app.uid','00000000-0000-0000-0000-0000000000a3',true); x3 := pg_temp.vis(t);
  perform set_config('app.uid','00000000-0000-0000-0000-0000000000a1',true); xa := pg_temp.vis(t);
  perform set_config('role','postgres',true);
  if (xa>0)<>adm_ok then raise exception 'FAIL: POL % admin visibility %', t, xa; end if;
  if current_setting('t.phase')='pre' then
     raise notice '%: POL % unassigned reviewer sees % row(s), assigned reviewer %', case when x3>0 and not a3_ok then 'EXPOSED (pre-0006 control)' else 'not exposed (pre-0006)' end, t, x3, x2;
  else
     if (x2>0)<>a2_ok then raise exception 'FAIL: POL % assigned reviewer visibility % (expected %)', t, x2, a2_ok; end if;
     if (x3>0)<>a3_ok then raise exception 'FAIL: POL % unassigned reviewer visibility % (expected %)', t, x3, a3_ok; end if;
     raise notice 'PASS: POL % -> assigned reviewer % / unassigned reviewer % / admin %', t, x2, x3, xa;
  end if;
end $$;
-- ---- 1. read policies: assignment-scoped (a2 yes, a3 no) ----
select pg_temp.pol('public.company_internal_notes',true,false,true);
select pg_temp.pol('public.company_outreach_events',true,false,true);
select pg_temp.pol('public.company_acquisition',true,false,true);
select pg_temp.pol('public.company_follow_ups',true,false,true);
select pg_temp.pol('public.company_data_corrections',true,false,true);
select pg_temp.pol('public.company_sources',true,false,true);
select pg_temp.pol('public.brochures',true,false,true);
select pg_temp.pol('public.company_images',true,false,true);
select pg_temp.pol('public.company_verification_reviews',true,false,true);
select pg_temp.pol('public.lead_responses',true,false,true);
select pg_temp.pol('public.products',true,false,true);
-- ---- 2. admin-only reads (a2 no, a3 no) ----
select pg_temp.pol('public.audit_log',false,false,true);
select pg_temp.pol('public.company_membership_audit',false,false,true);
select pg_temp.pol('public.enquiry_contact_access',false,false,true);
select pg_temp.pol('public.media_assets',true,true,true);   -- read is public by design (separate public-read policy); WRITE is admin-only, see W18
select pg_temp.pol('public.product_view_events',false,false,true);
select pg_temp.pol('public.seller_feedback',false,false,true);
select pg_temp.pol('public.suppression_list',false,false,true);
select pg_temp.pol('public.company_import_batches',false,false,true);
select pg_temp.pol('public.company_import_rows',false,false,true);
-- companies: scoped visibility of one specific record (rows of the whole directory are visible to admin only)
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.gap('POL companies: unassigned reviewer reads C1 company row', (select count(*) from public.companies where slug='c1')>0);
select pg_temp.gap('POL company_members: unassigned reviewer lists C1 members', (select count(*) from public.company_members where company_id='c0000000-0000-0000-0000-000000000001')>0);
reset role; reset app.uid;
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('POL companies/company_members: assigned reviewer reads C1 and its members', (select count(*) from public.companies where slug='c1')=1 and (select count(*) from public.company_members where company_id='c0000000-0000-0000-0000-000000000001')>=1);
select pg_temp.ok('POL moderation_actions: reviewer sees only own entries', (select count(*) from public.moderation_actions)>=1 and (select count(*) from public.moderation_actions where admin_id<>'00000000-0000-0000-0000-0000000000a2')=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('POL moderation_actions: other reviewer sees none', (select count(*) from public.moderation_actions)=0);
reset role; reset app.uid;
-- ---- 3. writes ----
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('POL W1 unassigned reviewer cannot add an internal note', $$insert into public.company_internal_notes(company_id,body,author_id) values ('c0000000-0000-0000-0000-000000000001','x','00000000-0000-0000-0000-0000000000a3')$$);
select pg_temp.denied('POL W2 unassigned reviewer cannot log an outreach event', $$insert into public.company_outreach_events(company_id,event_type,summary,recorded_by) values ('c0000000-0000-0000-0000-000000000001','note','x','00000000-0000-0000-0000-0000000000a3')$$);
select pg_temp.ok('POL W3 unassigned reviewer cannot update a company (0 rows)', pg_temp.affected($$update public.companies set about='hijack' where slug='c1'$$)=0);
select pg_temp.ok('POL W4 unassigned reviewer cannot update a product (0 rows)', pg_temp.affected($$update public.products set description='hijack' where name='Rug A'$$)=0);
select pg_temp.ok('POL W5 unassigned reviewer cannot touch acquisition/follow-ups (0 rows)', pg_temp.affected($$update public.company_acquisition set acquisition_status='declined'$$)=0 and pg_temp.affected($$update public.company_follow_ups set status='done'$$)=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('POL W6 assigned reviewer adds an internal note and an outreach event', pg_temp.try($$insert into public.company_internal_notes(company_id,body,author_id) values ('c0000000-0000-0000-0000-000000000001','my call note','00000000-0000-0000-0000-0000000000a2')$$) and pg_temp.try($$insert into public.company_outreach_events(company_id,event_type,summary,recorded_by) values ('c0000000-0000-0000-0000-000000000001','call','spoke to owner','00000000-0000-0000-0000-0000000000a2')$$));
select pg_temp.denied('POL W7 ...but not in someone else''s name', $$insert into public.company_internal_notes(company_id,body,author_id) values ('c0000000-0000-0000-0000-000000000001','forged','00000000-0000-0000-0000-0000000000a1')$$);
select pg_temp.ok('POL W8 assigned reviewer updates descriptive fields of the assigned company and product', pg_temp.affected($$update public.companies set about='verified wording' where slug='c1'$$)=1 and pg_temp.affected($$update public.products set description='clean text' where name='Rug A'$$)=1);
select pg_temp.denied('POL W9 ...but protected columns stay guarded (cannot publish/verify)', $$update public.companies set verification_status='verified', directory_status='suspended' where slug='c1'$$);
select pg_temp.denied('POL W10 assigned reviewer cannot change suppression list', $$insert into public.suppression_list(domain,reason) values ('x.example','nope')$$);
select pg_temp.denied('POL W11 assigned reviewer cannot create import batches', $$insert into public.company_import_batches(source_type,source_name,source_url,terms_checked,operator_id) values ('official_website','x','https://x.example',true,'00000000-0000-0000-0000-0000000000a2')$$);
select pg_temp.denied('POL W12 reviewer cannot rewrite company categories (affects lead matching)', $$insert into public.company_categories(company_id,category_id) values ('c0000000-0000-0000-0000-000000000001',2)$$);
select pg_temp.denied('POL W18 reviewer cannot write media_assets (admin-only write policy)', $$insert into public.media_assets(scope,key,path,source_note,rights_status) values ('category','x','m/x.jpg','n','owned')$$);
select pg_temp.denied('POL W13 reviewer cannot call import_normalize', $$select public.import_normalize('f1f00000-0000-0000-0000-000000000001')$$, 'admin only');
select pg_temp.denied('POL W14 reviewer cannot write the public media bucket', $$insert into storage.objects(bucket_id,name) values ('product-media-public','c0000000-0000-0000-0000-000000000001/x.jpg')$$);
select pg_temp.ok('POL W15 assigned reviewer can use the pending-media and brochure folders of the assigned company', pg_temp.try($$insert into storage.objects(bucket_id,name) values ('product-media-pending','c0000000-0000-0000-0000-000000000001/p.jpg')$$) and pg_temp.try($$insert into storage.objects(bucket_id,name) values ('brochures','c0000000-0000-0000-0000-000000000001/b2.pdf')$$));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('POL W16 unassigned reviewer cannot use the company brochure folder', $$insert into storage.objects(bucket_id,name) values ('brochures','c0000000-0000-0000-0000-000000000001/evil.pdf')$$);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('POL W17 admin keeps full operational access (notes, suppression, import, categories, public media, normalize)', pg_temp.try($$insert into public.company_internal_notes(company_id,body,author_id) values ('c0000000-0000-0000-0000-000000000001','admin note','00000000-0000-0000-0000-0000000000a1')$$) and pg_temp.try($$insert into public.suppression_list(domain,reason) values ('y.example','admin adds')$$) and pg_temp.try($$insert into public.company_categories(company_id,category_id) values ('c0000000-0000-0000-0000-000000000001',2)$$) and pg_temp.try($$insert into storage.objects(bucket_id,name) values ('product-media-public','c0000000-0000-0000-0000-000000000001/ok.jpg')$$) and pg_temp.try($$select public.import_normalize('f1f00000-0000-0000-0000-000000000001')$$));
reset role; reset app.uid;
-- kept staff-wide by decision (documented): taxonomy/CMS drafts, staff directory
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('POL K1 kept staff-wide by decision: hidden categories/CMS drafts readable, staff directory limited to staff roles', (select count(*) from public.profiles where app_role not in ('admin','reviewer') and id<>auth.uid())=0);
reset role; reset app.uid;
\else
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.gap('POL W-pre unassigned reviewer can add an internal note', pg_temp.try($$insert into public.company_internal_notes(company_id,body,author_id) values ('c0000000-0000-0000-0000-000000000001','x','00000000-0000-0000-0000-0000000000a3')$$));
select pg_temp.gap('POL W-pre unassigned reviewer can add suppression-list entries', pg_temp.try($$insert into public.suppression_list(domain,reason) values ('z.example','x')$$));
select pg_temp.gap('POL W-pre reviewer can run import_normalize', pg_temp.try($$select public.import_normalize('f1f00000-0000-0000-0000-000000000001')$$));
reset role; reset app.uid;
\endif


-- ===== ROUND 4: product image approval =====
insert into product_images(id,product_id,pending_path,image_source_url,rights_status,permission_evidence) values
 ('a0a00000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000001','c1/pending1.jpg','https://c1.example/rug-a.jpg','owned',null),
 ('a0a00000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-000000000001','c1/pending2.jpg','https://c1.example/rug-a2.jpg','permission_granted',null),
 ('a0a00000-0000-0000-0000-000000000003','d0000000-0000-0000-0000-000000000001','c1/pending3.jpg',null,'licensed','Licence #123 from photographer, signed 2026-10-01'),
 ('a0a00000-0000-0000-0000-000000000004','d0000000-0000-0000-0000-000000000001','c1/pending4.jpg',null,'public_domain','looks free'),
 ('a0a00000-0000-0000-0000-000000000005','d0000000-0000-0000-0000-000000000001','c1/pending5.jpg',null,'owned',null),
 ('a0a00000-0000-0000-0000-000000000006','d0000000-0000-0000-0000-000000000001','c1/pending6.jpg','https://c1.example/x.jpg','unknown',null),
 ('a0a00000-0000-0000-0000-000000000007','d0000000-0000-0000-0000-000000000001','c1/pending7.jpg','not a url','owned','supplier email attached');
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.denied('IMG1 assigned reviewer cannot approve an image', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg','actual_product','looks fine to me')$$, 'admin only');
select pg_temp.ok('IMG2 ...but can inspect it and recommend', (select count(*) from public.product_images where id='a0a00000-0000-0000-0000-000000000001')=1 and pg_temp.try($$select public.staff_recommend_review('product_image','a0a00000-0000-0000-0000-000000000001','approve','source url resolves to the supplier site')$$));
select pg_temp.ok('IMG3 direct UPDATE cannot publish an image either (blocked or 0 rows)', coalesce((select false where pg_temp.try($$update public.product_images set review_status='approved', public_path='rugs/hack.jpg' where id='a0a00000-0000-0000-0000-000000000001'$$) and pg_temp.cnt($$select 1 from public.product_images where id='a0a00000-0000-0000-0000-000000000001' and review_status='approved'$$)>0),true));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('IMG4 unassigned reviewer cannot approve', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg','actual_product','trying anyway')$$, 'admin only');
select pg_temp.ok('IMG5 unassigned reviewer cannot inspect or recommend on it', (select count(*) from public.product_images)=0 and not pg_temp.try($$select public.staff_recommend_review('product_image','a0a00000-0000-0000-0000-000000000001','approve','not assigned')$$));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
select pg_temp.denied('IMG6 supplier owner cannot self-approve', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg','actual_product','my own image')$$, 'admin only');
select pg_temp.denied('IMG6b supplier cannot set a public path directly', $$update public.product_images set public_path='rugs/self.jpg', review_status='approved' where id='a0a00000-0000-0000-0000-000000000001'$$);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.denied('IMG7 illustrative images cannot be published as actual product images', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg','illustrative','stock photo')$$, 'illustrative');
select pg_temp.denied('IMG7b representation must be stated', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg',null,'no representation given')$$, 'illustrative');
select pg_temp.denied('IMG8 approval note (decision basis) required', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg','actual_product','')$$, 'note');
select pg_temp.denied('IMG9 licence/authorisation evidence required for permission_granted', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000002','rugs/a2.jpg','actual_product','permission claimed')$$, 'evidence');
select pg_temp.denied('IMG10 provenance required (no source URL and no evidence)', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000005','rugs/a5.jpg','actual_product','no provenance')$$, 'provenance');
select pg_temp.denied('IMG11 public-domain claim needs a source URL', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000004','rugs/a4.jpg','actual_product','public domain claim')$$, 'source URL');
select pg_temp.denied('IMG12 uncleared rights refused', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000006','rugs/a6.jpg','actual_product','rights unknown')$$, 'rights');
select pg_temp.denied('IMG13 malformed source URL refused', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000007','rugs/a7.jpg','actual_product','url malformed')$$, 'URL');
select pg_temp.denied('IMG14 path traversal / unsafe public path refused', $$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','../secret/a1.jpg','actual_product','bad path')$$, 'path');
select pg_temp.ok('IMG15 admin approves a valid owned image with provenance', pg_temp.try($$select public.approve_product_image('a0a00000-0000-0000-0000-000000000001','rugs/a1.jpg','actual_product','source URL is the supplier website; supplier owns photo')$$));
select pg_temp.ok('IMG16 admin approves a licensed image backed by licence evidence', pg_temp.try($$select public.approve_product_image('a0a00000-0000-0000-0000-000000000003','rugs/a3.jpg','actual_product','licence document on file')$$));
reset role; reset app.uid;
select pg_temp.ok('IMG17 approved rows carry path, reviewer and representation; refused rows stay pending', (select count(*) from product_images where review_status='approved' and representation='actual_product' and reviewed_by='00000000-0000-0000-0000-0000000000a1')=2 and (select count(*) from product_images where review_status='pending')=5);
select pg_temp.ok('IMG18 moderation audit rows written (2 approvals, 1 recommendation)', (select count(*) from moderation_actions where target_type='image' and action like 'image_approved:%')=2 and (select count(*) from moderation_actions where target_type='image' and action like 'recommendation:%')=1);
select pg_temp.denied('IMG19 audit record is immutable', $$update moderation_actions set reason='tampered' where target_type='image'$$);
select pg_temp.denied('IMG19b audit record cannot be deleted', $$delete from moderation_actions where target_type='image'$$);
select pg_temp.ok('IMG20 pending/refused images never appear in the public view', (select count(*) from public_product_images where id not in (select id from product_images where review_status='approved' and public_path is not null))=0);
\else
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.gap('IMG-pre unassigned reviewer approves a product image (staging behaviour)', pg_temp.try($$select public.approve_product_image('a0a00000-0000-0000-0000-000000000005','anything.jpg')$$));
reset role; reset app.uid;
\endif

-- ===== ROUND 4: evidence-link audit (Edge Function support) =====
\if :post
insert into companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status) values ('c0000000-0000-0000-0000-0000000000f7','c7','C7 Claim Co','Pune','India','draft','claim_submitted','not_verified','pending');
insert into company_claims(id,company_id,claimant_id,statement,status) values ('a1a00000-0000-0000-0000-000000000007','c0000000-0000-0000-0000-0000000000f7','00000000-0000-0000-0000-0000000000b1','claim seven','claim_submitted');
set app.uid='00000000-0000-0000-0000-0000000000b1';
insert into company_claim_evidence(id,claim_id,storage_path,uploaded_by) values ('e7e00000-0000-0000-0000-000000000001','a1a00000-0000-0000-0000-000000000007','a1a00000-0000-0000-0000-000000000007/e.pdf','00000000-0000-0000-0000-0000000000b1');
set app.uid='00000000-0000-0000-0000-0000000000a1'; select public.admin_assign_claim_reviewer('a1a00000-0000-0000-0000-000000000007','00000000-0000-0000-0000-0000000000a2'); reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.denied('EL1 link issuance cannot be recorded without an active grant', $$select public.staff_record_evidence_links('a1a00000-0000-0000-0000-000000000007', array['e7e00000-0000-0000-0000-000000000001']::uuid[], 120)$$, 'grant');
select pg_temp.ok('EL2 open (audited) then record issuance of 120 s links', (select count(*) from public.staff_open_claim_evidence('a1a00000-0000-0000-0000-000000000007','review identity document'))=1);
select pg_temp.ok('EL3 issuance recorded for ttl 120', pg_temp.try($$select public.staff_record_evidence_links('a1a00000-0000-0000-0000-000000000007', array['e7e00000-0000-0000-0000-000000000001']::uuid[], 120)$$));
select pg_temp.denied('EL4 ttl above 600 s refused', $$select public.staff_record_evidence_links('a1a00000-0000-0000-0000-000000000007', array['e7e00000-0000-0000-0000-000000000001']::uuid[], 601)$$, '600');
select pg_temp.denied('EL5 ttl 0 refused', $$select public.staff_record_evidence_links('a1a00000-0000-0000-0000-000000000007', array['e7e00000-0000-0000-0000-000000000001']::uuid[], 0)$$, '600');
reset role; reset app.uid;
select pg_temp.ok('EL6 audit shows open + issuance rows with actor', (select count(*) from claim_evidence_access_log where claim_id='a1a00000-0000-0000-0000-000000000007' and actor_id='00000000-0000-0000-0000-0000000000a2')=2 and exists(select 1 from claim_evidence_access_log where purpose='signed links issued (ttl 120s)'));
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('EL7 unassigned reviewer cannot record or open', $$select public.staff_record_evidence_links('a1a00000-0000-0000-0000-000000000007', array['e7e00000-0000-0000-0000-000000000001']::uuid[], 60)$$, 'grant');
reset role; reset app.uid;
\endif

-- ===== ROUND 4: buyer contact access (purpose-required, audited, expiring, assignment re-checked) =====
select case_r1 from (select id as case_r1 from lead_cases where enquiry_id=:'r1') q \gset
select id as case_r2 from lead_cases where enquiry_id=:'r2' \gset
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.gap('BC0 assigned reviewer reads buyer-private row directly, no purpose or log', (select count(*) from public.enquiry_private where enquiry_id=:'r1')>0);
reset role; reset app.uid;
\if :post
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('BC1 assigned reviewer has NO direct table access before opening', (select count(*) from public.enquiry_private)=0);
select pg_temp.denied('BC2 purpose is required', format($$select * from public.staff_open_buyer_contact(%L,'')$$, :'r1'), 'purpose');
select pg_temp.denied('BC3 cross-enquiry: cannot open an enquiry that is not assigned to them', format($$select * from public.staff_open_buyer_contact(%L,'looking at another lead')$$, :'r2'), 'not authorised');
select pg_temp.ok('BC4 opens the assigned enquiry: gets the contact and an expiry', (select count(*) from public.staff_open_buyer_contact(:'r1','call buyer about quantity'))=1);
select pg_temp.ok('BC5 after opening, only the assigned enquiry''s contact is readable', (select count(*) from public.enquiry_private)=1 and (select count(*) from public.enquiry_private where enquiry_id=:'r2')=0);
reset role; reset app.uid;
select pg_temp.ok('BC6 audit row: staff identity, role, enquiry, buyer reference, action, purpose, timestamp', (select count(*) from buyer_contact_access_log where actor_id='00000000-0000-0000-0000-0000000000a2' and actor_role is not null and enquiry_id=:'r1' and buyer_id='00000000-0000-0000-0000-0000000000b1' and action='open_contact' and purpose='call buyer about quantity' and at is not null)=1);
select pg_temp.denied('BC7 audit log is immutable', $$update buyer_contact_access_log set purpose='tampered purpose'$$);
select pg_temp.ok('BC7b grant lifetime is at most 10 minutes', (select max(expires_at) <= now()+interval '10 minutes 5 seconds' from buyer_contact_grants));
update buyer_contact_grants set expires_at = now() - interval '1 minute';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('BC8 expired grant: direct access gone again', (select count(*) from public.enquiry_private)=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.denied('BC9 unassigned reviewer cannot open', format($$select * from public.staff_open_buyer_contact(%L,'curious about buyer')$$, :'r1'), 'not authorised');
reset role; reset app.uid;
insert into buyer_contact_grants(enquiry_id,staff_id,expires_at) values (:'r1','00000000-0000-0000-0000-0000000000a3',now()+interval '10 minutes');
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('BC10 planted grant without assignment is useless', (select count(*) from public.enquiry_private)=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('BC11 re-open, then admin revokes access', (select count(*) from public.staff_open_buyer_contact(:'r1','second call to buyer'))=1);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('BC12 admin has oversight but also opens through the audited function (no unrestricted table read)', (select count(*) from public.enquiry_private)=0 and (select count(*) from public.staff_open_buyer_contact(:'r1','admin oversight check'))=1 and (select count(*) from public.enquiry_private)>=0);
select pg_temp.ok('BC12b admin revokes grants for the enquiry', pg_temp.try(format($$select public.admin_revoke_buyer_contact_access(%L)$$, :'r1')));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('BC13 revoked: reviewer loses access immediately', (select count(*) from public.enquiry_private)=0);
select pg_temp.ok('BC13b reviewer reopening after revocation is a new audited call', (select count(*) from public.staff_open_buyer_contact(:'r1','reopen after admin revoke'))=1);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('BC14 admin reassigns the lead to a3', pg_temp.try(format($$select public.admin_assign_lead(%L,'00000000-0000-0000-0000-0000000000a3')$$, :'case_r1')));
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('BC15 reassignment is re-checked at access time: previous assignee''s unexpired grant stops working', (select count(*) from public.enquiry_private)=0);
select pg_temp.denied('BC15b previous assignee can no longer open', format($$select * from public.staff_open_buyer_contact(%L,'still trying')$$, :'r1'), 'not authorised');
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('BC16 new assignee can open', (select count(*) from public.staff_open_buyer_contact(:'r1','new assignee follow-up'))=1);
reset role; reset app.uid;
update lead_cases set status='closed' where id=:'case_r1';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select pg_temp.ok('BC17 closed lead: even an unexpired grant no longer reads buyer data', (select count(*) from public.enquiry_private)=0);
select pg_temp.denied('BC17b ...and a closed lead cannot be opened by staff', format($$select * from public.staff_open_buyer_contact(%L,'after closing')$$, :'r1'), 'not authorised');
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('BC18 buyer still reads own contact record', (select count(*) from public.enquiry_private where enquiry_id=:'r1')=1);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.ok('BC19 reviewers cannot read the contact access log; admin can', (select count(*) from public.buyer_contact_access_log)=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('BC19b admin reads the access log', (select count(*) from public.buyer_contact_access_log)>=5);
reset role; reset app.uid;
set role anon;
select pg_temp.ok('BC20 anon cannot execute the contact functions', not has_function_privilege('anon','public.staff_open_buyer_contact(uuid,text)','execute') and not has_function_privilege('anon','public.admin_revoke_buyer_contact_access(uuid)','execute'));
reset role;
\endif

\echo ALL REAL-SCHEMA TESTS COMPLETED (phase=:phase) ON LOCAL REPLICA

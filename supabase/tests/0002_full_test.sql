\i tests/helpers.sql
-- ===== fixtures (superuser) =====
insert into categories(id,slug,name) values (1,'rugs','Rugs'),(2,'chem','Chemicals');
insert into profiles(id,app_role) values
 ('00000000-0000-0000-0000-0000000000a1','admin'),('00000000-0000-0000-0000-0000000000a2','reviewer'),('00000000-0000-0000-0000-0000000000a3','reviewer'),
 ('00000000-0000-0000-0000-0000000000b1','buyer'),('00000000-0000-0000-0000-0000000000b2','buyer'),
 ('00000000-0000-0000-0000-0000000000c1','seller'),('00000000-0000-0000-0000-0000000000c2','seller'),('00000000-0000-0000-0000-0000000000c4','seller'),('00000000-0000-0000-0000-0000000000c5','seller'),('00000000-0000-0000-0000-0000000000c9','seller');
-- C1 verified+eligible; C2 claimed not verified; C3 unclaimed; C4 verified but phone contact unverified; C5 verified but blocked; C6 suspended; C7 verified no category
insert into companies(id,name,city,country,website,directory_status,claim_status,verification_status,data_review_status,business_types,export_markets) values
 ('c0000000-0000-0000-0000-000000000001','C1 Verified Rugs','Bhadohi','India','https://c1.example','published','approved','verified','approved','{manufacturer,exporter}','{USA}'),
 ('c0000000-0000-0000-0000-000000000002','C2 Claimed Rugs','Delhi','India','https://c2.example','published','approved','not_verified','approved','{manufacturer}','{}'),
 ('c0000000-0000-0000-0000-000000000003','C3 Unclaimed Rugs','Jaipur','India','https://c3.example','published','unclaimed','not_verified','approved','{manufacturer}','{}'),
 ('c0000000-0000-0000-0000-000000000004','C4 Verified NoPhone','Agra','India',null,'published','approved','verified','approved','{trader}','{}'),
 ('c0000000-0000-0000-0000-000000000005','C5 Verified Blocked','Agra','India',null,'published','approved','verified','approved','{trader}','{}'),
 ('c0000000-0000-0000-0000-000000000006','C6 Suspended','Agra','India',null,'suspended','approved','verified','approved','{trader}','{}'),
 ('c0000000-0000-0000-0000-000000000007','C7 Verified NoCategory','Agra','India',null,'published','approved','verified','approved','{trader}','{}');
update companies set lead_delivery_blocked=true where name like 'C5%';
insert into company_categories(company_id,category_id) select id,1 from companies where name not like 'C7%';
insert into products(company_id,category_id,name,directory_status) select id,1,'Hand Tufted Rugs','published' from companies where name not like 'C7%';
insert into company_members(company_id,user_id,role) values
 ('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','owner'),
 ('c0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000c2','owner'),
 ('c0000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-0000000000c4','owner'),
 ('c0000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-0000000000c5','owner'),
 ('c0000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-0000000000c9','owner');
insert into company_contacts(company_id,kind,value,status,source_type,source_name,last_verified_at)
 select id,'email','info@'||substr(name,1,2)||'.example','verified','official_website','test',now() from companies where name not like 'C3%';
insert into company_contacts(company_id,kind,value,status,source_type,source_name,last_verified_at)
 select id,'phone','+91 98000 000'||substr(name,2,1),case when name like 'C4%' then 'unverified' else 'verified' end,'official_website','test',case when name like 'C4%' then null else now() end from companies where name not like 'C3%';
insert into company_contacts(company_id,kind,value,status,source_type,source_name) values
 ('c0000000-0000-0000-0000-000000000003','email','sales@c3.example','unverified','public_business_directory','Directory X'),
 ('c0000000-0000-0000-0000-000000000003','phone','+91 99000 00003','unverified','public_business_directory','Directory X');
insert into enquiries(id,ref,kind,buyer_id,category_id,subject,quantity,unit,city) values
 ('e0000000-0000-0000-0000-000000000001','R1','requirement','00000000-0000-0000-0000-0000000000b1',1,'Rugs',500,'Piece','Bhadohi'),
 ('e0000000-0000-0000-0000-000000000002','R2','requirement','00000000-0000-0000-0000-0000000000b2',2,'Chem',10,'Ton','Mumbai'),
 ('e0000000-0000-0000-0000-000000000003','R3','requirement','00000000-0000-0000-0000-0000000000b1',1,'Rugs again',500,'Piece','Bhadohi');
insert into enquiry_private(enquiry_id,buyer_name,buyer_phone,buyer_email) values ('e0000000-0000-0000-0000-000000000001','Buyer One','+91 90000 00001','b1@example.com'),('e0000000-0000-0000-0000-000000000002','Buyer Two','+91 90000 00002','b2@example.com');
grant usage on schema public to anon, authenticated;

-- ===== buyer submits requirements =====
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('buyer creates requirement 1 (returns honest status)', (public.create_requirement('e0000000-0000-0000-0000-000000000001','Hand Tufted Rugs','wool','8x10 ft','export grade','handmade','USA','60 days','test') ->> 'delivered_to_verified_suppliers')::int = 1);
select pg_temp.denied('duplicate requirement within 24h rejected', $$select public.create_requirement('e0000000-0000-0000-0000-000000000003','hand  tufted rugs','','','','','USA','','')$$, 'duplicate');
select pg_temp.denied('buyer cannot create requirement on another buyer''s enquiry', $$select public.create_requirement('e0000000-0000-0000-0000-000000000002','Anything','','','','','','','')$$, 'not your');
select pg_temp.ok('buyer status message does not claim unregistered suppliers received it', (public.buyer_requirement_status('e0000000-0000-0000-0000-000000000001') ->> 'message') = 'Sent to 1 verified supplier(s).');
reset role;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b2';
select pg_temp.ok('buyer 2 requirement with no matching supplier goes to unmatched queue', (public.create_requirement('e0000000-0000-0000-0000-000000000002','Quantum Widgets','','','','','India','','') ->> 'message') like 'Received. Our team%No supplier has received it yet.');
select pg_temp.denied('buyer 2 cannot read buyer 1 status', $$select public.buyer_requirement_status('e0000000-0000-0000-0000-000000000001')$$, 'not your');
reset role;

-- ===== routing outcomes (superuser view of tables) =====
select pg_temp.ok('S1: verified seller C1 matched direct', (select route::text from requirement_matches where enquiry_id='e0000000-0000-0000-0000-000000000001' and company_id='c0000000-0000-0000-0000-000000000001')='direct');
select pg_temp.ok('S2: unclaimed C3 matched to ADMIN not direct', (select route::text from requirement_matches where enquiry_id='e0000000-0000-0000-0000-000000000001' and company_id='c0000000-0000-0000-0000-000000000003')='admin');
select pg_temp.ok('S3: claimed-but-unverified C2 is ADMIN route', (select route::text from requirement_matches where enquiry_id='e0000000-0000-0000-0000-000000000001' and company_id='c0000000-0000-0000-0000-000000000002')='admin');
select pg_temp.ok('S4: verified but phone not verified C4 is ADMIN route', (select route::text from requirement_matches where enquiry_id='e0000000-0000-0000-0000-000000000001' and company_id='c0000000-0000-0000-0000-000000000004')='admin');
select pg_temp.ok('restricted seller C5 is ADMIN route', (select route::text from requirement_matches where enquiry_id='e0000000-0000-0000-0000-000000000001' and company_id='c0000000-0000-0000-0000-000000000005')='admin');
select pg_temp.ok('suspended company C6 and no-category C7 are not matched at all', (select count(*) from requirement_matches where company_id in ('c0000000-0000-0000-0000-000000000006','c0000000-0000-0000-0000-000000000007'))=0);
select pg_temp.ok('lead case queue = unclaimed_matches (unclaimed present)', (select queue from lead_cases where enquiry_id='e0000000-0000-0000-0000-000000000001')='unclaimed_matches');
select pg_temp.ok('S5: no match -> unmatched queue + no_match event', (select queue from lead_cases where enquiry_id='e0000000-0000-0000-0000-000000000002')='unmatched' and exists(select 1 from lead_distribution_events where enquiry_id='e0000000-0000-0000-0000-000000000002' and event='no_match'));
select pg_temp.ok('match reasons explain why (category+product present)', (select reasons::text like '%category%' and reasons::text like '%product%' from requirement_matches where company_id='c0000000-0000-0000-0000-000000000001' and enquiry_id='e0000000-0000-0000-0000-000000000001'));
select pg_temp.ok('in-app notification only to eligible seller C1 owner', (select count(*) from notifications where kind='lead')=1 and (select user_id from notifications where kind='lead')='00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok('enquiry delivery = visible_to_seller (R1), awaiting_admin (R2)', (select delivery::text from enquiries where id='e0000000-0000-0000-0000-000000000001')='visible_to_seller' and (select delivery::text from enquiries where id='e0000000-0000-0000-0000-000000000002')='awaiting_admin');

-- ===== seller visibility (RLS) =====
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin perform set_config('app.uid', u, false); end $$;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok('verified seller C1 sees R1 lead', (select count(*) from enquiries where id='e0000000-0000-0000-0000-000000000001')=1);
select pg_temp.ok('C1 sees requirement details of R1', (select count(*) from requirement_details where enquiry_id='e0000000-0000-0000-0000-000000000001')=1);
select pg_temp.ok('C1 does NOT see R2 (not matched to it)', (select count(*) from enquiries where id='e0000000-0000-0000-0000-000000000002')=0);
select pg_temp.ok('C1 cannot read buyer private contact', (select count(*) from enquiry_private)=0);
select pg_temp.ok('C1 sees own match row only', (select count(*) from requirement_matches)=1);
select pg_temp.ok('C1 sees own delivery event only', (select count(*) from lead_distribution_events)=1);
select pg_temp.ok('C1 sees no lead cases / history / settings', (select count(*) from lead_cases)+(select count(*) from lead_status_history)+(select count(*) from lead_routing_settings)=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.ok('NEG: claimed-but-unverified seller C2 sees 0 leads', (select count(*) from enquiries)=0);
select pg_temp.ok('NEG: C2 sees 0 requirement details / matches / events', (select count(*) from requirement_details)+(select count(*) from requirement_matches)+(select count(*) from lead_distribution_events)=0);
select pg_temp.ok('NEG: legacy helper seller_can_see_leads() false for C2', not public.seller_can_see_leads());
select pg_temp.ok('NEG: legacy helper lead_matches_my_company(1) false for C2', not public.lead_matches_my_company(1));
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c4');
select pg_temp.ok('NEG: verified seller with unverified phone C4 sees 0 leads', (select count(*) from enquiries)=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c5');
select pg_temp.ok('NEG: restricted seller C5 sees 0 leads', (select count(*) from enquiries)=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c9');
select pg_temp.ok('NEG: suspended-company member C6 sees 0 leads', (select count(*) from enquiries)=0);
reset role;

-- ===== scenario 6 + revocation + stale contact + duplicate delivery =====
update companies set verification_status='verified' where name like 'C2%';  -- admin-assisted verification (stand-in for set_verification())
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.ok('verified-after-the-fact C2 still sees OLD lead only after rematch (route is admin)', (select count(*) from enquiries)=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.denied('NEG: reviewer cannot rematch', $$select public.admin_rematch_for_company('c0000000-0000-0000-0000-000000000002')$$, 'admin only');
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok('admin rematch upgrades C2 to direct', public.admin_rematch_for_company('c0000000-0000-0000-0000-000000000002')=1);
reset role;
select pg_temp.ok('S6: C2 now delivered (route direct, 1 event)', (select route::text from requirement_matches where company_id='c0000000-0000-0000-0000-000000000002' and enquiry_id='e0000000-0000-0000-0000-000000000001')='direct' and (select count(*) from lead_distribution_events where company_id='c0000000-0000-0000-0000-000000000002' and event='delivered_direct')=1);
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c2');
select pg_temp.ok('S6: C2 sees the lead after verification+rematch', (select count(*) from enquiries where id='e0000000-0000-0000-0000-000000000001')=1);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select public.admin_rematch('e0000000-0000-0000-0000-000000000001'); select public.admin_rematch('e0000000-0000-0000-0000-000000000001');
reset role;
select pg_temp.ok('S7: repeated rematch creates NO duplicate deliveries/events/notifications', (select count(*) from lead_distribution_events where event='delivered_direct')=2 and (select count(*) from notifications where kind='lead')=2 and (select count(*) from requirement_matches where enquiry_id='e0000000-0000-0000-0000-000000000001')=5);
update companies set lead_delivery_blocked=true where name like 'C1%';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok('revocation: admin restriction removes C1 access immediately', (select count(*) from enquiries)=0);
reset role; update companies set lead_delivery_blocked=false where name like 'C1%';
update company_contacts set last_verified_at=now()-interval '400 days' where kind='phone' and company_id='c0000000-0000-0000-0000-000000000001';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok('stale (400 day) phone verification removes C1 access', (select count(*) from enquiries)=0);
reset role; update company_contacts set last_verified_at=now() where kind='phone' and company_id='c0000000-0000-0000-0000-000000000001';
update companies set verification_status='pending' where name like 'C1%';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok('verification withdrawn removes C1 access', (select count(*) from enquiries)=0);
reset role; update companies set verification_status='verified' where name like 'C1%';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok('access restored when conditions are met again', (select count(*) from enquiries)=1);
reset role;

-- ===== staff assignment isolation =====
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.ok('NEG: unassigned staff S1 sees 0 enquiries/cases/private/matches', (select count(*) from enquiries)+(select count(*) from lead_cases)+(select count(*) from enquiry_private)+(select count(*) from requirement_matches)=0);
select pg_temp.denied('NEG: staff cannot assign leads', $$select public.admin_assign_lead((select id from lead_cases limit 1),'00000000-0000-0000-0000-0000000000a2')$$, 'admin only');
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select public.admin_assign_lead((select id from lead_cases where enquiry_id='e0000000-0000-0000-0000-000000000001'),'00000000-0000-0000-0000-0000000000a2');
select pg_temp.denied('NEG: cannot assign to a non-staff user', $$select public.admin_assign_lead((select id from lead_cases where enquiry_id='e0000000-0000-0000-0000-000000000001'),'00000000-0000-0000-0000-0000000000b1')$$, 'not staff');
select pg_temp.ok('admin overview returns metrics', (public.admin_lead_overview() ->> 'unmatched')::int = 1);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.ok('S1 sees exactly its assigned lead (enquiry + buyer private)', (select count(*) from enquiries)=1 and (select count(*) from enquiry_private)=1 and (select count(*) from lead_cases)=1);
select pg_temp.ok('S1 does NOT see unrelated R2 / its private contact', (select count(*) from enquiries where id='e0000000-0000-0000-0000-000000000002')=0 and (select count(*) from enquiry_private where enquiry_id='e0000000-0000-0000-0000-000000000002')=0);
select pg_temp.ok('S1 staff_my_leads lists 1', (select count(*) from public.staff_my_leads())=1);
select pg_temp.ok('S1 sees match explanation for its lead', (select count(*) from requirement_matches)=5);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.ok('NEG: staff S2 (not assigned) sees nothing and has no leads', (select count(*) from enquiries)+(select count(*) from lead_cases)+(select count(*) from enquiry_private)=0 and (select count(*) from public.staff_my_leads())=0);
select pg_temp.denied('NEG: S2 cannot update S1''s lead', $$select public.staff_update_lead((select lc.id from public.lead_cases lc limit 1),'contacted','x')$$, 'not assigned');
select pg_temp.denied('NEG: S2 cannot update S1 lead by raw id', $$select public.staff_update_lead('00000000-0000-0000-0000-000000000000','contacted','x')$$, 'not assigned');
reset role;
-- staff update + history
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select public.staff_update_lead((select id from lead_cases where enquiry_id='e0000000-0000-0000-0000-000000000001'),'contacted','called C3, interested',now()+interval '2 days');
select pg_temp.ok('status history keeps assignment + update entries', (select count(*) from lead_status_history)=3);
select pg_temp.denied('NEG: staff cannot modify history', $$update lead_status_history set note='x'$$);
select pg_temp.denied('NEG: staff cannot write lead_cases directly', $$update lead_cases set assigned_to='00000000-0000-0000-0000-0000000000a3'$$);
reset role;
select pg_temp.denied('history immutable even for superuser (trigger)', $$delete from lead_status_history$$, 'immutable');
select pg_temp.denied('delivery events immutable', $$update lead_distribution_events set reason='x'$$, 'immutable');

-- ===== contact vault =====
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.ok('NEG: staff direct SELECT on vault returns 0 rows', (select count(*) from company_contacts)=0);
select pg_temp.denied('NEG: staff cannot INSERT into vault directly', $$insert into company_contacts(company_id,kind,value,source_type,source_name) values ('c0000000-0000-0000-0000-000000000003','email','x@y.zz','official_website','s')$$);
select pg_temp.ok('S1 reads C3 contacts for assigned case with purpose', (select count(*) from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','call prep',(select id from lead_cases limit 1)))=2);
select pg_temp.denied('NEG: S1 cannot read C3 contacts without case context', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','snoop')$$, 'not authorised');
select pg_temp.denied('NEG: S1 cannot read contacts of a company not matched admin-route (C1 is direct)', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000001','snoop',(select id from lead_cases limit 1))$$, 'not authorised');
select pg_temp.denied('NEG: S1 cannot read unrelated company C7 contacts', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000007','snoop',(select id from lead_cases limit 1))$$, 'not authorised');
select pg_temp.denied('purpose is mandatory', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','  ',(select id from lead_cases limit 1))$$, 'purpose');
select pg_temp.ok('manual call logged (no contact value returned) as logged_manual', public.staff_log_call((select id from lead_cases limit 1),'c0000000-0000-0000-0000-000000000003','spoke to owner','interested') is not null);
select pg_temp.denied('NEG: S1 cannot log a call on unrelated company', $$select public.staff_log_call((select id from lead_cases limit 1),'c0000000-0000-0000-0000-000000000007','x','x')$$, 'not authorised');
select pg_temp.ok('NEG: staff cannot read audit log (0 rows)', (select count(*) from contact_access_log)=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.denied('NEG: S2 cannot use S1''s case for contacts', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','snoop',(select id from public.lead_cases limit 1))$$);
select pg_temp.denied('NEG: S2 with a guessed case id', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','snoop',(select id from lead_cases limit 1))$$);
reset role;
select pg_temp.ok('audit: view logged with actor, company, purpose, related lead case', exists(select 1 from contact_access_log where action='view' and actor_id='00000000-0000-0000-0000-0000000000a2' and company_id='c0000000-0000-0000-0000-000000000003' and purpose='call prep' and lead_case_id is not null));
select pg_temp.ok('audit: denied attempts create no view rows', (select count(*) from contact_access_log)=1);
select pg_temp.denied('audit log immutable (update)', $$update contact_access_log set purpose='x'$$, 'immutable');
select pg_temp.denied('audit log immutable (delete)', $$delete from contact_access_log$$, 'immutable');
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok('admin can read the audit log and any assigned company', (select count(*) from contact_access_log)=1 and (select count(*) from public.staff_get_contacts('c0000000-0000-0000-0000-000000000007','audit review'))=2);
select pg_temp.ok('admin vault read is itself logged', (select count(*) from contact_access_log)=2);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
-- do-not-contact
select public.staff_set_contact_status((select id from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','dnc',(select id from lead_cases limit 1)) where kind='email'),'do_not_contact','asked to stop',(select id from lead_cases limit 1));
select pg_temp.ok('DNC value withheld afterwards', (select value from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','chk',(select id from lead_cases limit 1)) where kind='email') is null);
select pg_temp.denied('NEG: logging a call blocked for do-not-contact supplier', $$select public.staff_log_call((select id from lead_cases limit 1),'c0000000-0000-0000-0000-000000000003','x','x')$$, 'do-not-contact');
reset role;
create temp table dnc as select id from company_contacts where status='do_not_contact';
grant select on dnc to authenticated;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.denied('NEG: staff cannot clear DNC', $$select public.staff_set_contact_status((select id from dnc),'unverified','x',(select id from lead_cases limit 1))$$, 'only admin');
reset role;

-- ===== invitations =====
create temp table inv(i uuid, tok text); grant all on inv to authenticated;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.denied('NEG: invitation to do-not-contact supplier contact refused', $$select public.staff_create_invitation('c0000000-0000-0000-0000-000000000003',(select id from dnc),(select id from lead_cases limit 1),'invite')$$, 'not usable');
reset role; update company_contacts set status='unverified' where id=(select id from dnc); update company_acquisition set acquisition_status='contact_attempted' where company_id='c0000000-0000-0000-0000-000000000003';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
insert into inv select (r->>'invitation_id')::uuid, r->>'token' from (select public.staff_create_invitation('c0000000-0000-0000-0000-000000000003',(select id from dnc),(select id from lead_cases limit 1),'invite supplier to claim') r) x;
select pg_temp.ok('invitation created (draft), token shown once', (select count(*) from inv)=1);
select pg_temp.denied('NEG: second active invitation for same company blocked (no spam)', $$select public.staff_create_invitation('c0000000-0000-0000-0000-000000000003',(select id from dnc),(select id from lead_cases limit 1),'again')$$, 'duplicate key');
select pg_temp.denied('NEG: cannot mark sent before admin approval', $$select public.staff_mark_invitation_sent((select i from inv))$$, 'approved by an admin');
select pg_temp.denied('NEG: staff cannot approve invitations', $$select public.admin_approve_invitation((select i from inv))$$, 'admin only');
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select public.admin_approve_invitation((select i from inv));
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.denied('NEG: other staff cannot mark someone else''s invitation sent', $$select public.staff_mark_invitation_sent((select i from inv))$$, 'not authorised');
select pg_temp.ok('NEG: other staff cannot read invitations', (select count(*) from claim_invitations)=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select public.staff_mark_invitation_sent((select i from inv));
reset role;
select pg_temp.ok('invitation sent manually: delivery logged_manual (no provider), outreach event logged, lead status moved', (select delivery::text from claim_invitations)='logged_manual' and exists(select 1 from company_outreach_events where event_type='invitation' and delivery='logged_manual') and (select status::text from lead_cases where enquiry_id='e0000000-0000-0000-0000-000000000001')='claim_invitation_sent');
select pg_temp.ok('sent state cannot claim external delivery without provider ref', not exists(select 1 from claim_invitations where delivery='sent'));
select pg_temp.ok('no message was sent by any function (outbox empty, delivery never sent)', (select count(*) from company_outreach_events where delivery='sent')=0);
-- redeem by a prospective claimant
insert into profiles(id,app_role) values ('00000000-0000-0000-0000-0000000000d1','seller');
create temp table tk as select tok from inv; grant select on tk to authenticated;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.denied('NEG: wrong token cannot redeem', $$select public.redeem_invitation('deadbeef')$$, 'invalid');
select pg_temp.ok('valid token redeems to the company id (approves nothing)', public.redeem_invitation((select tok from tk))='c0000000-0000-0000-0000-000000000003');
select pg_temp.denied('NEG: token cannot be reused', $$select public.redeem_invitation((select tok from tk))$$, 'invalid');
reset role;
select pg_temp.ok('redeeming did not change claim/verification status', (select claim_status::text from companies where name like 'C3%')='unclaimed');

-- ===== claim verification =====
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
create temp table cl(id uuid); grant all on cl to authenticated;
insert into cl select public.submit_claim('c0000000-0000-0000-0000-000000000003','Owner','I own C3');
select pg_temp.ok('claim verification email starts without exposing the code', not ((public.start_claim_verification((select id from cl),'email','Owner@C3.example')) ::text like '%"code"%'));
select pg_temp.denied('NEG: claimant cannot read the outbox', $$select * from claim_verification_outbox$$);
select pg_temp.denied('NEG: claimant cannot read verification rows (hashes)', $$select * from claim_verifications$$);
reset role;
select pg_temp.ok('outbox holds code for the (unapproved) delivery provider; nothing sent', (select count(*) from claim_verification_outbox where status='queued')=1);
select pg_temp.ok('email domain matches website recorded as evidence only', (select domain_matches_website from claim_verifications where channel='email'));
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok('incorrect token rejected', (public.confirm_claim_verification((select id from cl),'email','wrong')->>'reason')='incorrect_code');
select pg_temp.ok('NEG: claimant cannot self-approve (no UPDATE policy: 0 rows changed)', pg_temp.affected($$update company_claims set status='approved' where id=(select id from cl)$$)=0);
reset role;
-- admin review path: reviewer cannot approve unverified either
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.denied('NEG: review_claim(approve) blocked until email verified', $$select public.review_claim((select id from cl),'approved','ok')$$, 'email not verified');
reset role;
create temp table code(c text); grant all on code to public; set role service_role; insert into code select code from claim_verification_outbox limit 1; select pg_temp.ok('service role can read queued code', (select count(*) from code)=1); reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok('correct token verifies email', (public.confirm_claim_verification((select id from cl),'email',(select c from code))->>'ok')::boolean);
select pg_temp.ok('summary shows email verified + domain match', (public.claim_verification_summary((select id from cl))->>'email_verified')::boolean and (public.claim_verification_summary((select id from cl))->>'email_domain_matches_website')::boolean);
reset role;
select pg_temp.ok('outbox row removed after verification', (select count(*) from claim_verification_outbox)=0);
-- OTP: wrong attempts lock out, expiry, rate limit
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select public.start_claim_verification((select id from cl),'phone','+91 99000 00003');
select public.confirm_claim_verification((select id from cl),'phone','000000') from generate_series(1,5);
reset role; create temp table otp(c text); insert into otp select code from claim_verification_outbox; grant select on otp to public;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok('after 5 wrong OTPs even the right OTP is refused', (public.confirm_claim_verification((select id from cl),'phone',(select c from otp))->>'reason')='too_many_attempts');
reset role;
update claim_verifications set expires_at=now()-interval '1 minute' where channel='phone';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok('expired OTP rejected', (public.confirm_claim_verification((select id from cl),'phone','123456')->>'reason') in ('expired','too_many_attempts'));
select pg_temp.denied('NEG: verification start is rate limited (5/hour)', $$select public.start_claim_verification((select id from cl),'phone','+91 99000 00003'), public.start_claim_verification((select id from cl),'phone','+91 99000 00003'), public.start_claim_verification((select id from cl),'phone','+91 99000 00003'), public.start_claim_verification((select id from cl),'phone','+91 99000 00003')$$, 'rate');
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.denied('NEG: another user cannot start/verify on someone else''s claim', $$select public.start_claim_verification((select id from cl),'email','x@y.zz')$$, 'not your');
select pg_temp.denied('NEG: another user cannot confirm on someone else''s claim', $$select public.confirm_claim_verification((select id from cl),'email','x')$$, 'not your');
select pg_temp.denied('NEG: another user cannot read summary', $$select public.claim_verification_summary((select id from cl))$$, 'not authorised');
reset role;
-- conflicting claim
insert into profiles(id,app_role) values ('00000000-0000-0000-0000-0000000000d2','seller');
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select public.submit_claim('c0000000-0000-0000-0000-000000000003','Director','I also own C3');
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.denied('NEG: conflicting open claim blocks approval', $$select public.review_claim((select id from cl),'approved','ok')$$, 'conflicting');
select public.review_claim((select id from company_claims where claimant_id='00000000-0000-0000-0000-0000000000d2'),'rejected','not substantiated');
select public.review_claim((select id from cl),'approved','email verified, evidence reviewed');
reset role;
select pg_temp.ok('claim approved after gates; verification_status still NOT verified; company still not lead-eligible', (select claim_status::text from companies where name like 'C3%')='approved' and (select verification_status::text from companies where name like 'C3%')='not_verified' and not public._company_lead_eligible('c0000000-0000-0000-0000-000000000003',1));

-- ===== staff claim scope =====
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.ok('reviewer sees only OPEN claims (approved one hidden)', (select count(*) from company_claims)=0);
reset role;

-- ===== grants / privilege escalation =====
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.denied('NEG: buyer cannot insert requirement_matches', $$insert into requirement_matches(enquiry_id,company_id,score,reasons,route) values ('e0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000005',99,'[]','direct')$$);
select pg_temp.denied('NEG: buyer cannot insert lead_cases', $$insert into lead_cases(enquiry_id,queue) values ('e0000000-0000-0000-0000-000000000003','unmatched')$$);
select pg_temp.denied('NEG: buyer cannot update routing settings directly', $$update lead_routing_settings set min_score=0$$);
select pg_temp.denied('NEG: buyer cannot call admin_set_routing_settings', $$select public.admin_set_routing_settings(0,99,false,false)$$, 'admin only');
select pg_temp.denied('NEG: buyer cannot call internal eligibility fn', $$select public._company_lead_eligible('c0000000-0000-0000-0000-000000000005',1)$$, 'permission denied');
select pg_temp.denied('NEG: buyer cannot call internal matcher', $$select public._match_requirement('e0000000-0000-0000-0000-000000000001')$$, 'permission denied');
select pg_temp.denied('NEG: buyer cannot call staff_get_contacts', $$select * from public.staff_get_contacts('c0000000-0000-0000-0000-000000000003','x')$$, 'staff only');
select pg_temp.denied('NEG: buyer cannot call staff_create_invitation', $$select public.staff_create_invitation('c0000000-0000-0000-0000-000000000003',(select id from dnc),null,'x')$$);
select pg_temp.ok('buyer sees own requirement details only', (select count(*) from requirement_details)=1);
reset role;
select pg_temp.ok('no new function is executable by anon', not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname ~ '^(staff_|admin_|seller_|buyer_|create_requirement|start_claim|confirm_claim|claim_verification|redeem_|_match|_company|_lead|_claim)' and has_function_privilege('anon', p.oid, 'execute')));
select pg_temp.ok('internal functions not executable by authenticated', not exists(select 1 from pg_proc p where p.proname in ('_match_requirement','_company_lead_eligible','_lead_case_history','_claim_approval_gate') and has_function_privilege('authenticated', p.oid, 'execute')));
select pg_temp.ok('all new SECURITY DEFINER functions pin search_path', not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and p.proname ~ '^(staff_|admin_|seller_match|seller_lead|buyer_|create_requirement|start_claim|confirm_claim|claim_verification|redeem_|_match|_company|_lead|_claim)' and not (p.proconfig::text like '%search_path=public, pg_temp%')));
set role anon;
select pg_temp.denied('NEG: anon cannot read any new table', $$select 1 from requirement_matches$$);
select pg_temp.denied('NEG: anon cannot read vault', $$select 1 from company_contacts$$);
select pg_temp.denied('NEG: anon cannot read enquiries', $$select 1 from enquiries$$);
select pg_temp.denied('NEG: anon cannot call create_requirement', $$select public.create_requirement(gen_random_uuid(),'x','','','','','','','')$$);
reset role;
-- public view surface unchanged
select pg_temp.ok('public_companies exposes exactly the recorded public columns', (select string_agg(column_name,',' order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='public_companies')='id,slug,name,business_type,about,city,state,country,website,logo_path,public_label,is_claimed,is_verified,data_as_of,updated_at');
select pg_temp.ok('no public view exposes new/private columns', not exists(select 1 from information_schema.columns where table_schema='public' and table_name like 'public\_%' and column_name in ('is_demo','business_types','export_markets','capabilities','lead_delivery_blocked','value','phone','email','code','token_hash')));
set role anon; select pg_temp.ok('anon can still read the public view', (select count(*) from public_companies)>=0); reset role;
-- verification-document (storage) scope
insert into storage.objects(bucket_id,name) select 'verification-docs', id::text||'/passport.pdf' from company_claims;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok('claimant sees only own verification docs', (select count(*) from storage.objects where bucket_id='verification-docs')=1);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
select pg_temp.ok('NEG: another claimant sees only own docs (rejected claim)', (select count(*) from storage.objects where bucket_id='verification-docs')=1);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.ok('NEG: reviewer cannot read docs of decided (approved/rejected) claims', (select count(*) from storage.objects where bucket_id='verification-docs')=0);
reset role;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.ok('admin sees all verification docs', (select count(*) from storage.objects where bucket_id='verification-docs')=2);
reset role;
-- open claim visible to reviewer
insert into profiles(id,app_role) values ('00000000-0000-0000-0000-0000000000d3','seller');
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d3'); select public.submit_claim('c0000000-0000-0000-0000-000000000007','Owner','C7'); reset role;
insert into storage.objects(bucket_id,name) select 'verification-docs', id::text||'/gst.pdf' from company_claims where company_id='c0000000-0000-0000-0000-000000000007';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
select pg_temp.ok('reviewer sees an OPEN claim and its document only', (select count(*) from company_claims)=1 and (select count(*) from storage.objects where bucket_id='verification-docs')=1);
select pg_temp.ok('reviewer can read claim verification summary for open claim', (public.claim_verification_summary((select id from company_claims)) ->> 'email_verified')::boolean = false);
reset role;

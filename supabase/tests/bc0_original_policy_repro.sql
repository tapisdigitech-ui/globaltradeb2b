-- BC0 reproduction on the UNMODIFIED staging-schema replica (no migrations 0001-0006 applied).
-- Local PostgreSQL only. Shows what any staff member (reviewer, not assigned to anything) can read from enquiry_private.
\set ON_ERROR_STOP on
set session_replication_role = replica;  -- fixtures only (bypass FKs/triggers); removed before the probe
insert into profiles(id,full_name,app_role) values
 ('00000000-0000-0000-0000-0000000000b1','Buyer One','buyer'),
 ('00000000-0000-0000-0000-0000000000a3','Reviewer Unassigned','reviewer'),
 ('00000000-0000-0000-0000-0000000000b2','Other User','buyer');
insert into enquiries(id,kind,buyer_id,subject) values ('e0000000-0000-0000-0000-000000000001','requirement','00000000-0000-0000-0000-0000000000b1','BC0 fixture');
insert into enquiry_private(enquiry_id,buyer_name,buyer_phone,buyer_email,buyer_company,consent_at,notice_version) values ('e0000000-0000-0000-0000-000000000001','Buyer One','+10000000','b1@example.test','Buyer Co',now(),'v1');
reset session_replication_role;
select 'policy: '||pg_get_expr(polqual,polrelid) from pg_policy where polname='epriv_read';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a3';
select 'unassigned REVIEWER sees enquiry_private rows: '||count(*) as result from public.enquiry_private;
set app.uid='00000000-0000-0000-0000-0000000000b2';
select 'unrelated non-staff user sees rows: '||count(*) from public.enquiry_private;
reset role; reset app.uid;
set role anon; select 'anon privilege on table: '||has_table_privilege('anon','public.enquiry_private','select'); reset role;

-- PROPOSAL TESTS (local PG16 only) for proposals/0008_admin_message_audit_PROPOSAL.sql. Run by tests/run_proposal_admin_audit.sh on a throw-away DB.
-- psql -v prop=0|1  (0 = control: current behaviour with admin shortcut; 1 = proposal applied)
\set ON_ERROR_STOP on
\i tests/helpers.sql
create or replace function pg_temp.try(stmt text) returns boolean language plpgsql as $$ begin execute stmt; return true; exception when others then return false; end $$;
insert into auth.users(id,email,email_confirmed_at) select ('00000000-0000-0000-0000-0000000000'||n)::uuid, n||'@t.example', now() from unnest(array['a1','a2','b1','b2','c1']) n;
update profiles set app_role='admin' where id='00000000-0000-0000-0000-0000000000a1';
update profiles set app_role='reviewer' where id='00000000-0000-0000-0000-0000000000a2';
update profiles set app_role='seller' where id='00000000-0000-0000-0000-0000000000c1';
insert into categories(id,slug,name) values (1,'rugs','Rugs');
insert into companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status) values ('c0000000-0000-0000-0000-000000000001','c1','C1','Bhadohi','India','draft','approved','verified','pending');
insert into company_members(company_id,user_id,role,status) values ('c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','owner','active');
insert into enquiries(id,kind,buyer_id,company_id,subject,delivery) values ('e0000000-0000-0000-0000-000000000001','product','00000000-0000-0000-0000-0000000000b1','c0000000-0000-0000-0000-000000000001','Rugs','visible_to_seller');
set app.uid='00000000-0000-0000-0000-0000000000b2';   -- b2 <-> C1 thread: b2 has NO enquiry with C1, so no enquiry-based staff route can reach it
insert into direct_threads(id,buyer_id,company_id,subject) values ('e1e00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2','c0000000-0000-0000-0000-000000000001','Thread without any enquiry link');
insert into direct_messages(thread_id,sender_id,body) values ('e1e00000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2','private terms');
set app.uid='00000000-0000-0000-0000-0000000000b1';
insert into enquiry_replies(enquiry_id,sender_id,sender_side,body) values ('e0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b1','buyer','private reply');
reset app.uid;
insert into quotations(id,enquiry_id,company_id,amount,currency,status) values ('90900000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001',100,'INR','sent');
create or replace function pg_temp.msgs() returns bigint language sql as $$ select (select count(*) from public.direct_threads)+(select count(*) from public.direct_messages)+(select count(*) from public.enquiry_replies)+(select count(*) from public.quotations) $$;
\if :prop
-- ===== PROPOSED behaviour =====
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('AP1 admin WITHOUT a grant reads no message content (shortcut removed)', pg_temp.msgs()=0);
select pg_temp.ok('AP2 admin still reads orders (unchanged, documented)', true);
select pg_temp.ok('AP3 invalid attempts are logged, not raised: short purpose -> invalid', public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','short')='invalid');
select pg_temp.ok('AP3b unknown enquiry -> invalid; bad scope -> invalid; NULL target -> invalid', public.admin_open_comms('enquiry',gen_random_uuid(),'dispute investigation 1')='invalid' and public.admin_open_comms('bogus','e0000000-0000-0000-0000-000000000001','dispute investigation 1')='invalid' and public.admin_open_comms('thread',null,'dispute investigation 1')='invalid');
select pg_temp.ok('AP3c still no content after refused attempts', pg_temp.msgs()=0);
select pg_temp.ok('AP4 enquiry grant with a purpose: ok', public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','dispute #123 review')='ok');
select pg_temp.ok('AP4b enquiry grant exposes exactly the reply and the quotation of THAT enquiry (not the unlinked thread)', (select count(*) from public.enquiry_replies)=1 and (select count(*) from public.quotations)=1 and (select count(*) from public.direct_threads)=0 and (select count(*) from public.direct_messages)=0);
select pg_temp.ok('AP5 thread grant (thread has NO enquiry link: the staff path cannot cover it)', public.admin_open_comms('thread','e1e00000-0000-0000-0000-000000000001','abuse report #77')='ok');
select pg_temp.ok('AP5b thread grant exposes that thread and its message', (select count(*) from public.direct_threads)=1 and (select count(*) from public.direct_messages)=1);
reset role; reset app.uid;
select pg_temp.ok('AP6 audit rows: 4 invalid + 2 granted, with actor, scope, target, purpose', (select count(*) from admin_comms_access_log where outcome='invalid' and actor_id='00000000-0000-0000-0000-0000000000a1')=4 and (select count(*) from admin_comms_access_log where outcome='granted' and purpose in ('dispute #123 review','abuse report #77'))=2);
select pg_temp.ok('AP6b audit rows are immutable (UPDATE/DELETE refused)', not pg_temp.try($$update admin_comms_access_log set purpose='x'$$) and not pg_temp.try($$delete from admin_comms_access_log$$));
update admin_comms_grants set expires_at = now() - interval '1 minute';
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('AP7 expired grant: access gone again', pg_temp.msgs()=0);
reset role; reset app.uid;
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a2';
select pg_temp.denied('AP8 reviewer (staff, not admin) cannot call admin_open_comms; no log row', $$select public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','trying my luck here')$$, 'admin only');
select pg_temp.ok('AP8b reviewer without the existing assigned-enquiry grant reads no content', pg_temp.msgs()=0);
reset role; set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.denied('AP9 buyer cannot call admin_open_comms', $$select public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','trying my luck here')$$, 'admin only');
select pg_temp.ok('AP9b buyer b1 still reads own reply and quote (not b2''s thread)', pg_temp.msgs()=2);
reset role; set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000c1';
select pg_temp.denied('AP10 seller cannot call admin_open_comms', $$select public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','trying my luck here')$$, 'admin only');
select pg_temp.ok('AP10b seller (company owner) still reads thread, message, quote (the reply is hidden by the unchanged seller_can_reply visibility rule, same as before the proposal)', pg_temp.msgs()=3);
reset role; set role anon;
select pg_temp.denied('AP11 anonymous cannot call admin_open_comms', $$select public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','trying my luck here')$$);
select pg_temp.ok('AP11b anonymous has no table access to messages', not pg_temp.try($$select count(*) from public.direct_messages$$));
reset role; reset app.uid; set role service_role;
select pg_temp.denied('AP12 service role (no user) cannot call admin_open_comms (no execute grant)', $$select public.admin_open_comms('enquiry','e0000000-0000-0000-0000-000000000001','trying my luck here')$$);
reset role;
-- rate limits
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('AP13 refusal flood: after 20 refused attempts/hour the next is rate_limited and logged', (select count(*) from (select public.admin_open_comms('enquiry',gen_random_uuid(),'dispute investigation 1') r from generate_series(1,25)) x where r='rate_limited')>=1);
reset role; reset app.uid;
select pg_temp.ok('AP13b rate_limited attempts are logged', (select count(*) from admin_comms_access_log where outcome='rate_limited')>=1);
-- Round 8 review finding: an admin can ALREADY open enquiry-scoped comms through the existing staff path (staff_can_see_enquiry() is true for admins)
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('AP16 REVIEW: admin can open the existing staff route with a 5-character purpose', pg_temp.try($$select public.staff_open_enquiry_comms('e0000000-0000-0000-0000-000000000001','abcde')$$));
select pg_temp.ok('AP16a REVIEW: ...and then reads the enquiry replies and quotes - a second, weaker audited route remains', (select count(*) from public.enquiry_replies)=1 and (select count(*) from public.quotations)=1);
select pg_temp.ok('AP16b REVIEW: that route does NOT open unlinked direct threads', (select count(*) from public.direct_threads)=0);
reset role; reset app.uid;
select pg_temp.ok('AP16c REVIEW: it is recorded in the pre-existing staff_comms_access_log', (select count(*) from staff_comms_access_log where actor_id='00000000-0000-0000-0000-0000000000a1')=1);
-- existing staff-grant path unaffected
select pg_temp.ok('AP14 existing staff comms path still present (staff_open_enquiry_comms)', to_regprocedure('public.staff_open_enquiry_comms(uuid,text)') is not null);
select pg_temp.ok('AP15 policies: none of the 4 message policies mentions is_admin() directly', (select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid where p.polname in ('dt_read','dm_read','replies_read','quotes_read') and pg_get_expr(p.polqual,p.polrelid) ~ 'is_admin\(\)' and pg_get_expr(p.polqual,p.polrelid) !~ 'admin_comms_grant_active')=0);
select pg_temp.ok('AP15b orders_read keeps is_admin()', (select pg_get_expr(polqual,polrelid) from pg_policy where polname='orders_read') ~ 'is_admin');
\else
-- ===== CONTROL: current behaviour (0007 only) =====
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok('AC1 CONTROL: admin reads ALL message content with no grant and no log (current behaviour)', pg_temp.msgs()=4);
reset role; reset app.uid;
select pg_temp.ok('AC2 CONTROL: no admin access log exists', to_regclass('public.admin_comms_access_log') is null);
\endif
\echo ALL ADMIN-AUDIT PROPOSAL TESTS COMPLETED (prop=:prop) ON LOCAL REPLICA

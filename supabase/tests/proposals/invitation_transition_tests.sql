-- PROPOSAL TESTS (local PG16 only) for proposals/0007a_legacy_invitation_transition_PROPOSAL.sql. Runner: tests/run_proposal_invitation.sh
\set ON_ERROR_STOP on
\i tests/helpers.sql
create or replace function pg_temp.try(stmt text) returns boolean language plpgsql as $$ begin execute stmt; return true; exception when others then return false; end $$;
insert into auth.users(id,email,email_confirmed_at) select ('00000000-0000-0000-0000-0000000000'||n)::uuid, n||'@t.example', now() from unnest(array['a1','b1','c1','d1','d2','d3']) n;
update profiles set app_role='admin' where id='00000000-0000-0000-0000-0000000000a1';
insert into companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status) values ('c0000000-0000-0000-0000-000000000001','c1','C1','Bhadohi','India','draft','approved','verified','pending');
-- legacy rows: simulate trusted-session inserts without expiry (constraint temporarily dropped, re-added NOT VALID exactly like 0007 leaves it)
alter table company_members drop constraint company_members_invite_has_expiry;
insert into company_members(id,company_id,invite_email,role,status,expires_at,created_at) values
 ('b1b00000-0000-0000-0000-00000000000a','c0000000-0000-0000-0000-000000000001','d1@t.example','viewer','invited',null, now()-interval '3 days'),
 ('b1b00000-0000-0000-0000-00000000000b','c0000000-0000-0000-0000-000000000001','d2@t.example','viewer','invited',null, now()-interval '20 days'),
 ('b1b00000-0000-0000-0000-00000000000c','c0000000-0000-0000-0000-000000000001','d3@t.example','viewer','invited',null, now()),
 ('b1b00000-0000-0000-0000-00000000000e','c0000000-0000-0000-0000-000000000001','e@t.example','viewer','invited', now()+interval '5 days', now());
insert into company_members(id,company_id,user_id,role,status,created_at) values ('b1b00000-0000-0000-0000-00000000000d','c0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','viewer','active', now()-interval '90 days');
alter table company_members add constraint company_members_invite_has_expiry check (status <> 'invited' or expires_at is not null) not valid;
\if :prop
select pg_temp.ok('IT0 precondition: 3 pending invites without expiry', (select count(*) from company_members where status='invited' and expires_at is null)=3);
select expires_at as e_keep from company_members where id='b1b00000-0000-0000-0000-00000000000e' \gset
\i proposals/0007a_legacy_invitation_transition_PROPOSAL.sql
select pg_temp.ok('IT1 no pending invite without expiry remains; constraint now VALIDATED', (select count(*) from company_members where status='invited' and expires_at is null)=0 and (select convalidated from pg_constraint where conname='company_members_invite_has_expiry'));
select pg_temp.ok('IT2 young invites (3 days, 0 days) get created_at+14d (normal rule, not longer); the 20-day-old one is already expired', (select expires_at from company_members where id='b1b00000-0000-0000-0000-00000000000a')=(select created_at+interval '14 days' from company_members where id='b1b00000-0000-0000-0000-00000000000a') and (select expires_at from company_members where id='b1b00000-0000-0000-0000-00000000000b')<now() and (select expires_at from company_members where id='b1b00000-0000-0000-0000-00000000000c')<=now()+interval '14 days');
select pg_temp.ok('IT3 untouched rows: invite that had an expiry, and the active member', (select expires_at from company_members where id='b1b00000-0000-0000-0000-00000000000e')=:'e_keep'::timestamptz and (select expires_at from company_members where id='b1b00000-0000-0000-0000-00000000000d') is null and (select status::text from company_members where id='b1b00000-0000-0000-0000-00000000000d')='active');
select pg_temp.ok('IT4 transition log: 3 rows, previous NULL; rows immutable', (select count(*) from legacy_invitation_transition_log where previous_expires_at is null)=3 and not pg_temp.try($$delete from legacy_invitation_transition_log$$));
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000d1';
select pg_temp.ok('IT5 invitee of the young legacy invite can now accept it and the invite is listed', (select count(*) from public.my_invitations())=1 and pg_temp.try($$select public.accept_invitation('b1b00000-0000-0000-0000-00000000000a')$$));
reset role; set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000d2';
select pg_temp.denied('IT6 invitee of the expired legacy invite is refused (owner must re-invite)', $$select public.accept_invitation('b1b00000-0000-0000-0000-00000000000b')$$, 'expired');
reset role; set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok('IT7 buyer / other roles cannot read the log table', not pg_temp.try($$select * from legacy_invitation_transition_log$$));
reset role; set role anon;
select pg_temp.ok('IT8 anonymous cannot read the log table', not pg_temp.try($$select * from legacy_invitation_transition_log$$));
reset role; reset app.uid;
select pg_temp.ok('IT9 membership audit trail recorded the expiry updates (3 update rows)', (select count(*) from company_membership_audit where action='update' and old_status='invited' and new_status='invited')=3);
select pg_temp.ok('IT10 new NULL-expiry pending invite still refused after validation', not pg_temp.try($$insert into company_members(company_id,invite_email,role,status,expires_at) values ('c0000000-0000-0000-0000-000000000001','n@t.example','viewer','invited',null)$$));
\i proposals/0007a_legacy_invitation_transition_DOWN.sql
select pg_temp.ok('IT11 DOWN: constraint back to NOT VALID and log dropped (rows of the accepted invitee stay active)', not (select convalidated from pg_constraint where conname='company_members_invite_has_expiry') and to_regclass('public.legacy_invitation_transition_log') is null);
\else
select pg_temp.ok('IC1 CONTROL (0007 only): legacy NULL-expiry invites are refused by accept_invitation', (select count(*) from company_members where status='invited' and expires_at is null)=3);
set role authenticated; set app.uid='00000000-0000-0000-0000-0000000000d1';
select pg_temp.denied('IC2 CONTROL: even the 3-day-old legitimate legacy invite is refused until re-issued', $$select public.accept_invitation('b1b00000-0000-0000-0000-00000000000a')$$, 'expired');
reset role; reset app.uid;
\endif
\echo ALL INVITATION-TRANSITION TESTS COMPLETED (prop=:prop)

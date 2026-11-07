\set ON_ERROR_STOP on
create or replace function pg_temp.ok(name text, cond boolean) returns void language plpgsql as $$ begin if cond then raise notice 'PASS: %', name; else raise exception 'FAIL: %', name; end if; end $$;
-- fixtures (superuser)
insert into profiles values ('00000000-0000-0000-0000-0000000000a1','admin'),('00000000-0000-0000-0000-0000000000a2','reviewer'),('00000000-0000-0000-0000-0000000000b1','buyer'),('00000000-0000-0000-0000-0000000000c1','seller'),('00000000-0000-0000-0000-0000000000c2','seller');
insert into companies(id,name) values ('11111111-1111-1111-1111-111111111111','Co A'),('22222222-2222-2222-2222-222222222222','Co B');
insert into company_members(company_id,user_id,role) values ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-0000000000c1','owner'),('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-0000000000c2','owner');
grant usage on schema public to anon, authenticated;
grant select on profiles, companies, company_members to authenticated;

-- staff adds contacts
set app.uid='00000000-0000-0000-0000-0000000000a2'; set role authenticated;
select pg_temp.ok('staff can add email contact', public.staff_add_contact('11111111-1111-1111-1111-111111111111','email','Sales@CoA.example','official_website','Co A website','https://coa.example/contact') is not null);
select public.staff_add_contact('11111111-1111-1111-1111-111111111111','phone','+91 98765 43210','public_business_directory','Directory X');
select public.staff_add_contact('22222222-2222-2222-2222-222222222222','email','info@cob.example','official_website','Co B website');
do $$ begin begin perform public.staff_add_contact('11111111-1111-1111-1111-111111111111','email','not-an-email','official_website','x'); raise exception 'FAIL: invalid email accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: invalid email rejected'; end; end $$;
do $$ begin begin perform public.staff_add_contact('11111111-1111-1111-1111-111111111111','phone','abc','official_website','x'); raise exception 'FAIL: invalid phone accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: invalid phone rejected'; end; end $$;
do $$ begin begin perform public.staff_add_contact('11111111-1111-1111-1111-111111111111','email','x@y.zz','official_website',''); raise exception 'FAIL: missing source accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: missing source rejected'; end; end $$;
do $$ begin begin perform public.staff_add_contact('11111111-1111-1111-1111-111111111111','email','SALES@coa.example','official_website','dup'); raise exception 'FAIL: duplicate accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: duplicate contact (case-insensitive) rejected'; end; end $$;
select pg_temp.ok('staff direct SELECT on vault returns 0 rows (must use audited RPC)', (select count(*) from company_contacts)=0);
select pg_temp.ok('staff_get_contacts returns 2 rows for Co A', (select count(*) from public.staff_get_contacts('11111111-1111-1111-1111-111111111111','call prep'))=2);
do $$ begin begin perform * from public.staff_get_contacts('11111111-1111-1111-1111-111111111111',''); raise exception 'FAIL: empty purpose accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: purpose required'; end; end $$;
select pg_temp.ok('staff cannot read the access log', (select count(*) from contact_access_log)=0);
select public.staff_set_contact_status((select id from public.staff_get_contacts('11111111-1111-1111-1111-111111111111','x') where kind='email'),'do_not_contact','supplier asked');
select pg_temp.ok('do-not-contact value is withheld', (select value from public.staff_get_contacts('11111111-1111-1111-1111-111111111111','x') where kind='email') is null);
do $$ begin begin perform public.staff_set_contact_status((select id from public.staff_get_contacts('11111111-1111-1111-1111-111111111111','x') where kind='email'),'unverified','retry'); raise exception 'FAIL: reviewer cleared DNC'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: reviewer cannot clear do-not-contact'; end; end $$;
reset role;

-- admin
set app.uid='00000000-0000-0000-0000-0000000000a1'; set role authenticated;
select pg_temp.ok('admin can read audit log', (select count(*) from contact_access_log)>=6);
select public.staff_set_contact_status((select id from public.staff_get_contacts('11111111-1111-1111-1111-111111111111','admin review') where kind='email'),'unverified','admin cleared');
select pg_temp.ok('admin cleared DNC logged', (select count(*) from contact_access_log where action='set_status')=2);
do $$ begin begin update contact_access_log set purpose='x'; raise exception 'FAIL: log mutable'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: log update blocked'; end; end $$;
reset role;
do $$ begin begin delete from contact_access_log; raise exception 'FAIL: log deletable'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: log delete blocked (even superuser, trigger)'; end; end $$;

-- sellers / buyers / anon
set app.uid='00000000-0000-0000-0000-0000000000c1'; set role authenticated;
select pg_temp.ok('owner A sees only own company contacts', (select count(*) from company_contacts)=2 and not exists(select 1 from company_contacts where company_id='22222222-2222-2222-2222-222222222222'));
do $$ begin begin perform * from public.staff_get_contacts('22222222-2222-2222-2222-222222222222','snoop'); raise exception 'FAIL: seller used staff RPC'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: seller cannot call staff_get_contacts'; end; end $$;
reset role;
set app.uid='00000000-0000-0000-0000-0000000000b1'; set role authenticated;
select pg_temp.ok('buyer sees 0 contacts', (select count(*) from company_contacts)=0);
reset role;
set role anon;
do $$ begin begin perform count(*) from company_contacts; raise exception 'FAIL: anon select allowed'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: anon cannot select vault'; end; end $$;
do $$ begin begin perform * from public.staff_get_contacts('11111111-1111-1111-1111-111111111111','x'); raise exception 'FAIL: anon exec'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: anon cannot execute staff RPC'; end; end $$;
reset role;
-- schema extensions
do $$ begin begin update companies set business_types='{spaceship}' where name='Co A'; raise exception 'FAIL: bad business type'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: invalid business type rejected'; end; end $$;
update companies set business_types='{manufacturer,exporter}', export_markets='{USA,UAE}' where name='Co A';
select pg_temp.ok('multi business type stored', (select cardinality(business_types) from companies where name='Co A')=2);
select pg_temp.ok('is_demo defaults false', (select not is_demo from companies where name='Co A'));
insert into categories(slug,name) values ('t','Top'); insert into categories(slug,name,parent_id) values ('s','Sub',1);
select pg_temp.ok('subcategory parent link', (select parent_id from categories where slug='s')=1);

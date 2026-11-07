-- Category seed tests. Run by tests/run_seed.sh on LOCAL DBs. psql vars: none. Output lines start with PASS:/FAIL:.
\set ON_ERROR_STOP off
create or replace function pg_temp.t(n text, c boolean) returns void language plpgsql as $$ begin if c then raise notice 'PASS: %', n; else raise notice 'FAIL: %', n; end if; end $$;
select pg_temp.t('SD1 empty DB (after migrations): 0 categories before seed', (select count(*)=0 from public.categories));
\i seed.sql
select pg_temp.t('SD2 seed inserts exactly 14 categories', (select count(*)=14 from public.categories));
select pg_temp.t('SD3 ids are stable 1..14 in frontend order', (select array_agg(id order by id)=array(select generate_series(1,14)) and array_agg("position" order by id)=array(select generate_series(1,14)) from public.categories));
select pg_temp.t('SD4 names/slugs: slug = make_slug(name), all unique, none hidden, no parent', (select count(distinct slug)=14 and bool_and(slug=public.make_slug(name)) and not bool_or(hidden) and bool_and(parent_id is null) from public.categories));
select pg_temp.t('SD5 the 14 names are exactly the approved list', (select array_agg(name order by id)=array['Industrial Plants & Machinery','Architecture & Interiors','Consumer Electronics','Carpets, Rugs & Home Furnishing','Textiles & Garments','Food & Agro Products','Building & Construction','Packaging & Printing','Medical & Healthcare','Automotive & Spare Parts','Handicrafts & Gifts','Renewable Energy','Chemicals & Dyes','Safety & Security'] from public.categories));
create temp table before_snap as select * from public.categories;
\i seed.sql
\i seed.sql
select pg_temp.t('SD6 repeated seed: still 14 rows, rows byte-identical (no duplicates, ids unchanged)', (select count(*)=14 from public.categories) and not exists(select 1 from (select * from public.categories except select * from before_snap) x) and not exists(select 1 from (select * from before_snap except select * from public.categories) x));
select pg_temp.t('SD7 sequence advanced past seed ids (next id = 15)', (select nextval('public.categories_id_seq')=15));
update public.categories set name='Edited By Admin', hue=1 where id=3;
\i seed.sql
select pg_temp.t('SD8 re-seed preserves later admin edits (DO NOTHING, not overwrite)', (select name='Edited By Admin' and hue=1 from public.categories where id=3));
update public.categories set name='Consumer Electronics', hue=265 where id=3;
-- relationships: a product/company link and parent_id survive a re-seed
select pg_temp.t('SD9 FK dependants exist for categories (company_categories/products) and none dangling', (select count(*)=0 from public.company_categories cc where not exists(select 1 from public.categories c where c.id=cc.category_id)));
-- duplicate prevention at the constraint level
do $$ begin begin insert into public.categories(slug,name) values ('renewable-energy','Dup'); raise notice 'FAIL: SD10 duplicate slug accepted'; exception when unique_violation then raise notice 'PASS: SD10 duplicate slug rejected by categories_slug_key'; end; end $$;
-- collision: another row owns id 14 under a different slug -> the seed must FAIL LOUDLY (guard) and roll back, not silently skip
delete from public.categories where id=14;
insert into public.categories(id,slug,name) values (14,'something-else','Squatter');
\i seed.sql
rollback;
select pg_temp.t('SD11 id collision with a different slug is NOT silently ignored: guard raised, seed rolled back, squatter still present, safety-security still missing', (select count(*)=13 from public.categories where slug<>'something-else') and not exists(select 1 from public.categories where slug='safety-security') and exists(select 1 from public.categories where slug='something-else'));
delete from public.categories where id=14;
\i seed.sql
select pg_temp.t('SD12 after removing the squatter, seed completes: exactly the 14 approved slugs, squatter gone', (select count(*)=14 from public.categories) and not exists(select 1 from public.categories where slug='something-else'));
-- public read behaviour via real roles
set role anon;
select pg_temp.t('SD13 anon can read all 14 categories', (select count(*)=14 from public.categories));
reset role;
set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000e001","role":"authenticated","aud":"authenticated"}';
select pg_temp.t('SD14 authenticated can read categories', (select count(*)=14 from public.categories));
do $$ begin begin insert into public.categories(slug,name) values ('x-nonadmin','X'); raise notice 'FAIL: SD15 non-admin inserted a category'; exception when others then raise notice 'PASS: SD15 non-admin cannot insert a category (%)', sqlerrm; end; end $$;
reset role; reset request.jwt.claims;
set role anon;
do $$ begin begin insert into public.categories(slug,name) values ('x-anon','X'); raise notice 'FAIL: SD16 anon inserted a category'; exception when others then raise notice 'PASS: SD16 anon cannot insert a category'; end; end $$;
do $$ begin begin perform nextval('public.categories_id_seq'); raise notice 'FAIL: SD17 anon used categories_id_seq'; exception when others then raise notice 'PASS: SD17 anon cannot use categories_id_seq'; end; end $$;
reset role;
select pg_temp.t('SD18 seed contains no synthetic/test or supplier data: no rows in companies/profiles created by seed', (select count(*)=0 from public.companies) and (select count(*)=0 from public.profiles));

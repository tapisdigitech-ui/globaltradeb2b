-- Read-only inventory run on the LOCAL clone (post-0006). Each section must return the stated expectation.
\echo '1. SECURITY DEFINER functions in public without a pinned search_path (expect 0)'
select p.proname from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and not exists(select 1 from unnest(coalesce(p.proconfig,'{}')) c where c like 'search_path=%');
\echo '2. public functions executable by anon (expect only the known public-by-design list)'
select p.proname from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f' and has_function_privilege('anon',p.oid,'execute') order by 1;
\echo '3. public tables without ENABLE+FORCE RLS (expect 0)'
select c.relname from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and not (c.relrowsecurity and c.relforcerowsecurity);
\echo '4. RLS tables with zero policies (deny-all by design; expect only definer-only tables)'
select c.relname from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and c.relrowsecurity and not exists(select 1 from pg_policy p where p.polrelid=c.oid) order by 1;
\echo '5. tables where anon holds any privilege (expect 0)'
select table_name, string_agg(privilege_type,',') from information_schema.role_table_grants where table_schema='public' and grantee='anon' and table_name not like 'public\_%' group by 1;
\echo '6. storage.objects policies'
select polname, polcmd, (select coalesce(string_agg(rolname,','),'PUBLIC') from pg_roles where oid=any(polroles)) roles from pg_policy where polrelid='storage.objects'::regclass order by 1;
\echo '7. new-in-0006 tables: grants to authenticated (expect SELECT only, or none)'
select table_name, string_agg(privilege_type,',') from information_schema.role_table_grants where table_schema='public' and grantee='authenticated' and table_name in ('claim_reviewer_assignments','claim_evidence_access_log','claim_evidence_grants','staff_comms_access_log','staff_comms_grants','review_recommendations') group by 1 order by 1;
\echo '8. policies still referencing bare is_staff() on confidential tables'
select c.relname, p.polname from pg_policy p join pg_class c on c.oid=p.polrelid where c.relnamespace='public'::regnamespace and (pg_get_expr(p.polqual,p.polrelid) like '%is_staff()%' or pg_get_expr(p.polwithcheck,p.polrelid) like '%is_staff()%') order by 1,2;

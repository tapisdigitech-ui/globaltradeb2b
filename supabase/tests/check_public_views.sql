-- Read-only audit of the public_* views. Run against a schema-only restore of staging (or staging itself with a read-only role).
-- 1) definition, options, owner  2) output columns vs approved allowlist  3) flagged column names  4) base tables read  5) publication filter present?
\echo '== view options / owner'
select c.relname, coalesce(array_to_string(c.reloptions,','),'(none)') as options, pg_get_userbyid(c.relowner) as owner from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v' and c.relname like 'public\_%' order by 1;
\echo '== view definitions'
select viewname, definition from pg_views where schemaname='public' and viewname like 'public\_%' order by 1;
\echo '== base relations each view depends on'
select distinct v.relname as view, t.relname as depends_on from pg_depend d join pg_rewrite r on r.oid=d.objid join pg_class v on v.oid=r.ev_class join pg_class t on t.oid=d.refobjid and t.relkind in ('r','v') and t.oid<>v.oid join pg_namespace n on n.oid=v.relnamespace where n.nspname='public' and v.relname like 'public\_%' order by 1,2;
\echo '== FLAG: columns whose names suggest private data (must return 0 rows)'
select table_name, column_name from information_schema.columns where table_schema='public' and table_name like 'public\_%' and column_name ~* '(phone|email|mail|address|pin$|contact|token|hash|secret|password|code$|buyer|private|internal|note|value|iban|gst|bank|dedupe|created_by|verified_by|reviewed_by)';
\echo '== FLAG: views not filtering on publication/approval (inspect manually if listed)'
select viewname from pg_views where schemaname='public' and viewname like 'public\_%' and definition !~* '(published|approved|rights_status|review_status)';
\echo '== anon/authenticated privileges on public_* views (should be SELECT only)'
select table_name, grantee, string_agg(privilege_type, ',') from information_schema.role_table_grants where table_schema='public' and table_name like 'public\_%' and grantee in ('anon','authenticated') group by 1,2 order by 1,2;

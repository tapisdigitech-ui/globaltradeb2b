\set ON_ERROR_STOP on
create or replace function pg_temp.ok(name text, cond boolean) returns void language plpgsql as $$ begin if coalesce(cond,false) then raise notice 'PASS: %', name; else raise exception 'FAIL: %', name; end if; end $$;
-- expects the statement to raise an error (optionally containing a text fragment)
create or replace function pg_temp.denied(name text, stmt text, frag text default null) returns void language plpgsql as $$
begin
  begin execute stmt; exception when others then
    if frag is not null and position(lower(frag) in lower(sqlerrm)) = 0 then raise exception 'FAIL: % (wrong error: %)', name, sqlerrm; end if;
    raise notice 'PASS: % [%]', name, left(sqlerrm, 60); return; end;
  raise exception 'FAIL: % (no error raised)', name;
end $$;
create or replace function pg_temp.cnt(stmt text) returns bigint language plpgsql as $$ declare n bigint; begin execute 'select count(*) from (' || stmt || ') q' into n; return n; end $$;
create or replace function pg_temp.affected(stmt text) returns bigint language plpgsql as $$ declare n bigint; begin execute stmt; get diagnostics n = row_count; return n; end $$;

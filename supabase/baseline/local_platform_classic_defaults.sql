-- LOCAL STAND-IN for the Supabase-managed platform. NOT a migration. Never run on a hosted project.
-- Mirrors what the read-only staging catalogue showed (2026-11-07): extensions live in schema "extensions", the "postgres" role's
-- default privileges in schema public give service_role only D/x/t(/m) on NEW tables and nothing to anon/authenticated,
-- new functions keep the PostgreSQL default (PUBLIC execute), postgres role search_path = "$user", public, extensions.
-- Stubs: auth.users/auth.uid(), storage.buckets/objects/foldername(). The real auth/storage schemas are Supabase-managed and
-- CANNOT be validated locally.
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema extensions;
create extension pgcrypto with schema extensions;
create extension pg_trgm with schema extensions;
create extension "uuid-ossp" with schema extensions;
create schema auth; create schema storage;
create table auth.users(id uuid primary key default gen_random_uuid(), email text, email_confirmed_at timestamptz, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('app.uid',true),'')::uuid $$;
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text);
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
alter table storage.objects enable row level security;
grant usage on schema public, auth, storage, extensions to anon, authenticated, service_role;
grant select on auth.users to postgres;
-- hosted pg_default_acl for role postgres in schema public (tables: postgres + service_role=Dxtm; functions/sequences: owner only)
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role; alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role; alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
alter role postgres set search_path = "$user", public, extensions;

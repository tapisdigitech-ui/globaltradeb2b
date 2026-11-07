-- Minimal stand-in for the parts of the staging schema that 0001 depends on. TEST ONLY. Not the real schema.
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('app.uid',true),'')::uuid $$;
grant usage on schema auth, public to anon, authenticated;
create type public.member_role as enum ('owner','manager','sales','catalogue_editor','viewer');
create type public.app_role as enum ('buyer','seller','reviewer','admin');
create type public.source_type as enum ('official_website','public_business_directory','trade_association','exhibitor_directory','government_registry','direct_submission','licensed_data_provider','other_approved');
create table public.profiles(id uuid primary key, app_role public.app_role not null default 'buyer');
create table public.categories(id serial primary key, slug text, name text);
create table public.companies(id uuid primary key default gen_random_uuid(), name text not null, claim_status text default 'unclaimed');
create table public.company_members(id uuid primary key default gen_random_uuid(), company_id uuid, user_id uuid, role public.member_role, status text default 'active');
create function public.is_staff() returns boolean language sql stable security definer as $$ select exists(select 1 from profiles where id=auth.uid() and app_role in ('admin','reviewer')) $$;
create function public.is_admin() returns boolean language sql stable security definer as $$ select exists(select 1 from profiles where id=auth.uid() and app_role='admin') $$;
create function public.has_company_role(cid uuid, roles public.member_role[]) returns boolean language sql stable security definer as $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active' and m.role=any(roles)) $$;
create function public.block_mutation() returns trigger language plpgsql as $$ begin raise exception 'immutable'; end $$;

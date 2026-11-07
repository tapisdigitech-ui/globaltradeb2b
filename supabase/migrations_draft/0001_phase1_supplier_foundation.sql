-- DRAFT — NOT APPLIED to any Supabase project. Locally tested on a scratch Postgres 16 with stub baseline only.
-- Phase 1 (G1,G2,G3 of IMPLEMENTATION_ROADMAP.md). Additive only; no drops, no data changes.
-- Review before staging apply. Assumes existing: companies, categories, source_type enum, is_staff(), is_admin(), has_company_role(), block_mutation().

begin;

-- G3: subcategories (flat categories stay valid; parent_id null = top level)
alter table public.categories add column if not exists parent_id integer references public.categories(id) on delete restrict;
create index if not exists categories_parent_idx on public.categories(parent_id);

-- G2: profile extensions. Not exposed by any public view until a view is deliberately changed.
alter table public.companies
  add column if not exists is_demo boolean not null default false,          -- demo rows are excluded from all reports
  add column if not exists business_types text[] not null default '{}',      -- brief: a business may have several types, evidence-backed
  add column if not exists export_markets text[] not null default '{}',      -- ISO country names/codes
  add column if not exists capabilities text;                               -- manufacturing/supply capability summary (reviewed before publish)
alter table public.companies
  add constraint companies_business_types_valid check (business_types <@ array['manufacturer','wholesaler','distributor','exporter','importer','trader','supplier','service_provider']);

-- G1: contact vault v2 — separate from company_private (which stays as is until migrated)
create table if not exists public.company_contacts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('phone','email')),
  value text not null check (length(value) between 5 and 200),
  value_norm text generated always as (lower(trim(value))) stored,
  status text not null default 'unverified' check (status in ('unverified','verified','invalid','do_not_contact')),
  source_type public.source_type not null,
  source_name text not null,
  source_url text,
  collected_at timestamptz not null default now(),
  last_verified_at timestamptz,
  verified_by uuid,
  legal_basis text not null default 'legitimate_interest_b2b_public' ,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (company_id, kind, value_norm)
);
comment on table public.company_contacts is 'class=private; discovered/verified business contacts. No anon/buyer access. Staff read ONLY through staff_get_contacts() (audited). Company owner/manager may read their own.';
alter table public.company_contacts enable row level security;
revoke all on public.company_contacts from anon, authenticated, public;
grant select on public.company_contacts to authenticated;
create policy ccontacts_own_read on public.company_contacts for select to authenticated
  using (public.has_company_role(company_id, array['owner'::public.member_role,'manager'::public.member_role]));

create table if not exists public.contact_access_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  action text not null check (action in ('view','add','set_status')),
  company_id uuid not null,
  contact_id uuid,
  purpose text not null,
  at timestamptz not null default now()
);
comment on table public.contact_access_log is 'class=staff; immutable audit of every contact-vault view/add/status change.';
alter table public.contact_access_log enable row level security;
revoke all on public.contact_access_log from anon, authenticated, public;
create policy calog_admin_read on public.contact_access_log for select to authenticated using (public.is_admin());
grant select on public.contact_access_log to authenticated;
create trigger calog_immutable before update or delete on public.contact_access_log
  for each row execute function public.block_mutation();

-- Staff add a contact (never exposed publicly). Format validated; no auto-verification.
create or replace function public.staff_add_contact(p_company uuid, p_kind text, p_value text,
  p_source_type public.source_type, p_source_name text, p_source_url text default null, p_purpose text default 'acquisition')
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v text := trim(p_value); cid uuid;
begin
  if not public.is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  if p_kind='email' and v !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email'; end if;
  if p_kind='phone' and v !~ '^[0-9+\-\s()]{7,20}$' then raise exception 'invalid phone'; end if;
  if p_kind not in ('email','phone') then raise exception 'invalid kind'; end if;
  if coalesce(trim(p_source_name),'')='' then raise exception 'source required'; end if;
  insert into public.company_contacts(company_id,kind,value,source_type,source_name,source_url,created_by)
    values (p_company,p_kind,v,p_source_type,p_source_name,p_source_url,auth.uid()) returning id into cid;
  insert into public.contact_access_log(actor_id,action,company_id,contact_id,purpose) values (auth.uid(),'add',p_company,cid,left(p_purpose,200));
  return cid;
end $$;

-- Staff read: audited, a purpose is mandatory, do-not-contact rows return no value.
create or replace function public.staff_get_contacts(p_company uuid, p_purpose text)
returns table(id uuid, kind text, value text, status text, source_name text, source_url text, last_verified_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  if coalesce(trim(p_purpose),'')='' then raise exception 'purpose required'; end if;
  insert into public.contact_access_log(actor_id,action,company_id,purpose) values (auth.uid(),'view',p_company,left(p_purpose,200));
  return query select c.id,c.kind,case when c.status='do_not_contact' then null else c.value end,c.status,c.source_name,c.source_url,c.last_verified_at
    from public.company_contacts c where c.company_id=p_company order by c.kind,c.created_at;
end $$;

create or replace function public.staff_set_contact_status(p_contact uuid, p_status text, p_purpose text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare cc public.company_contacts;
begin
  if not public.is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  if p_status not in ('unverified','verified','invalid','do_not_contact') then raise exception 'invalid status'; end if;
  select * into cc from public.company_contacts where id=p_contact; if not found then raise exception 'not found'; end if;
  if cc.status='do_not_contact' and not public.is_admin() then raise exception 'only admin can clear do-not-contact'; end if;
  update public.company_contacts set status=p_status,
    last_verified_at = case when p_status='verified' then now() else last_verified_at end,
    verified_by = case when p_status='verified' then auth.uid() else verified_by end where id=p_contact;
  insert into public.contact_access_log(actor_id,action,company_id,contact_id,purpose) values (auth.uid(),'set_status',cc.company_id,p_contact,left(coalesce(p_purpose,''),200));
end $$;

revoke all on function public.staff_add_contact(uuid,text,text,public.source_type,text,text,text) from public, anon;
revoke all on function public.staff_get_contacts(uuid,text) from public, anon;
revoke all on function public.staff_set_contact_status(uuid,text,text) from public, anon;
grant execute on function public.staff_add_contact(uuid,text,text,public.source_type,text,text,text) to authenticated;
grant execute on function public.staff_get_contacts(uuid,text) to authenticated;
grant execute on function public.staff_set_contact_status(uuid,text,text) to authenticated;

commit;

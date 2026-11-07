-- DRAFT — NOT APPLIED to any Supabase project. Additive. Depends on: companies, categories, source_type, is_staff(), is_admin(), has_company_role(), block_mutation().
begin;
-- Subcategories
alter table public.categories add column if not exists parent_id integer references public.categories(id) on delete restrict;
create index if not exists categories_parent_idx on public.categories(parent_id);
-- Profile extensions (not exposed by any public view until a view is deliberately changed)
alter table public.companies
  add column if not exists is_demo boolean not null default false,
  add column if not exists business_types text[] not null default '{}',
  add column if not exists export_markets text[] not null default '{}',
  add column if not exists capabilities text,
  add column if not exists lead_delivery_blocked boolean not null default false;  -- admin can stop direct leads for a seller (restriction)
alter table public.companies add constraint companies_business_types_valid
  check (business_types <@ array['manufacturer','wholesaler','distributor','exporter','importer','trader','supplier','service_provider']);

-- Contact vault v2
create table public.company_contacts (
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
  legal_basis text not null default 'legitimate_interest_b2b_public',
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (company_id, kind, value_norm)
);
comment on table public.company_contacts is 'class=private; business contacts. No anon/buyer/staff direct access. Staff read only via staff_get_contacts() (purpose + assignment + immutable audit). Company owner/manager may read their own.';
alter table public.company_contacts enable row level security;
revoke all on public.company_contacts from anon, authenticated, public;
grant select on public.company_contacts to authenticated;
create policy ccontacts_own_read on public.company_contacts for select to authenticated
  using (public.has_company_role(company_id, array['owner'::public.member_role,'manager'::public.member_role]));

create table public.contact_access_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  action text not null check (action in ('view','add','set_status')),
  company_id uuid not null,
  contact_id uuid,
  purpose text not null check (length(trim(purpose))>0),
  lead_case_id uuid,
  claim_id uuid,
  at timestamptz not null default now()
);
comment on table public.contact_access_log is 'class=staff; immutable audit of contact-vault view/add/status change, with related lead case or claim.';
alter table public.contact_access_log enable row level security;
revoke all on public.contact_access_log from anon, authenticated, public;
grant select on public.contact_access_log to authenticated;
create policy calog_admin_read on public.contact_access_log for select to authenticated using (public.is_admin());
create trigger calog_immutable before update or delete on public.contact_access_log for each row execute function public.block_mutation();
commit;

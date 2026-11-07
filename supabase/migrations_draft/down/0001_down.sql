begin;
drop table if exists public.contact_access_log;
drop table if exists public.company_contacts;
alter table public.companies drop constraint if exists companies_business_types_valid;
alter table public.companies drop column if exists is_demo, drop column if exists business_types, drop column if exists export_markets, drop column if exists capabilities, drop column if exists lead_delivery_blocked;
drop index if exists public.categories_parent_idx;
alter table public.categories drop column if exists parent_id;
commit;

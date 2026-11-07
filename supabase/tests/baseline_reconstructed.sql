-- RECONSTRUCTED BASELINE (TEST ONLY) — rebuilt from read-only catalog queries of staging on 2026-11-07
-- (table columns, enums, function signatures, recorded policy predicates, grants, storage policy names).
-- It is NOT the real staging schema: view bodies, trigger bodies, constraints, indexes, FK actions and most
-- function bodies were not captured. Replace with a `supabase db dump --schema-only` of staging before any apply.
-- Items marked GUESS are not from the catalog.
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;  -- as in Supabase
create extension if not exists pgcrypto;
create schema auth; create schema storage;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('app.uid',true),'')::uuid $$;
grant usage on schema public, auth, storage to anon, authenticated, service_role;

create type public.acquisition_status as enum ('not_contacted','contact_attempted','in_conversation','invited_to_claim','claim_started','declined','do_not_contact');
create type public.app_role as enum ('buyer','seller','reviewer','admin');
create type public.assoc_basis as enum ('manufacturer','brand_owner','distributor','reseller','marketplace_seller','unknown');
create type public.claim_status as enum ('unclaimed','claim_submitted','evidence_requested','under_review','approved','rejected','withdrawn');
create type public.directory_status as enum ('draft','pending_review','published','paused','rejected','suspended');
create type public.enquiry_delivery as enum ('stored','awaiting_admin','visible_to_seller','sent_external','failed');
create type public.enquiry_kind as enum ('product','requirement');
create type public.enquiry_status as enum ('new','read','replied','quoted','closed','spam');
create type public.image_rights as enum ('unknown','owned','licensed','permission_granted','public_domain','rejected');
create type public.member_role as enum ('owner','manager','sales','catalogue_editor','viewer');
create type public.member_status as enum ('invited','active','removed');
create type public.notif_kind as enum ('system','tip','lead','enquiry','message','moderation','claim','admin');
create type public.outreach_delivery as enum ('logged_manual','queued','sent','failed');
create type public.outreach_type as enum ('call','email','message','invitation','follow_up','note');
create type public.review_status as enum ('pending','approved','rejected');
create type public.source_type as enum ('official_website','public_business_directory','trade_association','exhibitor_directory','government_registry','direct_submission','licensed_data_provider','other_approved');
create type public.verification_status as enum ('not_verified','pending','verified','rejected','expired');

create table public.profiles(id uuid primary key, full_name text, phone text, company_name text, city text, country text, preferred_location text, app_role public.app_role not null default 'buyer', created_at timestamptz default now(), updated_at timestamptz default now());
create table public.categories(id serial primary key, slug text unique, name text, hue integer, spec_template jsonb, hidden boolean default false, position integer);
create table public.companies(id uuid primary key default gen_random_uuid(), slug text, name text not null, business_type text, about text, city text, state text, country text, website text, logo_path text,
  directory_status public.directory_status not null default 'draft', claim_status public.claim_status not null default 'unclaimed', verification_status public.verification_status not null default 'not_verified',
  verified_at timestamptz, verified_by uuid, data_review_status public.review_status not null default 'pending', data_reviewed_by uuid, data_reviewed_at timestamptz, dedupe_key text, import_batch_id uuid, created_by uuid, created_at timestamptz default now(), updated_at timestamptz default now());
create table public.company_categories(company_id uuid references public.companies(id) on delete cascade, category_id integer references public.categories(id), primary key(company_id,category_id));
create table public.company_members(id uuid primary key default gen_random_uuid(), company_id uuid references public.companies(id), user_id uuid, invite_email text, role public.member_role not null, status public.member_status not null default 'active', invited_by uuid, expires_at timestamptz, created_at timestamptz default now());
create table public.products(id uuid primary key default gen_random_uuid(), company_id uuid references public.companies(id), category_id integer, name text not null, description text, tags text, directory_status public.directory_status default 'draft', search tsvector);
create table public.company_private(company_id uuid primary key references public.companies(id), phone text, email text, address text, pin text, contact_person text, updated_at timestamptz default now());
create table public.company_claims(id uuid primary key default gen_random_uuid(), company_id uuid references public.companies(id), claimant_id uuid, claimant_role_title text, statement text, status public.claim_status not null default 'claim_submitted', decided_by uuid, decided_at timestamptz, decision_reason text, created_at timestamptz default now(), updated_at timestamptz default now());
create table public.company_claim_evidence(id uuid primary key default gen_random_uuid(), claim_id uuid references public.company_claims(id), storage_path text, description text, uploaded_by uuid, created_at timestamptz default now());
create table public.company_acquisition(company_id uuid primary key references public.companies(id), acquisition_status public.acquisition_status default 'not_contacted', last_contacted_at timestamptz, next_follow_up_at timestamptz, contact_channel text, contact_outcome text, owner_id uuid, updated_at timestamptz default now());
create table public.company_outreach_events(id uuid primary key default gen_random_uuid(), company_id uuid references public.companies(id), event_type public.outreach_type not null, channel text, summary text, outcome text, delivery public.outreach_delivery not null default 'logged_manual', provider_ref text, occurred_at timestamptz default now(), recorded_by uuid);
create table public.enquiries(id uuid primary key default gen_random_uuid(), ref text, kind public.enquiry_kind not null, buyer_id uuid not null, product_id uuid, company_id uuid, category_id integer, subject text, quantity numeric(14,2), unit text, message text, city text, status public.enquiry_status not null default 'new', delivery public.enquiry_delivery not null default 'stored', delivery_note text, created_at timestamptz default now(), updated_at timestamptz default now());
create table public.enquiry_private(enquiry_id uuid primary key references public.enquiries(id), buyer_name text, buyer_phone text, buyer_email text, buyer_company text, consent_at timestamptz, notice_version text);
create table public.notifications(id uuid primary key default gen_random_uuid(), user_id uuid, company_id uuid, kind public.notif_kind not null, title text, body text, link text, read_at timestamptz, created_at timestamptz default now());
create table public.rate_events(id bigint generated always as identity primary key, user_id uuid, action text, at timestamptz default now());
create table public.audit_log(id bigint generated always as identity primary key, actor_id uuid, actor_role text, action text, entity text, entity_id text, old_value jsonb, new_value jsonb, at timestamptz default now());
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text, name text);  -- STORAGE STUB (GUESS: real table has many more columns)
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name,'/') $$;

-- functions: bodies for is_admin/is_staff/lead_matches_my_company/seller_can_see_leads/staff_mark_enquiry are the REAL bodies (captured). Others are GUESS stand-ins.
create function public.is_admin() returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from profiles where id=auth.uid() and app_role='admin') $$;
create function public.is_staff() returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from profiles where id=auth.uid() and app_role in ('admin','reviewer')) $$;
create function public.has_company_role(cid uuid, roles public.member_role[]) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active' and m.role=any(roles)) $$; -- GUESS
create function public.is_company_member(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active') $$; -- GUESS
create function public.enquiry_buyer(eid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $$ select buyer_id from enquiries where id=eid $$; -- GUESS
create function public.claim_claimant(cid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $$ select claimant_id from company_claims where id=cid $$; -- GUESS
create function public.claim_is_open_for_me(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from company_claims where id=cid and claimant_id=auth.uid() and status in ('claim_submitted','evidence_requested','under_review')) $$; -- GUESS
create function public.safe_uuid(t text) returns uuid language plpgsql immutable set search_path to '' as $$ begin return t::uuid; exception when others then return null; end $$;
create function public.norm_domain(t text) returns text language sql immutable set search_path to '' as $$ select lower(regexp_replace(regexp_replace(coalesce(t,''),'^https?://(www\.)?',''),'[/:?#].*$','')) $$; -- GUESS
create function public.block_mutation() returns trigger language plpgsql set search_path to '' as $$ begin raise exception 'immutable'; end $$;
create function public.check_rate(p_action text, p_max integer, p_window interval) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$ begin if (select count(*) from rate_events where user_id=auth.uid() and action=p_action and at>now()-p_window)>=p_max then raise exception 'rate limit'; end if; insert into rate_events(user_id,action) values (auth.uid(),p_action); end $$; -- GUESS
create function public.seller_can_see_leads() returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from company_members m join companies c on c.id=m.company_id where m.user_id=auth.uid() and m.status='active' and c.claim_status='approved' and c.directory_status='published' and m.role in ('owner','manager','sales')) $$;
create function public.lead_matches_my_company(cat integer) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$ select exists(select 1 from company_members m join companies c on c.id=m.company_id where m.user_id=auth.uid() and m.status='active' and c.claim_status='approved' and c.directory_status='published' and m.role in ('owner','manager','sales') and (cat is null or exists(select 1 from company_categories cc where cc.company_id=c.id and cc.category_id=cat))) $$;
create function public.staff_mark_enquiry(p_enquiry uuid, p_delivery enquiry_delivery, p_note text, p_provider_ref text default null) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$ begin if not is_staff() then raise exception 'staff only' using errcode='42501'; end if; if p_delivery='sent_external' and coalesce(trim(p_provider_ref),'')='' then raise exception 'sent_external requires a provider reference'; end if; update enquiries set delivery=p_delivery, delivery_note=left(coalesce(p_note,'')||case when p_provider_ref is not null then ' [ref '||p_provider_ref||']' else '' end,500) where id=p_enquiry; if not found then raise exception 'enquiry not found'; end if; end $$;
create function public.submit_claim(p_company uuid, p_title text, p_statement text) returns uuid language plpgsql security definer set search_path to 'public','pg_temp' as $$ declare cl uuid; begin insert into company_claims(company_id,claimant_id,claimant_role_title,statement) values (p_company,auth.uid(),p_title,p_statement) returning id into cl; return cl; end $$; -- GUESS (real body also rate limits and updates companies.claim_status)
create function public.review_claim(p_claim uuid, p_decision claim_status, p_reason text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$ begin if not is_staff() then raise exception 'staff only'; end if; update company_claims set status=p_decision, decided_by=auth.uid(), decided_at=now(), decision_reason=p_reason where id=p_claim; if p_decision='approved' then update companies set claim_status='approved' where id=(select company_id from company_claims where id=p_claim); end if; end $$; -- GUESS

-- RLS enable + recorded policies (REAL predicates captured from pg_policies)
do $$ declare t text; begin foreach t in array array['profiles','categories','companies','company_categories','company_members','products','company_private','company_claims','company_claim_evidence','company_acquisition','company_outreach_events','enquiries','enquiry_private','notifications','rate_events','audit_log'] loop execute format('alter table public.%I enable row level security', t); execute format('grant select,insert,update,delete on public.%I to authenticated', t); end loop; end $$;
create policy cpriv_read on public.company_private for select using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role]) or is_staff());
create policy cacq_staff on public.company_acquisition for all using (is_staff()) with check (is_staff());
create policy claims_read on public.company_claims for select using (claimant_id = auth.uid() or is_staff());
create policy cev_read on public.company_claim_evidence for select using ((claim_claimant(claim_id)=auth.uid()) or is_staff());  -- GUESS predicate
create policy cout_read on public.company_outreach_events for select using (is_staff()); create policy cout_insert on public.company_outreach_events for insert with check (is_staff());  -- GUESS predicates
create policy enq_buyer_read on public.enquiries for select using (buyer_id = auth.uid());
create policy enq_company_read on public.enquiries for select using (company_id is not null and has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]));
create policy enq_leads_read on public.enquiries for select using (kind='requirement' and seller_can_see_leads() and lead_matches_my_company(category_id));
create policy enq_staff_read on public.enquiries for select using (is_staff());
create policy enq_staff_upd on public.enquiries for update using (is_staff()) with check (is_staff());
create policy epriv_read on public.enquiry_private for select using (enquiry_buyer(enquiry_id)=auth.uid() or is_staff());
create policy profiles_self_read on public.profiles for select using (id=auth.uid() or is_staff());
create policy members_read on public.company_members for select using (user_id=auth.uid() or is_staff());  -- GUESS
create policy cat_read on public.categories for select using (true); create policy cc_read on public.company_categories for select using (true); -- GUESS
create policy comp_read on public.companies for select using (directory_status='published' or is_staff() or is_company_member(id)); -- GUESS
create policy prod_read on public.products for select using (directory_status='published' or is_staff()); -- GUESS
create policy notif_read on public.notifications for select using (user_id=auth.uid()); -- GUESS
alter table storage.objects enable row level security; grant select,insert,update,delete on storage.objects to authenticated;
create policy vd_read on storage.objects for select to authenticated using (bucket_id='verification-docs' and (claim_claimant(public.safe_uuid((storage.foldername(name))[1]))=auth.uid() or is_staff()));
-- public view STAND-INS (GUESS bodies; real column lists captured). Real definitions are an open blocker.
create view public.public_companies with (security_invoker=false) as select id, slug, name, business_type, about, city, state, country, website, logo_path,
  case when verification_status='verified' then 'Verified business' when claim_status='approved' then 'Claimed business' else 'Unclaimed business' end as public_label,
  (claim_status='approved') as is_claimed, (verification_status='verified') as is_verified, updated_at as data_as_of, updated_at
  from public.companies where directory_status='published' and data_review_status='approved';
grant select on public.public_companies to anon, authenticated;
-- mirror real grants: catalog showed non-trigger functions executable by authenticated+service_role only (not PUBLIC/anon)
do $$ declare f record; begin for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' loop
  execute format('revoke all on function %s from public', f.sig); execute format('grant execute on function %s to authenticated, service_role', f.sig); end loop; end $$;

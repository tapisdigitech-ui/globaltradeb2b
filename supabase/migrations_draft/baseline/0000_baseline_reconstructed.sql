-- PROPOSED BASELINE (reconstructed from a read-only catalogue extract of globaltradeb2b-staging). DRAFT - NOT APPLIED ANYWHERE.
-- Purpose: give a Supabase branch a schema (staging has an EMPTY migration history). Separate from migrations 0001-0006.
-- Excluded: auth/storage platform objects, extension objects, roles, secrets, all row data (categories seed = 14 rows, names not captured),
-- PG17 MAINTAIN privilege. Run with search_path = public, extensions (the Supabase default) so gin_trgm_ops resolves.
begin;
set local search_path = public, extensions;

-- ===== types, sequences, tables =====
create type public.acquisition_status as enum ('not_contacted','contact_attempted','in_conversation','invited_to_claim','claim_started','declined','do_not_contact');
create type public.app_role as enum ('buyer','seller','reviewer','admin');
create type public.assoc_basis as enum ('manufacturer','brand_owner','distributor','reseller','marketplace_seller','unknown');
create type public.batch_status as enum ('staged','validated','applied','rolled_back');
create type public.claim_status as enum ('unclaimed','claim_submitted','evidence_requested','under_review','approved','rejected','withdrawn');
create type public.correction_status as enum ('new','accepted','rejected','applied');
create type public.directory_status as enum ('draft','pending_review','published','paused','rejected','suspended');
create type public.enquiry_delivery as enum ('stored','awaiting_admin','visible_to_seller','sent_external','failed');
create type public.enquiry_kind as enum ('product','requirement');
create type public.enquiry_status as enum ('new','read','replied','quoted','closed','spam');
create type public.followup_status as enum ('open','done','cancelled');
create type public.image_rights as enum ('unknown','owned','licensed','permission_granted','public_domain','rejected');
create type public.import_row_status as enum ('staged','invalid','duplicate_review','suppressed','approved','imported','rejected');
create type public.member_role as enum ('owner','manager','sales','catalogue_editor','viewer');
create type public.member_status as enum ('invited','active','removed');
create type public.notif_kind as enum ('system','tip','lead','enquiry','message','moderation','claim','admin');
create type public.order_status as enum ('placed','confirmed','in_production','shipped','delivered','cancelled');
create type public.outreach_delivery as enum ('logged_manual','queued','sent','failed');
create type public.outreach_type as enum ('call','email','message','invitation','follow_up','note');
create type public.promo_type as enum ('featured','top_search','category_banner');
create type public.quote_status as enum ('draft','sent','accepted','declined','expired','withdrawn');
create type public.review_status as enum ('pending','approved','rejected');
create type public.source_type as enum ('official_website','public_business_directory','trade_association','exhibitor_directory','government_registry','direct_submission','licensed_data_provider','other_approved');
create type public.verification_status as enum ('not_verified','pending','verified','rejected','expired');

create sequence public.audit_log_id_seq; create sequence public.categories_id_seq as integer; create sequence public.company_membership_audit_id_seq;
create sequence public.enquiry_contact_access_id_seq; create sequence public.product_view_events_id_seq; create sequence public.rate_events_id_seq;

create table public.audit_log (id bigint not null default nextval('audit_log_id_seq'::regclass), actor_id uuid, actor_role text, action text not null, entity text not null, entity_id text, old_value jsonb, new_value jsonb, at timestamp with time zone not null default now());
create table public.brochures (company_id uuid not null, path text not null, file_name text, size_bytes integer, is_public boolean not null default false, updated_at timestamp with time zone not null default now());
create table public.catalogue_selections (company_id uuid not null, product_ids uuid[] not null default '{}'::uuid[], updated_at timestamp with time zone not null default now());
create table public.categories (id integer not null default nextval('categories_id_seq'::regclass), slug text not null, name text not null, hue integer, spec_template jsonb not null default '[]'::jsonb, hidden boolean not null default false, "position" integer not null default 0);
create table public.cms_pages (slug text not null, title text not null, body text not null, published boolean not null default false, updated_at timestamp with time zone not null default now());
create table public.companies (id uuid not null default gen_random_uuid(), slug text not null, name text not null, business_type text, about text, city text, state text, country text default 'IN'::text, website text, logo_path text, directory_status directory_status not null default 'draft'::directory_status, claim_status claim_status not null default 'unclaimed'::claim_status, verification_status verification_status not null default 'not_verified'::verification_status, verified_at timestamp with time zone, verified_by uuid, data_review_status review_status not null default 'pending'::review_status, data_reviewed_by uuid, data_reviewed_at timestamp with time zone, dedupe_key text, import_batch_id uuid, created_by uuid, created_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now());
create table public.company_acquisition (company_id uuid not null, acquisition_status acquisition_status not null default 'not_contacted'::acquisition_status, last_contacted_at timestamp with time zone, next_follow_up_at timestamp with time zone, contact_channel text, contact_outcome text, owner_id uuid, updated_at timestamp with time zone not null default now());
create table public.company_categories (company_id uuid not null, category_id integer not null);
create table public.company_claim_evidence (id uuid not null default gen_random_uuid(), claim_id uuid not null, storage_path text not null, description text, uploaded_by uuid not null, created_at timestamp with time zone not null default now());
create table public.company_claims (id uuid not null default gen_random_uuid(), company_id uuid not null, claimant_id uuid not null, claimant_role_title text, statement text, status claim_status not null default 'claim_submitted'::claim_status, decided_by uuid, decided_at timestamp with time zone, decision_reason text, created_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now());
create table public.company_data_corrections (id uuid not null default gen_random_uuid(), company_id uuid not null, product_id uuid, field_name text not null, proposed_value text, evidence_url text, reporter_note text, reporter_id uuid not null, status correction_status not null default 'new'::correction_status, reviewed_by uuid, reviewed_at timestamp with time zone, review_note text, created_at timestamp with time zone not null default now());
create table public.company_follow_ups (id uuid not null default gen_random_uuid(), company_id uuid not null, due_at timestamp with time zone not null, owner_id uuid, status followup_status not null default 'open'::followup_status, outcome text, created_by uuid, created_at timestamp with time zone not null default now(), closed_at timestamp with time zone);
create table public.company_images (id uuid not null default gen_random_uuid(), company_id uuid not null, path text not null, "position" integer not null default 0, rights_status image_rights not null default 'unknown'::image_rights, source_url text, rights_evidence text, review_status review_status not null default 'pending'::review_status, created_at timestamp with time zone not null default now());
create table public.company_import_batches (id uuid not null default gen_random_uuid(), source_type source_type not null, source_name text not null, source_url text not null, terms_checked boolean not null default false, terms_note text, operator_id uuid not null, status batch_status not null default 'staged'::batch_status, counts jsonb not null default '{}'::jsonb, validation_report jsonb not null default '{}'::jsonb, created_at timestamp with time zone not null default now(), applied_at timestamp with time zone, rolled_back_at timestamp with time zone, rollback_ref text);
create table public.company_import_rows (id uuid not null default gen_random_uuid(), batch_id uuid not null, row_no integer not null, raw jsonb not null, name text, website text, city text, state text, about text, business_type text, normalized_name text, domain text, dedupe_key text, status import_row_status not null default 'staged'::import_row_status, match_company_id uuid, errors text[] not null default '{}'::text[]);
create table public.company_internal_notes (id uuid not null default gen_random_uuid(), company_id uuid not null, body text not null, author_id uuid not null, created_at timestamp with time zone not null default now());
create table public.company_members (id uuid not null default gen_random_uuid(), company_id uuid not null, user_id uuid, invite_email text, role member_role not null default 'viewer'::member_role, status member_status not null default 'invited'::member_status, invited_by uuid, expires_at timestamp with time zone, created_at timestamp with time zone not null default now());
create table public.company_membership_audit (id bigint not null default nextval('company_membership_audit_id_seq'::regclass), company_id uuid, member_user_id uuid, action text not null, old_role member_role, new_role member_role, old_status member_status, new_status member_status, actor_id uuid, at timestamp with time zone not null default now());
create table public.company_outreach_events (id uuid not null default gen_random_uuid(), company_id uuid not null, event_type outreach_type not null, channel text, summary text not null, outcome text, delivery outreach_delivery not null default 'logged_manual'::outreach_delivery, provider_ref text, occurred_at timestamp with time zone not null default now(), recorded_by uuid not null);
create table public.company_private (company_id uuid not null, phone text, email text, address text, pin text, contact_person text, updated_at timestamp with time zone not null default now());
create table public.company_sources (id uuid not null default gen_random_uuid(), company_id uuid not null, field_name text not null, source_type source_type not null, source_name text not null, source_url text not null, collected_at timestamp with time zone not null, last_checked_at timestamp with time zone, data_confidence smallint, recorded_by uuid, import_batch_id uuid, created_at timestamp with time zone not null default now());
create table public.company_verification_reviews (id uuid not null default gen_random_uuid(), company_id uuid not null, claim_id uuid, subject text not null, decision text not null, reason text not null, reviewer_id uuid not null, decided_at timestamp with time zone not null default now());
create table public.direct_messages (id uuid not null default gen_random_uuid(), thread_id uuid not null, sender_id uuid not null, body text not null, created_at timestamp with time zone not null default now());
create table public.direct_threads (id uuid not null default gen_random_uuid(), buyer_id uuid not null, company_id uuid not null, subject text, created_at timestamp with time zone not null default now());
create table public.enquiries (id uuid not null default gen_random_uuid(), ref text not null default ('ENQ-'::text || upper(substr(replace((gen_random_uuid())::text, '-'::text, ''::text), 1, 10))), kind enquiry_kind not null, buyer_id uuid not null, product_id uuid, company_id uuid, category_id integer, subject text not null, quantity numeric(14,2), unit text, message text, city text, status enquiry_status not null default 'new'::enquiry_status, delivery enquiry_delivery not null default 'stored'::enquiry_delivery, delivery_note text, created_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now());
create table public.enquiry_contact_access (id bigint not null default nextval('enquiry_contact_access_id_seq'::regclass), enquiry_id uuid not null, accessor_id uuid not null, company_id uuid, basis text not null, at timestamp with time zone not null default now());
create table public.enquiry_private (enquiry_id uuid not null, buyer_name text not null, buyer_phone text, buyer_email text, buyer_company text, consent_at timestamp with time zone not null, notice_version text not null);
create table public.enquiry_replies (id uuid not null default gen_random_uuid(), enquiry_id uuid not null, sender_id uuid not null, sender_side text not null, body text not null, created_at timestamp with time zone not null default now());
create table public.lead_responses (id uuid not null default gen_random_uuid(), enquiry_id uuid not null, company_id uuid not null, responded_by uuid not null, created_at timestamp with time zone not null default now());
create table public.media_assets (id uuid not null default gen_random_uuid(), scope text not null, key text not null, path text not null, source_note text not null, rights_status image_rights not null, added_by uuid, created_at timestamp with time zone not null default now());
create table public.moderation_actions (id uuid not null default gen_random_uuid(), target_type text not null, target_id text not null, action text not null, reason text, admin_id uuid not null, created_at timestamp with time zone not null default now());
create table public.notifications (id uuid not null default gen_random_uuid(), user_id uuid not null, company_id uuid, kind notif_kind not null, title text not null, body text, link text, read_at timestamp with time zone, created_at timestamp with time zone not null default now());
create table public.orders (id uuid not null default gen_random_uuid(), quotation_id uuid not null, buyer_id uuid not null, company_id uuid not null, total numeric(14,2) not null, currency character(3) not null, status order_status not null default 'placed'::order_status, created_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now());
create table public.product_group_items (group_id uuid not null, product_id uuid not null);
create table public.product_groups (id uuid not null default gen_random_uuid(), company_id uuid not null, name text not null, "position" integer not null default 0, created_at timestamp with time zone not null default now());
create table public.product_images (id uuid not null default gen_random_uuid(), product_id uuid not null, pending_path text not null, public_path text, "position" integer not null default 0, image_source_url text, rights_status image_rights not null default 'unknown'::image_rights, permission_evidence text, review_status review_status not null default 'pending'::review_status, reviewed_by uuid, reviewed_at timestamp with time zone, created_at timestamp with time zone not null default now());
create table public.product_view_events (id bigint not null default nextval('product_view_events_id_seq'::regclass), product_id uuid not null, company_id uuid not null, viewer_hash text not null, viewed_at timestamp with time zone not null default now());
create table public.products (id uuid not null default gen_random_uuid(), company_id uuid not null, category_id integer not null, name text not null, description text, price numeric(14,2), price_on_request boolean not null default false, unit text, moq numeric(12,2) default 1, specs jsonb not null default '[]'::jsonb, tags text, directory_status directory_status not null default 'draft'::directory_status, rejected_reason text, association_basis assoc_basis not null default 'unknown'::assoc_basis, source_url text, source_name text, collected_at timestamp with time zone, last_checked_at timestamp with time zone, data_review_status review_status not null default 'pending'::review_status, data_reviewed_by uuid, data_reviewed_at timestamp with time zone, created_by uuid, created_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now(), search tsvector generated always as (to_tsvector('simple'::regconfig, ((((COALESCE(name, ''::text) || ' '::text) || COALESCE(description, ''::text)) || ' '::text) || COALESCE(tags, ''::text)))) stored);  -- generated column (attrdef default rendered by catalog; assumed STORED)
create table public.profiles (id uuid not null, full_name text not null default ''::text, phone text, company_name text, city text, country text default 'IN'::text, preferred_location text, app_role app_role not null default 'buyer'::app_role, created_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now());
create table public.promotions (id uuid not null default gen_random_uuid(), company_id uuid not null, product_id uuid not null, type promo_type not null, days integer not null, starts_at timestamp with time zone not null default now(), paused boolean not null default false, created_by uuid);
create table public.quotations (id uuid not null default gen_random_uuid(), enquiry_id uuid not null, company_id uuid not null, amount numeric(14,2) not null, currency character(3) not null default 'INR'::bpchar, valid_until date, terms text, status quote_status not null default 'draft'::quote_status, created_by uuid, sent_at timestamp with time zone, responded_at timestamp with time zone, created_at timestamp with time zone not null default now());
create table public.rate_events (id bigint not null default nextval('rate_events_id_seq'::regclass), user_id uuid not null, action text not null, at timestamp with time zone not null default now());
create table public.seller_feedback (id uuid not null default gen_random_uuid(), user_id uuid, company_id uuid, body text not null, created_at timestamp with time zone not null default now());
create table public.seller_settings (user_id uuid not null, report_range integer not null default 30, lang text not null default 'English'::text, notify_enquiry boolean not null default true, notify_lead boolean not null default true, notify_tips boolean not null default true, email_digest boolean not null default false, compact boolean not null default false);
create table public.suppression_list (id uuid not null default gen_random_uuid(), domain text, normalized_name text, reason text not null, created_by uuid, created_at timestamp with time zone not null default now());
create table public.thread_reads (user_id uuid not null, enquiry_id uuid not null, read_at timestamp with time zone not null default now());

-- ===== functions =====
create or replace function public.block_mutation() returns trigger language plpgsql set search_path to '' as $function$
begin
  if TG_OP='DELETE' and pg_trigger_depth() > 1 then return old; end if;
  raise exception '% is immutable', TG_TABLE_NAME using errcode='42501';
end $function$;
create or replace function public.safe_uuid(t text) returns uuid language plpgsql immutable set search_path to '' as $function$
begin return t::uuid; exception when others then return null; end $function$;
create or replace function public.make_slug(t text) returns text language sql immutable set search_path to '' as $function$
  select left(coalesce(nullif(trim(both '-' from regexp_replace(lower(coalesce(t,'')),'[^a-z0-9]+','-','g')),''),'company'),60) $function$;
create or replace function public.norm_domain(t text) returns text language sql immutable set search_path to '' as $function$
  select nullif(lower(regexp_replace(regexp_replace(coalesce(t,''),'^https?://(www\.)?','','i'),'[/?#].*$','')),'') $function$;
create or replace function public.norm_name(t text) returns text language sql immutable set search_path to '' as $function$
  select nullif(trim(regexp_replace(lower(regexp_replace(coalesce(t,''),'\m(pvt|private|ltd|limited|llp|inc|co|company|corp|corporation)\M\.?','','gi')),'[^a-z0-9]+',' ','g')),'') $function$;
create or replace function public.set_updated_at() returns trigger language plpgsql set search_path to '' as $function$
begin new.updated_at = now(); return new; end $function$;
create or replace function public.is_trusted_session() returns boolean language sql stable set search_path to '' as $function$
  select current_user in ('postgres','service_role','supabase_admin') $function$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from profiles where id=auth.uid() and app_role='admin') $function$;
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from profiles where id=auth.uid() and app_role in ('admin','reviewer')) $function$;
create or replace function public.is_company_member(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from company_members m join companies c on c.id=m.company_id
    where m.company_id=cid and m.user_id=auth.uid() and m.status='active' and c.claim_status='approved') $function$;
create or replace function public.has_company_role(cid uuid, roles member_role[]) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from company_members m join companies c on c.id=m.company_id
    where m.company_id=cid and m.user_id=auth.uid() and m.status='active'
      and c.claim_status='approved' and m.role = any(roles)) $function$;
create or replace function public.claim_claimant(cid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select claimant_id from company_claims where id=cid and claimant_id=auth.uid() $function$;
create or replace function public.claim_company(cid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select company_id from company_claims where id=cid $function$;
create or replace function public.claim_is_open_for_me(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from company_claims where id=cid and claimant_id=auth.uid() and status in ('claim_submitted','evidence_requested','under_review')) $function$;
create or replace function public.company_is_claimed(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from companies c where c.id=cid and c.claim_status='approved') $function$;
create or replace function public.company_is_live(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from companies c where c.id=cid and c.directory_status='published') $function$;
create or replace function public.user_is_claimant(cid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from company_claims where company_id=cid and claimant_id=auth.uid() and status in ('claim_submitted','evidence_requested','under_review','approved')) $function$;
create or replace function public.enquiry_buyer(eid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select buyer_id from enquiries where id=eid and buyer_id=auth.uid() $function$;
create or replace function public.enquiry_company(eid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select company_id from enquiries where id=eid $function$;
create or replace function public.group_company(gid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select company_id from product_groups where id=gid $function$;
create or replace function public.product_company(pid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select company_id from products where id=pid $function$;
create or replace function public.thread_buyer(tid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select buyer_id from direct_threads where id=tid and buyer_id=auth.uid() $function$;
create or replace function public.thread_company(tid uuid) returns uuid language sql stable security definer set search_path to 'public','pg_temp' as $function$ select company_id from direct_threads where id=tid $function$;
create or replace function public.seller_can_see_leads() returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from company_members m join companies c on c.id=m.company_id
    where m.user_id=auth.uid() and m.status='active' and c.claim_status='approved' and c.directory_status='published'
      and m.role in ('owner','manager','sales')) $function$;
create or replace function public.lead_matches_my_company(cat integer) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from company_members m join companies c on c.id=m.company_id
    where m.user_id=auth.uid() and m.status='active' and c.claim_status='approved' and c.directory_status='published'
      and m.role in ('owner','manager','sales')
      and (cat is null or exists(select 1 from company_categories cc where cc.company_id=c.id and cc.category_id=cat))) $function$;
create or replace function public.check_rate(p_action text, p_max integer, p_window interval) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare uid uuid := auth.uid(); n int;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  select count(*) into n from rate_events where user_id=uid and action=p_action and at > now()-p_window;
  if n >= p_max then raise exception 'rate_limited: % (max % per %)', p_action, p_max, p_window using errcode='P0001'; end if;
  insert into rate_events(user_id,action) values (uid,p_action);
end $function$;
create or replace function public.rate_trigger() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin perform check_rate(TG_ARGV[0], TG_ARGV[1]::int, (TG_ARGV[2]||' minutes')::interval); return new; end $function$;
create or replace function public.audit_changes() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare col text; o jsonb; n jsonb; changed boolean := false; role_txt text;
begin
  if TG_OP='INSERT' then
    insert into audit_log(actor_id,actor_role,action,entity,entity_id,new_value)
      values (auth.uid(), current_user, 'insert', TG_TABLE_NAME, to_jsonb(new)->>coalesce(TG_ARGV[0],'id'), to_jsonb(new)); return new;
  end if;
  o := to_jsonb(old); n := to_jsonb(new);
  for i in 1..array_length(TG_ARGV,1)-1 loop
    col := TG_ARGV[i];
    if (o->col) is distinct from (n->col) then changed := true; end if;
  end loop;
  if changed then
    insert into audit_log(actor_id,actor_role,action,entity,entity_id,old_value,new_value)
    values (auth.uid(), current_user, 'status_change', TG_TABLE_NAME, o->>TG_ARGV[0],
            (select jsonb_object_agg(k,o->k) from unnest(TG_ARGV[2:]) k),
            (select jsonb_object_agg(k,n->k) from unnest(TG_ARGV[2:]) k));
  end if;
  return new;
end $function$;
create or replace function public.audit_membership() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  insert into company_membership_audit(company_id,member_user_id,action,old_role,new_role,old_status,new_status,actor_id)
  values (coalesce(new.company_id,old.company_id), coalesce(new.user_id,old.user_id), lower(TG_OP),
          case when TG_OP<>'INSERT' then old.role end, case when TG_OP<>'DELETE' then new.role end,
          case when TG_OP<>'INSERT' then old.status end, case when TG_OP<>'DELETE' then new.status end, auth.uid());
  return coalesce(new, old);
end $function$;
create or replace function public.company_publish_check() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  -- invariant: a published company ALWAYS has approved data review (checked on every write, not only on transition)
  if new.directory_status='published' then
    if new.data_review_status <> 'approved' then raise exception 'cannot publish: data review not approved'; end if;
    if (TG_OP='INSERT' or old.directory_status is distinct from 'published')
       and not exists(select 1 from company_sources s where s.company_id=new.id) then
      raise exception 'cannot publish: no source provenance recorded'; end if;
  end if;
  return new;
end $function$;
create or replace function public.guard_company_columns() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if not is_trusted_session() and (
        new.directory_status is distinct from old.directory_status or new.claim_status is distinct from old.claim_status
     or new.verification_status is distinct from old.verification_status or new.verified_at is distinct from old.verified_at
     or new.verified_by is distinct from old.verified_by or new.data_review_status is distinct from old.data_review_status
     or new.data_reviewed_by is distinct from old.data_reviewed_by or new.slug is distinct from old.slug
     or new.dedupe_key is distinct from old.dedupe_key or new.import_batch_id is distinct from old.import_batch_id
     or new.created_by is distinct from old.created_by) then
    raise exception 'protected company column: use the review RPCs' using errcode='42501';
  end if;
  return new;
end $function$;
create or replace function public.guard_company_image() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if not is_trusted_session() and not is_staff() then
    if TG_OP='INSERT' then new.review_status := 'pending';
    elsif new.review_status is distinct from old.review_status then raise exception 'protected image column' using errcode='42501';
    elsif new.path is distinct from old.path or new.rights_status is distinct from old.rights_status then new.review_status := 'pending'; end if;
  end if;
  return new;
end $function$;
create or replace function public.guard_direct_thread() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if not is_trusted_session() then
    if new.buyer_id <> auth.uid() then raise exception 'not your thread' using errcode='42501'; end if;
    if not (company_is_live(new.company_id) and company_is_claimed(new.company_id)) then
      raise exception 'company cannot receive direct messages' using errcode='42501'; end if;
  end if;
  return new;
end $function$;
create or replace function public.guard_enquiry() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if not is_trusted_session() and (
        new.delivery is distinct from old.delivery or new.delivery_note is distinct from old.delivery_note
     or new.buyer_id is distinct from old.buyer_id or new.company_id is distinct from old.company_id
     or new.product_id is distinct from old.product_id or new.category_id is distinct from old.category_id
     or new.kind is distinct from old.kind or new.subject is distinct from old.subject or new.message is distinct from old.message
     or new.quantity is distinct from old.quantity or new.unit is distinct from old.unit or new.city is distinct from old.city
     or new.ref is distinct from old.ref) then
    raise exception 'only status may be changed' using errcode='42501';
  end if;
  return new;
end $function$;
create or replace function public.guard_member() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if is_trusted_session() then
    if TG_OP='DELETE' then return old; end if;
    return new;
  end if;
  if TG_OP='INSERT' then
    if new.status <> 'invited' or new.user_id is not null or new.invite_email is null or new.role = 'owner' then
      raise exception 'members can only be invited (non-owner role, by email); acceptance activates them' using errcode='42501'; end if;
    new.invite_email := lower(trim(new.invite_email));
    if new.invite_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid invitation email'; end if;
    new.invited_by := auth.uid(); new.expires_at := now() + interval '14 days';
    return new;
  elsif TG_OP='UPDATE' then
    if new.user_id is distinct from old.user_id or new.company_id is distinct from old.company_id
       or new.invite_email is distinct from old.invite_email or new.invited_by is distinct from old.invited_by
       or new.expires_at is distinct from old.expires_at then
      raise exception 'protected membership column' using errcode='42501'; end if;
    if old.role = 'owner' or new.role = 'owner' then raise exception 'owner role is managed by staff' using errcode='42501'; end if;
    if new.status is distinct from old.status and not (new.status = 'removed' and old.status in ('invited','active')) then
      raise exception 'illegal membership status change (activation happens only by accepting an invitation)' using errcode='42501'; end if;
    return new;
  else
    if old.role = 'owner' then raise exception 'owner membership is managed by staff' using errcode='42501'; end if;
    return old;
  end if;
end $function$;
create or replace function public.guard_product() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if not is_trusted_session() then
    if TG_OP='INSERT' then
      if new.directory_status not in ('draft','pending_review') or new.data_review_status<>'pending'
         or new.source_url is not null or new.collected_at is not null then
        raise exception 'sellers cannot set review, publication or provenance fields' using errcode='42501'; end if;
      new.created_by := auth.uid();
    else
      if new.data_review_status is distinct from old.data_review_status or new.data_reviewed_by is distinct from old.data_reviewed_by
         or new.data_reviewed_at is distinct from old.data_reviewed_at or new.rejected_reason is distinct from old.rejected_reason
         or new.source_url is distinct from old.source_url or new.source_name is distinct from old.source_name
         or new.collected_at is distinct from old.collected_at or new.last_checked_at is distinct from old.last_checked_at
         or new.company_id is distinct from old.company_id or new.created_by is distinct from old.created_by then
        raise exception 'protected product column' using errcode='42501'; end if;
      if new.directory_status is distinct from old.directory_status
         and not (new.directory_status in ('draft','pending_review','paused') and old.directory_status not in ('rejected','suspended'))
         and not (old.directory_status='paused' and new.directory_status='published') then
        raise exception 'illegal status change for seller' using errcode='42501'; end if;
      if old.directory_status='published' and new.directory_status='published'
         and (new.name is distinct from old.name or new.description is distinct from old.description or new.price is distinct from old.price
              or new.specs is distinct from old.specs or new.category_id is distinct from old.category_id) then
        new.directory_status := 'pending_review'; new.data_review_status := 'pending';
      end if;
    end if;
  end if;
  return new;
end $function$;
create or replace function public.guard_product_image() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if not is_trusted_session() then
    if TG_OP='INSERT' then
      if new.review_status<>'pending' or new.public_path is not null then raise exception 'protected image column' using errcode='42501'; end if;
    elsif new.review_status is distinct from old.review_status or new.public_path is distinct from old.public_path
       or new.reviewed_by is distinct from old.reviewed_by or new.pending_path is distinct from old.pending_path then
      raise exception 'protected image column' using errcode='42501';
    elsif new.rights_status is distinct from old.rights_status or new.image_source_url is distinct from old.image_source_url
       or new.permission_evidence is distinct from old.permission_evidence then
      new.review_status := 'pending'; new.public_path := null;   -- any rights edit sends it back to review
    end if;
  end if;
  return new;
end $function$;
create or replace function public.guard_profile_role() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if new.app_role is distinct from old.app_role and not is_trusted_session() then
    raise exception 'app_role is not user-editable' using errcode='42501'; end if;
  return new;
end $function$;
create or replace function public.guard_quote() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if TG_OP='INSERT' then
    if not is_trusted_session() then
      if new.status<>'draft' then raise exception 'quotes start as draft' using errcode='42501'; end if;
      new.created_by := auth.uid();
      if not exists(select 1 from enquiries e where e.id=new.enquiry_id and
           (e.company_id = new.company_id or exists(select 1 from lead_responses lr where lr.enquiry_id=e.id and lr.company_id=new.company_id))) then
        raise exception 'quotation company does not match enquiry' using errcode='42501'; end if;
    end if;
  elsif not is_trusted_session() then
    if old.status not in ('draft','sent') then raise exception 'quotation is closed' using errcode='42501'; end if;
    if new.status not in ('draft','sent','withdrawn') then raise exception 'sellers cannot accept or decline quotations' using errcode='42501'; end if;
    if new.enquiry_id is distinct from old.enquiry_id or new.company_id is distinct from old.company_id then raise exception 'immutable link' using errcode='42501'; end if;
    if new.status='sent' and old.status='draft' then new.sent_at := now(); end if;
  end if;
  return new;
end $function$;
create or replace function public.guard_reply() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  if exists(select 1 from enquiries where id=new.enquiry_id and status='spam') then
    raise exception 'thread closed' using errcode='42501'; end if;
  return new;     -- who may post is decided by policy replies_ins (seller_can_reply / buyer ownership)
end $function$;
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  insert into profiles(id, full_name) values (new.id, left(coalesce(new.raw_user_meta_data->>'full_name',''),120));
  return new;   -- role is ALWAYS buyer here
end $function$;
create or replace function public.outreach_touch() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  if new.event_type not in ('note','follow_up') then
    insert into company_acquisition(company_id,last_contacted_at,contact_channel,contact_outcome)
    values (new.company_id,new.occurred_at,new.channel,new.outcome)
    on conflict (company_id) do update set last_contacted_at=excluded.last_contacted_at,
      contact_channel=coalesce(excluded.contact_channel,company_acquisition.contact_channel),
      contact_outcome=coalesce(excluded.contact_outcome,company_acquisition.contact_outcome), updated_at=now();
  end if;
  return new;
end $function$;
create or replace function public.product_publish_check() returns trigger language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if new.directory_status='published' then
    if new.data_review_status <> 'approved' then raise exception 'cannot publish: data review not approved'; end if;
    if (TG_OP='INSERT' or old.directory_status is distinct from 'published')
       and not (company_is_claimed(new.company_id) or (new.source_url is not null and new.association_basis <> 'unknown')) then
      raise exception 'cannot publish: product-company association needs evidence (source_url and basis)'; end if;
  end if;
  return new;
end $function$;
create or replace function public.suppression_apply() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  update companies set directory_status='suspended'
   where directory_status <> 'suspended'
     and ((new.domain is not null and norm_domain(website)=new.domain) or (new.normalized_name is not null and norm_name(name)=new.normalized_name));
  return new;
end $function$;
create or replace function public.notify_on_enquiry() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  if new.delivery='visible_to_seller' then
    insert into notifications(user_id,company_id,kind,title,body,link)
      select m.user_id,new.company_id,'enquiry','New enquiry: '||left(new.subject,80),'Open Messages to view and reply.','msgs'
      from company_members m left join seller_settings s on s.user_id=m.user_id
      where m.company_id=new.company_id and m.status='active' and m.role in ('owner','manager','sales') and coalesce(s.notify_enquiry,true);
  elsif new.delivery='awaiting_admin' then
    insert into notifications(user_id,company_id,kind,title,body,link)
      select p.id,new.company_id,'admin','Enquiry for unclaimed company','Reference '||new.ref||'. Hold and follow up.','admin/enquiries'
      from profiles p where p.app_role in ('admin','reviewer');
  elsif new.kind='requirement' then
    insert into notifications(user_id,company_id,kind,title,body,link)
      select distinct m.user_id,m.company_id,'lead'::notif_kind,'New buy lead: '||left(new.subject,80),'Open Buy Leads to review it.','leads'
      from company_members m join companies c on c.id=m.company_id left join seller_settings s on s.user_id=m.user_id
      where m.status='active' and c.claim_status='approved' and c.directory_status='published' and m.role in ('owner','manager','sales')
        and (new.category_id is null or exists(select 1 from company_categories cc where cc.company_id=c.id and cc.category_id=new.category_id))
        and coalesce(s.notify_lead,true);
  end if;
  return new;
end $function$;
create or replace function public.respond_to_lead(p_enquiry uuid, p_company uuid) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare e enquiries;
begin
  select * into e from enquiries where id=p_enquiry and kind='requirement';
  if not found then raise exception 'lead not found'; end if;
  if not has_company_role(p_company, array['owner','manager','sales']::member_role[]) or not company_is_live(p_company) then
    raise exception 'not authorised' using errcode='42501'; end if;
  if e.category_id is not null and not exists(select 1 from company_categories where company_id=p_company and category_id=e.category_id) then
    raise exception 'lead is outside your categories' using errcode='42501'; end if;
  perform check_rate('lead_response',30,interval '1 day');
  insert into lead_responses(enquiry_id,company_id,responded_by) values (p_enquiry,p_company,auth.uid()) on conflict do nothing;
end $function$;
create or replace function public.reveal_buyer_contact(p_enquiry uuid, p_company uuid) returns table(buyer_name text, buyer_phone text, buyer_email text, buyer_company text) language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare e enquiries; basis text;
begin
  select * into e from enquiries where id=p_enquiry;
  if not found then raise exception 'not found'; end if;
  if not has_company_role(p_company, array['owner','manager','sales']::member_role[]) then raise exception 'not authorised' using errcode='42501'; end if;
  if e.kind='product' then
    if e.company_id is distinct from p_company then raise exception 'not authorised' using errcode='42501'; end if;
    basis := 'product_enquiry';
  else
    if not exists(select 1 from lead_responses where enquiry_id=p_enquiry and company_id=p_company) then raise exception 'respond to the lead first' using errcode='42501'; end if;
    basis := 'lead_response';
  end if;
  perform check_rate('reveal',100,interval '1 day');
  insert into enquiry_contact_access(enquiry_id,accessor_id,company_id,basis) values (p_enquiry,auth.uid(),p_company,basis);
  return query select ep.buyer_name, ep.buyer_phone, ep.buyer_email, ep.buyer_company from enquiry_private ep where ep.enquiry_id=p_enquiry;
end $function$;
create or replace function public.seller_can_reply(eid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $function$
  select exists(select 1 from enquiries e where e.id=eid and (
      (e.kind='product' and has_company_role(e.company_id, array['owner','manager','sales']::member_role[]))
   or (e.kind='requirement' and exists(select 1 from lead_responses lr where lr.enquiry_id=e.id
        and has_company_role(lr.company_id, array['owner','manager','sales']::member_role[]))))) $function$;
create or replace function public.review_claim(p_claim uuid, p_decision claim_status, p_reason text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare cl company_claims; c companies;
begin
  if not is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  if p_decision not in ('under_review','evidence_requested','approved','rejected') then raise exception 'invalid decision'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'reason required'; end if;
  select * into cl from company_claims where id=p_claim for update;
  if not found then raise exception 'claim not found'; end if;
  if cl.status not in ('claim_submitted','evidence_requested','under_review') then raise exception 'claim already closed'; end if;
  select * into c from companies where id=cl.company_id for update;
  if p_decision='approved' then
    if c.claim_status='approved' then raise exception 'company already has an approved owner'; end if;
    if not exists(select 1 from company_claim_evidence where claim_id=p_claim) then raise exception 'cannot approve: no evidence on file'; end if;
    update company_claims set status='approved', decided_by=auth.uid(), decided_at=now(), decision_reason=p_reason where id=p_claim;
    update companies set claim_status='approved' where id=cl.company_id;
    insert into company_members(company_id,user_id,role,status,invited_by) values (cl.company_id,cl.claimant_id,'owner','active',auth.uid())
      on conflict (company_id,user_id) do update set role='owner', status='active';
    update profiles set app_role='seller' where id=cl.claimant_id and app_role='buyer';
    update company_claims set status='rejected', decided_by=auth.uid(), decided_at=now(), decision_reason='Superseded: another claim was approved'
      where company_id=cl.company_id and id<>p_claim and status in ('claim_submitted','evidence_requested','under_review');
  else
    update company_claims set status=p_decision, decided_by=case when p_decision='rejected' then auth.uid() end,
           decided_at=case when p_decision='rejected' then now() end, decision_reason=p_reason where id=p_claim;
    if c.claim_status <> 'approved' then update companies set claim_status=p_decision where id=cl.company_id; end if;
  end if;
  insert into company_verification_reviews(company_id,claim_id,subject,decision,reason,reviewer_id)
    values (cl.company_id,p_claim,'claim',p_decision::text,p_reason,auth.uid());
  insert into notifications(user_id,company_id,kind,title,body,link)
    values (cl.claimant_id,cl.company_id,'claim','Claim update: '||p_decision::text,left(p_reason,300),'account/claims');
end $function$;
create or replace function public.set_verification(p_company uuid, p_status verification_status, p_reason text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare c companies;
begin
  if not is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'reason required'; end if;
  select * into c from companies where id=p_company for update;
  if not found then raise exception 'company not found'; end if;
  if p_status in ('pending','verified') and c.claim_status<>'approved' then raise exception 'ownership must be approved first'; end if;
  update companies set verification_status=p_status,
    verified_at=case when p_status='verified' then now() end, verified_by=case when p_status='verified' then auth.uid() end
   where id=p_company;
  insert into company_verification_reviews(company_id,subject,decision,reason,reviewer_id) values (p_company,'verification',p_status::text,p_reason,auth.uid());
end $function$;
create or replace function public.staff_mark_enquiry(p_enquiry uuid, p_delivery enquiry_delivery, p_note text, p_provider_ref text DEFAULT NULL::text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $function$
begin
  if not is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  if p_delivery='sent_external' and coalesce(trim(p_provider_ref),'')='' then raise exception 'sent_external requires a provider reference'; end if;
  update enquiries set delivery=p_delivery, delivery_note=left(coalesce(p_note,'')||case when p_provider_ref is not null then ' [ref '||p_provider_ref||']' else '' end,500) where id=p_enquiry;
  if not found then raise exception 'enquiry not found'; end if;
end $function$;
create or replace function public.submit_claim(p_company uuid, p_title text, p_statement text) returns uuid language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare uid uuid := auth.uid(); c record; cl uuid;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  select * into c from companies where id=p_company and directory_status='published';
  if not found then raise exception 'company not available for claiming'; end if;
  if c.claim_status='approved' then raise exception 'company already has an approved owner'; end if;
  perform check_rate('claim',3,interval '1 day');
  insert into company_claims(company_id,claimant_id,claimant_role_title,statement)
    values (p_company,uid,left(p_title,100),left(p_statement,2000)) returning id into cl;   -- unique index blocks duplicates
  if c.claim_status in ('unclaimed','rejected','withdrawn') then
    update companies set claim_status='claim_submitted' where id=p_company; end if;
  insert into notifications(user_id,company_id,kind,title,body,link)
    select pr.id,p_company,'admin','New claim submitted','A claim needs review.','admin/claims' from profiles pr where pr.app_role in ('admin','reviewer');
  return cl;
end $function$;
create or replace function public.submit_enquiry(p_kind enquiry_kind, p_product uuid, p_company uuid, p_category integer, p_subject text, p_quantity numeric, p_unit text, p_message text, p_city text, p_buyer_name text, p_phone text, p_email text, p_buyer_company text, p_consent boolean, p_notice_version text) returns table(enquiry_ref text, delivery enquiry_delivery, notice text) language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare uid uuid := auth.uid(); cid uuid; cat int; d enquiry_delivery; eid uuid; r text; n text;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if not coalesce(p_consent,false) then raise exception 'consent required'; end if;
  if coalesce(trim(p_buyer_name),'')='' then raise exception 'name required'; end if;
  if nullif(trim(p_phone),'') is null and nullif(trim(p_email),'') is null then raise exception 'phone or email required'; end if;
  perform check_rate('enquiry',10,interval '1 hour'); perform check_rate('enquiry_day',30,interval '1 day');
  if p_kind='product' then
    if p_product is not null then
      select p.company_id, p.category_id into cid, cat from products p join companies c on c.id=p.company_id
       where p.id=p_product and p.directory_status='published' and p.data_review_status='approved' and c.directory_status='published';
      if cid is null then raise exception 'product not available'; end if;
      if p_company is not null and p_company<>cid then raise exception 'company does not match product'; end if;
    else
      select id into cid from companies where id=p_company and directory_status='published';
      if cid is null then raise exception 'company not available'; end if;
    end if;
    if exists(select 1 from company_members m where m.company_id=cid and m.status='active' and m.role in ('owner','manager','sales'))
       and company_is_claimed(cid) then
      d := 'visible_to_seller';
      n := 'Your enquiry '||'%REF%'||' has been recorded and is visible to the supplier in their GlobalTradeB2B seller account. We cannot confirm they have read it.';
    else
      d := 'awaiting_admin';
      n := 'Your enquiry '||'%REF%'||' has been recorded. This company has not joined GlobalTradeB2B, so your enquiry has NOT been sent to them. Our team holds it and may contact the company.';
    end if;
  else
    if p_category is null or not exists(select 1 from categories where id=p_category and not hidden) then raise exception 'valid category required'; end if;
    cat := p_category; cid := null; d := 'stored';
    n := 'Your requirement '||'%REF%'||' is posted to the requirements board. Registered suppliers in this category can see it. No supplier has been contacted yet.';
  end if;
  insert into enquiries(kind,buyer_id,product_id,company_id,category_id,subject,quantity,unit,message,city,delivery)
    values (p_kind,uid,p_product,cid,cat,left(trim(p_subject),200),p_quantity,left(p_unit,30),left(p_message,2000),left(p_city,80),d)
    returning id, ref into eid, r;
  insert into enquiry_private(enquiry_id,buyer_name,buyer_phone,buyer_email,buyer_company,consent_at,notice_version)
    values (eid,left(trim(p_buyer_name),120),left(nullif(trim(p_phone),''),30),left(nullif(trim(p_email),''),160),left(p_buyer_company,160),now(),coalesce(p_notice_version,'v1'));
  return query select r, d, replace(n,'%REF%',r);
end $function$;
create or replace function public.withdraw_claim(p_claim uuid) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare cl company_claims;
begin
  select * into cl from company_claims where id=p_claim and claimant_id=auth.uid() and status in ('claim_submitted','evidence_requested','under_review');
  if not found then raise exception 'no such active claim'; end if;
  update company_claims set status='withdrawn' where id=p_claim;
  if not exists(select 1 from company_claims where company_id=cl.company_id and status in ('claim_submitted','evidence_requested','under_review'))
     and exists(select 1 from companies where id=cl.company_id and claim_status<>'approved') then
    update companies set claim_status='withdrawn' where id=cl.company_id; end if;
end $function$;
CREATE OR REPLACE FUNCTION public.accept_invitation(p_member uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare uid uuid := auth.uid(); em text; m company_members;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  select lower(email) into em from auth.users where id=uid and email_confirmed_at is not null;
  if em is null then raise exception 'confirmed email required'; end if;
  perform check_rate('accept_invite',10,interval '1 day');
  select * into m from company_members where id=p_member and status='invited' and user_id is null for update;
  -- same message for "no such invite" and "invite for someone else": no enumeration
  if not found or lower(m.invite_email) <> em then raise exception 'invitation not found'; end if;
  if m.expires_at < now() then raise exception 'invitation expired'; end if;
  if not company_is_claimed(m.company_id) then raise exception 'company workspace is not active'; end if;
  if exists(select 1 from company_members where company_id=m.company_id and user_id=uid) then raise exception 'already a member'; end if;
  update company_members set user_id=uid, status='active' where id=p_member;
  update profiles set app_role='seller' where id=uid and app_role='buyer';
end $function$;
CREATE OR REPLACE FUNCTION public.advance_order(p_order uuid, p_status order_status)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o orders;
begin
  select * into o from orders where id=p_order for update;
  if not found then raise exception 'order not found'; end if;
  if not has_company_role(o.company_id, array['owner','manager','sales']::member_role[]) then raise exception 'not authorised' using errcode='42501'; end if;
  if not ((o.status='placed' and p_status in ('confirmed','cancelled')) or (o.status='confirmed' and p_status in ('in_production','cancelled'))
       or (o.status='in_production' and p_status='shipped') or (o.status='shipped' and p_status='delivered')) then
    raise exception 'illegal transition % -> %', o.status, p_status; end if;
  update orders set status=p_status, updated_at=now() where id=p_order;
end $function$;
create or replace function public.approve_product_image(p_image uuid, p_public_path text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $f$
declare im product_images;
begin
  if not is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  select * into im from product_images where id=p_image for update;
  if not found then raise exception 'image not found'; end if;
  if im.rights_status not in ('owned','licensed','permission_granted','public_domain') then raise exception 'image rights not cleared'; end if;
  update product_images set review_status='approved', public_path=p_public_path, reviewed_by=auth.uid(), reviewed_at=now() where id=p_image;
end $f$;
CREATE OR REPLACE FUNCTION public.cancel_order(p_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare o orders;
begin
  select * into o from orders where id=p_order and buyer_id=auth.uid() for update;
  if not found then raise exception 'order not found'; end if;
  if o.status <> 'placed' then raise exception 'only placed orders can be cancelled by the buyer'; end if;
  update orders set status='cancelled', updated_at=now() where id=p_order;
end $function$;
CREATE OR REPLACE FUNCTION public.create_company_request(p_name text, p_type text, p_city text, p_statement text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare uid uuid := auth.uid(); cid uuid;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'name required'; end if;
  perform check_rate('company_request',3,interval '1 day');
  insert into companies(slug,name,business_type,city,created_by,claim_status)
    values (make_slug(p_name)||'-'||substr(gen_random_uuid()::text,1,6), left(trim(p_name),160), left(p_type,80), left(p_city,80), uid, 'claim_submitted')
    returning id into cid;
  insert into company_sources(company_id,field_name,source_type,source_name,source_url,collected_at,recorded_by)
    values (cid,'name','direct_submission','Direct submission','direct-submission:'||uid::text,now(),uid);
  insert into company_claims(company_id,claimant_id,statement,claimant_role_title) values (cid,uid,left(p_statement,2000),'Creator');
  return cid;
end $function$;
CREATE OR REPLACE FUNCTION public.create_order(p_quote uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q quotations; e enquiries; oid uuid;
begin
  select * into q from quotations where id=p_quote;
  if not found then raise exception 'quotation not found'; end if;
  select * into e from enquiries where id=q.enquiry_id;
  if e.buyer_id <> auth.uid() then raise exception 'not your quotation' using errcode='42501'; end if;
  if q.status <> 'accepted' then raise exception 'quotation must be accepted first'; end if;
  if not company_is_claimed(q.company_id) then raise exception 'supplier not active'; end if;
  perform check_rate('order',20,interval '1 day');
  insert into orders(quotation_id,buyer_id,company_id,total,currency) values (q.id,auth.uid(),q.company_id,q.amount,q.currency) returning id into oid;
  return oid;
end $function$;
CREATE OR REPLACE FUNCTION public.decline_invitation(p_member uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare em text;
begin
  select lower(email) into em from auth.users where id=auth.uid() and email_confirmed_at is not null;
  update company_members set status='removed' where id=p_member and status='invited' and user_id is null and lower(invite_email)=em;
  if not found then raise exception 'invitation not found'; end if;
end $function$;
CREATE OR REPLACE FUNCTION public.import_apply(p_batch uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare b company_import_batches; r record; cid uuid; ins int := 0; skipped int := 0;
begin
  if not is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  select * into b from company_import_batches where id=p_batch for update;
  if not found then raise exception 'batch not found'; end if;
  if not b.terms_checked then raise exception 'source terms have not been confirmed for this batch'; end if;
  if b.status not in ('validated','applied') then raise exception 'batch must be validated first'; end if;
  for r in select * from company_import_rows where batch_id=p_batch and status='approved' order by row_no loop
    cid := null;
    insert into companies(slug,name,business_type,about,city,state,website,dedupe_key,import_batch_id,created_by)
      values (make_slug(r.name)||'-'||substr(gen_random_uuid()::text,1,6), left(r.name,160), r.business_type, r.about, r.city, r.state, r.website, r.dedupe_key, p_batch, auth.uid())
      on conflict (dedupe_key) where dedupe_key is not null do nothing returning id into cid;
    if cid is null then
      update company_import_rows set status='duplicate_review', match_company_id=(select id from companies where dedupe_key=r.dedupe_key) where id=r.id; skipped := skipped+1;
    else
      insert into company_sources(company_id,field_name,source_type,source_name,source_url,collected_at,data_confidence,recorded_by,import_batch_id)
        select cid,f,b.source_type,b.source_name,b.source_url,now(),3,auth.uid(),p_batch
        from unnest(array['name'] || case when r.website is not null then array['website'] else '{}' end
                    || case when r.city is not null then array['city'] else '{}' end
                    || case when r.about is not null then array['about'] else '{}' end) f;
      update company_import_rows set status='imported', match_company_id=cid where id=r.id; ins := ins+1;
    end if;
  end loop;
  update company_import_batches set status='applied', applied_at=now(),
    counts = counts || jsonb_build_object('last_apply_inserted',ins,'last_apply_skipped',skipped) where id=p_batch;
  return jsonb_build_object('inserted',ins,'skipped_duplicates',skipped);
end $function$;
create or replace function public.import_normalize(p_batch uuid) returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $f$
declare r record; errs text[]; m uuid; supp boolean; k text; cnt jsonb;
begin
  if not is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  for r in select * from company_import_rows where batch_id=p_batch and status in ('staged','invalid','duplicate_review','suppressed') order by row_no loop
    errs := '{}';
    if coalesce(trim(r.name),'')='' then errs := array_append(errs,'name missing'); end if;
    if r.website is not null and r.website !~* '^https?://[^ ]+\.[^ ]+$' then errs := array_append(errs,'website not a valid http(s) URL'); end if;
    k := case when norm_domain(r.website) is not null then 'd:'||norm_domain(r.website)
              else 'n:'||coalesce(norm_name(r.name),'')||'|'||lower(coalesce(trim(r.city),'')) end;
    select exists(select 1 from suppression_list s where (s.domain is not null and s.domain=norm_domain(r.website))
                  or (s.normalized_name is not null and s.normalized_name=norm_name(r.name))) into supp;
    select c.id into m from companies c
     where c.dedupe_key = k or (norm_domain(r.website) is not null and norm_domain(c.website)=norm_domain(r.website))
        or (norm_name(c.name)=norm_name(r.name) and lower(coalesce(c.city,''))=lower(coalesce(r.city,''))) limit 1;
    if m is null and exists(select 1 from company_import_rows o where o.batch_id=p_batch and o.dedupe_key=k and o.row_no<r.row_no) then
      errs := array_append(errs,'duplicate of an earlier row in this batch'); end if;
    update company_import_rows set normalized_name=norm_name(r.name), domain=norm_domain(r.website), dedupe_key=k, match_company_id=m,
      errors=errs, status=case when supp then 'suppressed' when cardinality(errs)>0 and errs<>array['duplicate of an earlier row in this batch'] then 'invalid'
                               when m is not null or cardinality(errs)>0 then 'duplicate_review' else 'staged' end::import_row_status
     where id=r.id;
  end loop;
  select jsonb_object_agg(status, n) into cnt from (select status, count(*) n from company_import_rows where batch_id=p_batch group by status) s;
  update company_import_batches set status='validated', counts=coalesce(cnt,'{}'), validation_report=jsonb_build_object('validated_at',now(),'by',auth.uid()) where id=p_batch;
  return cnt;
end $f$;
CREATE OR REPLACE FUNCTION public.import_rollback(p_batch uuid, p_ref text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if not is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  if exists(select 1 from companies c where c.import_batch_id=p_batch and (
        exists(select 1 from enquiries e where e.company_id=c.id) or exists(select 1 from company_claims cc where cc.company_id=c.id)
     or exists(select 1 from company_members m where m.company_id=c.id) or c.directory_status='published')) then
    raise exception 'cannot roll back: batch companies are published or have enquiries/claims/members';
  end if;
  delete from companies where import_batch_id=p_batch; get diagnostics n = row_count;
  update company_import_rows set status='approved', match_company_id=null where batch_id=p_batch and status='imported';
  update company_import_batches set status='rolled_back', rolled_back_at=now(), rollback_ref=p_ref where id=p_batch;
  return n;
end $function$;
CREATE OR REPLACE FUNCTION public.my_invitations()
 RETURNS TABLE(member_id uuid, company_id uuid, company_name text, role member_role, expires_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select m.id, m.company_id, c.name, m.role, m.expires_at
  from company_members m join companies c on c.id=m.company_id
  where m.status='invited' and m.user_id is null and m.expires_at > now() and c.claim_status='approved'
    and lower(m.invite_email) = (select lower(u.email) from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null) $function$;
CREATE OR REPLACE FUNCTION public.record_product_view(p_product uuid, p_viewer_hash text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cid uuid;
begin
  select p.company_id into cid from products p join companies c on c.id=p.company_id
   where p.id=p_product and p.directory_status='published' and c.directory_status='published';
  if cid is null or p_viewer_hash is null or length(p_viewer_hash) not between 16 and 128 then return; end if;
  if exists(select 1 from product_view_events where product_id=p_product and viewer_hash=p_viewer_hash and viewed_at > now()-interval '1 hour') then return; end if;
  insert into product_view_events(product_id,company_id,viewer_hash) values (p_product,cid,p_viewer_hash);
end $function$;
CREATE OR REPLACE FUNCTION public.report_correction(p_company uuid, p_product uuid, p_field text, p_value text, p_url text, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='28000'; end if;
  if not company_is_live(p_company) then raise exception 'company not available'; end if;
  perform check_rate('correction',10,interval '1 day');
  insert into company_data_corrections(company_id,product_id,field_name,proposed_value,evidence_url,reporter_note,reporter_id)
    values (p_company,p_product,left(p_field,60),left(p_value,1000),left(p_url,500),left(p_note,1000),auth.uid()) returning company_data_corrections.id into id;
  return id;
end $function$;
CREATE OR REPLACE FUNCTION public.respond_quotation(p_quote uuid, p_accept boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q quotations; e enquiries;
begin
  select * into q from quotations where id=p_quote for update;
  if not found then raise exception 'quotation not found'; end if;
  select * into e from enquiries where id=q.enquiry_id;
  if e.buyer_id <> auth.uid() then raise exception 'not your quotation' using errcode='42501'; end if;
  if q.status <> 'sent' then raise exception 'quotation is not open'; end if;
  if q.valid_until is not null and q.valid_until < current_date then
    update quotations set status='expired', responded_at=now() where id=p_quote; raise exception 'quotation expired'; end if;
  update quotations set status=case when p_accept then 'accepted' else 'declined' end::quote_status, responded_at=now() where id=p_quote;
end $function$;
create or replace function public.set_data_review(p_target text, p_id uuid, p_status review_status, p_note text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $f$
begin
  if not is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  -- a review that is not 'approved' ALWAYS withdraws publication in the same statement
  if p_target='company' then
    update companies set data_review_status=p_status, data_reviewed_by=auth.uid(), data_reviewed_at=now(),
        directory_status=case when p_status='approved' then directory_status
                              when p_status='rejected' then 'rejected'
                              when directory_status='published' then 'pending_review' else directory_status end
     where id=p_id;
  elsif p_target='product' then
    update products set data_review_status=p_status, data_reviewed_by=auth.uid(), data_reviewed_at=now(),
        rejected_reason=case when p_status='rejected' then p_note end,
        directory_status=case when p_status='approved' then directory_status
                              when p_status='rejected' then 'rejected'
                              when directory_status='published' then 'pending_review' else directory_status end
     where id=p_id;
  else raise exception 'unknown target'; end if;
  if not found then raise exception 'target not found'; end if;
  insert into moderation_actions(target_type,target_id,action,reason,admin_id) values (p_target,p_id::text,'data_review:'||p_status::text,p_note,auth.uid());
end $f$;
create or replace function public.set_directory_status(p_target text, p_id uuid, p_status directory_status, p_reason text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $f$
begin
  if not is_staff() then raise exception 'staff only' using errcode='42501'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'reason required'; end if;
  if p_target='company' then update companies set directory_status=p_status where id=p_id;
  elsif p_target='product' then update products set directory_status=p_status, rejected_reason=case when p_status='rejected' then p_reason end where id=p_id;
  else raise exception 'unknown target'; end if;
  if not found then raise exception 'target not found'; end if;
  insert into moderation_actions(target_type,target_id,action,reason,admin_id) values (p_target,p_id::text,'status:'||p_status::text,p_reason,auth.uid());
end $f$;

-- ===== constraints and indexes =====
alter table public.audit_log add constraint audit_log_pkey PRIMARY KEY (id);
alter table public.brochures add constraint brochures_pkey PRIMARY KEY (company_id);
alter table public.catalogue_selections add constraint catalogue_selections_pkey PRIMARY KEY (company_id);
alter table public.categories add constraint categories_pkey PRIMARY KEY (id);
alter table public.cms_pages add constraint cms_pages_pkey PRIMARY KEY (slug);
alter table public.companies add constraint companies_pkey PRIMARY KEY (id);
alter table public.company_acquisition add constraint company_acquisition_pkey PRIMARY KEY (company_id);
alter table public.company_categories add constraint company_categories_pkey PRIMARY KEY (company_id, category_id);
alter table public.company_claim_evidence add constraint company_claim_evidence_pkey PRIMARY KEY (id);
alter table public.company_claims add constraint company_claims_pkey PRIMARY KEY (id);
alter table public.company_data_corrections add constraint company_data_corrections_pkey PRIMARY KEY (id);
alter table public.company_follow_ups add constraint company_follow_ups_pkey PRIMARY KEY (id);
alter table public.company_images add constraint company_images_pkey PRIMARY KEY (id);
alter table public.company_import_batches add constraint company_import_batches_pkey PRIMARY KEY (id);
alter table public.company_import_rows add constraint company_import_rows_pkey PRIMARY KEY (id);
alter table public.company_internal_notes add constraint company_internal_notes_pkey PRIMARY KEY (id);
alter table public.company_members add constraint company_members_pkey PRIMARY KEY (id);
alter table public.company_membership_audit add constraint company_membership_audit_pkey PRIMARY KEY (id);
alter table public.company_outreach_events add constraint company_outreach_events_pkey PRIMARY KEY (id);
alter table public.company_private add constraint company_private_pkey PRIMARY KEY (company_id);
alter table public.company_sources add constraint company_sources_pkey PRIMARY KEY (id);
alter table public.company_verification_reviews add constraint company_verification_reviews_pkey PRIMARY KEY (id);
alter table public.direct_messages add constraint direct_messages_pkey PRIMARY KEY (id);
alter table public.direct_threads add constraint direct_threads_pkey PRIMARY KEY (id);
alter table public.enquiries add constraint enquiries_pkey PRIMARY KEY (id);
alter table public.enquiry_contact_access add constraint enquiry_contact_access_pkey PRIMARY KEY (id);
alter table public.enquiry_private add constraint enquiry_private_pkey PRIMARY KEY (enquiry_id);
alter table public.enquiry_replies add constraint enquiry_replies_pkey PRIMARY KEY (id);
alter table public.lead_responses add constraint lead_responses_pkey PRIMARY KEY (id);
alter table public.media_assets add constraint media_assets_pkey PRIMARY KEY (id);
alter table public.moderation_actions add constraint moderation_actions_pkey PRIMARY KEY (id);
alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table public.orders add constraint orders_pkey PRIMARY KEY (id);
alter table public.product_group_items add constraint product_group_items_pkey PRIMARY KEY (group_id, product_id);
alter table public.product_groups add constraint product_groups_pkey PRIMARY KEY (id);
alter table public.product_images add constraint product_images_pkey PRIMARY KEY (id);
alter table public.product_view_events add constraint product_view_events_pkey PRIMARY KEY (id);
alter table public.products add constraint products_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.promotions add constraint promotions_pkey PRIMARY KEY (id);
alter table public.quotations add constraint quotations_pkey PRIMARY KEY (id);
alter table public.rate_events add constraint rate_events_pkey PRIMARY KEY (id);
alter table public.seller_feedback add constraint seller_feedback_pkey PRIMARY KEY (id);
alter table public.seller_settings add constraint seller_settings_pkey PRIMARY KEY (user_id);
alter table public.suppression_list add constraint suppression_list_pkey PRIMARY KEY (id);
alter table public.thread_reads add constraint thread_reads_pkey PRIMARY KEY (user_id, enquiry_id);
alter table public.categories add constraint categories_name_key UNIQUE (name);
alter table public.categories add constraint categories_slug_key UNIQUE (slug);
alter table public.companies add constraint companies_slug_key UNIQUE (slug);
alter table public.company_import_rows add constraint company_import_rows_batch_id_row_no_key UNIQUE (batch_id, row_no);
alter table public.company_members add constraint company_members_company_id_user_id_key UNIQUE (company_id, user_id);
alter table public.direct_threads add constraint direct_threads_buyer_id_company_id_subject_key UNIQUE (buyer_id, company_id, subject);
alter table public.enquiries add constraint enquiries_ref_key UNIQUE (ref);
alter table public.lead_responses add constraint lead_responses_enquiry_id_company_id_key UNIQUE (enquiry_id, company_id);
alter table public.media_assets add constraint media_assets_scope_key_key UNIQUE (scope, key);
alter table public.orders add constraint orders_quotation_id_key UNIQUE (quotation_id);
alter table public.companies add constraint companies_check CHECK (((verification_status <> 'verified'::verification_status) OR (claim_status = 'approved'::claim_status)));
alter table public.company_claims add constraint company_claims_status_check CHECK ((status <> 'unclaimed'::claim_status));
alter table public.company_internal_notes add constraint company_internal_notes_body_check CHECK ((char_length(body) <= 2000));
alter table public.company_members add constraint company_members_check CHECK (((user_id IS NOT NULL) OR (invite_email IS NOT NULL)));
alter table public.company_outreach_events add constraint company_outreach_events_check CHECK (((delivery <> 'sent'::outreach_delivery) OR (provider_ref IS NOT NULL)));
alter table public.company_outreach_events add constraint company_outreach_events_summary_check CHECK ((char_length(summary) <= 1000));
alter table public.company_sources add constraint company_sources_data_confidence_check CHECK (((data_confidence >= 1) AND (data_confidence <= 5)));
alter table public.company_verification_reviews add constraint company_verification_reviews_subject_check CHECK ((subject = ANY (ARRAY['claim'::text, 'verification'::text])));
alter table public.direct_messages add constraint direct_messages_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 4000)));
alter table public.enquiries add constraint enquiries_check CHECK ((((kind = 'product'::enquiry_kind) AND (company_id IS NOT NULL)) OR (kind = 'requirement'::enquiry_kind)));
alter table public.enquiries add constraint enquiries_message_check CHECK ((char_length(message) <= 2000));
alter table public.enquiries add constraint enquiries_subject_check CHECK (((char_length(subject) >= 2) AND (char_length(subject) <= 200)));
alter table public.enquiry_private add constraint enquiry_private_check CHECK (((buyer_phone IS NOT NULL) OR (buyer_email IS NOT NULL)));
alter table public.enquiry_replies add constraint enquiry_replies_body_check CHECK (((char_length(body) >= 1) AND (char_length(body) <= 4000)));
alter table public.enquiry_replies add constraint enquiry_replies_sender_side_check CHECK ((sender_side = ANY (ARRAY['buyer'::text, 'seller'::text])));
alter table public.media_assets add constraint media_assets_rights_status_check CHECK ((rights_status = ANY (ARRAY['owned'::image_rights, 'licensed'::image_rights, 'permission_granted'::image_rights, 'public_domain'::image_rights])));
alter table public.media_assets add constraint media_assets_scope_check CHECK ((scope = ANY (ARRAY['product_name'::text, 'category'::text])));
alter table public.moderation_actions add constraint moderation_actions_target_type_check CHECK ((target_type = ANY (ARRAY['product'::text, 'company'::text, 'category'::text, 'image'::text, 'enquiry'::text])));
alter table public.product_images add constraint product_images_check CHECK (((public_path IS NULL) OR ((review_status = 'approved'::review_status) AND (rights_status = ANY (ARRAY['owned'::image_rights, 'licensed'::image_rights, 'permission_granted'::image_rights, 'public_domain'::image_rights])))));
alter table public.promotions add constraint promotions_days_check CHECK (((days >= 1) AND (days <= 365)));
alter table public.quotations add constraint quotations_amount_check CHECK ((amount > (0)::numeric));
alter table public.seller_feedback add constraint seller_feedback_body_check CHECK ((char_length(body) <= 2000));
alter table public.suppression_list add constraint suppression_list_check CHECK (((domain IS NOT NULL) OR (normalized_name IS NOT NULL)));
alter table public.brochures add constraint brochures_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.catalogue_selections add constraint catalogue_selections_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.companies add constraint companies_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.companies add constraint companies_data_reviewed_by_fkey FOREIGN KEY (data_reviewed_by) REFERENCES profiles(id);
alter table public.companies add constraint companies_import_batch_id_fkey FOREIGN KEY (import_batch_id) REFERENCES company_import_batches(id);
alter table public.companies add constraint companies_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES profiles(id);
alter table public.company_acquisition add constraint company_acquisition_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_acquisition add constraint company_acquisition_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id);
alter table public.company_categories add constraint company_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE;
alter table public.company_categories add constraint company_categories_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_claim_evidence add constraint company_claim_evidence_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES company_claims(id) ON DELETE CASCADE;
alter table public.company_claim_evidence add constraint company_claim_evidence_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id);
alter table public.company_claims add constraint company_claims_claimant_id_fkey FOREIGN KEY (claimant_id) REFERENCES profiles(id);
alter table public.company_claims add constraint company_claims_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_claims add constraint company_claims_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES profiles(id);
alter table public.company_data_corrections add constraint company_data_corrections_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_data_corrections add constraint company_data_corrections_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table public.company_data_corrections add constraint company_data_corrections_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES profiles(id);
alter table public.company_data_corrections add constraint company_data_corrections_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id);
alter table public.company_follow_ups add constraint company_follow_ups_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_follow_ups add constraint company_follow_ups_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.company_follow_ups add constraint company_follow_ups_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id);
alter table public.company_images add constraint company_images_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_import_batches add constraint company_import_batches_operator_id_fkey FOREIGN KEY (operator_id) REFERENCES profiles(id);
alter table public.company_import_rows add constraint company_import_rows_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES company_import_batches(id) ON DELETE CASCADE;
alter table public.company_import_rows add constraint company_import_rows_match_company_id_fkey FOREIGN KEY (match_company_id) REFERENCES companies(id) ON DELETE SET NULL;
alter table public.company_internal_notes add constraint company_internal_notes_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id);
alter table public.company_internal_notes add constraint company_internal_notes_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_members add constraint company_members_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_members add constraint company_members_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES profiles(id);
alter table public.company_members add constraint company_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.company_outreach_events add constraint company_outreach_events_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_outreach_events add constraint company_outreach_events_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES profiles(id);
alter table public.company_private add constraint company_private_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_sources add constraint company_sources_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_sources add constraint company_sources_import_batch_id_fkey FOREIGN KEY (import_batch_id) REFERENCES company_import_batches(id) ON DELETE CASCADE;
alter table public.company_sources add constraint company_sources_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES profiles(id);
alter table public.company_verification_reviews add constraint company_verification_reviews_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES company_claims(id) ON DELETE SET NULL;
alter table public.company_verification_reviews add constraint company_verification_reviews_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_verification_reviews add constraint company_verification_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES profiles(id);
alter table public.direct_messages add constraint direct_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES profiles(id);
alter table public.direct_messages add constraint direct_messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES direct_threads(id) ON DELETE CASCADE;
alter table public.direct_threads add constraint direct_threads_buyer_id_fkey FOREIGN KEY (buyer_id) REFERENCES profiles(id);
alter table public.direct_threads add constraint direct_threads_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id);
alter table public.enquiries add constraint enquiries_buyer_id_fkey FOREIGN KEY (buyer_id) REFERENCES profiles(id);
alter table public.enquiries add constraint enquiries_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id);
alter table public.enquiries add constraint enquiries_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE SET NULL;
alter table public.enquiries add constraint enquiries_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;
alter table public.enquiry_contact_access add constraint enquiry_contact_access_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES enquiries(id) ON DELETE CASCADE;
alter table public.enquiry_private add constraint enquiry_private_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES enquiries(id) ON DELETE CASCADE;
alter table public.enquiry_replies add constraint enquiry_replies_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES enquiries(id) ON DELETE CASCADE;
alter table public.enquiry_replies add constraint enquiry_replies_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES profiles(id);
alter table public.lead_responses add constraint lead_responses_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.lead_responses add constraint lead_responses_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES enquiries(id) ON DELETE CASCADE;
alter table public.lead_responses add constraint lead_responses_responded_by_fkey FOREIGN KEY (responded_by) REFERENCES profiles(id);
alter table public.media_assets add constraint media_assets_added_by_fkey FOREIGN KEY (added_by) REFERENCES profiles(id);
alter table public.moderation_actions add constraint moderation_actions_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES profiles(id);
alter table public.notifications add constraint notifications_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.notifications add constraint notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.orders add constraint orders_buyer_id_fkey FOREIGN KEY (buyer_id) REFERENCES profiles(id);
alter table public.orders add constraint orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id);
alter table public.orders add constraint orders_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES quotations(id);
alter table public.product_group_items add constraint product_group_items_group_id_fkey FOREIGN KEY (group_id) REFERENCES product_groups(id) ON DELETE CASCADE;
alter table public.product_group_items add constraint product_group_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table public.product_groups add constraint product_groups_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.product_images add constraint product_images_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table public.product_images add constraint product_images_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id);
alter table public.product_view_events add constraint product_view_events_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.product_view_events add constraint product_view_events_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table public.products add constraint products_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id);
alter table public.products add constraint products_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.products add constraint products_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.products add constraint products_data_reviewed_by_fkey FOREIGN KEY (data_reviewed_by) REFERENCES profiles(id);
alter table public.promotions add constraint promotions_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.promotions add constraint promotions_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.promotions add constraint promotions_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table public.quotations add constraint quotations_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id);
alter table public.quotations add constraint quotations_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.quotations add constraint quotations_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES enquiries(id) ON DELETE CASCADE;
alter table public.seller_feedback add constraint seller_feedback_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id);
alter table public.seller_feedback add constraint seller_feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id);
alter table public.seller_settings add constraint seller_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.suppression_list add constraint suppression_list_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table public.thread_reads add constraint thread_reads_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES enquiries(id) ON DELETE CASCADE;
alter table public.thread_reads add constraint thread_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX companies_dedupe_uq ON public.companies USING btree (dedupe_key) WHERE (dedupe_key IS NOT NULL);
CREATE INDEX companies_directory_status_city_idx ON public.companies USING btree (directory_status, city);
CREATE INDEX companies_name_idx ON public.companies USING gin (name gin_trgm_ops);
CREATE INDEX companies_norm_name_idx ON public.companies USING btree (norm_name(name));
CREATE UNIQUE INDEX company_claims_active_uq ON public.company_claims USING btree (company_id, claimant_id) WHERE (status = ANY (ARRAY['claim_submitted'::claim_status, 'evidence_requested'::claim_status, 'under_review'::claim_status]));
CREATE UNIQUE INDEX company_members_company_id_lower_idx ON public.company_members USING btree (company_id, lower(invite_email)) WHERE (invite_email IS NOT NULL);
CREATE INDEX company_sources_company_id_field_name_idx ON public.company_sources USING btree (company_id, field_name);
CREATE INDEX enquiries_buyer_id_created_at_idx ON public.enquiries USING btree (buyer_id, created_at DESC);
CREATE INDEX enquiries_company_id_status_created_at_idx ON public.enquiries USING btree (company_id, status, created_at DESC);
CREATE INDEX enquiries_delivery_idx ON public.enquiries USING btree (delivery) WHERE (delivery = 'awaiting_admin'::enquiry_delivery);
CREATE INDEX enquiries_kind_category_id_created_at_idx ON public.enquiries USING btree (kind, category_id, created_at DESC);
CREATE INDEX enquiry_replies_enquiry_id_created_at_idx ON public.enquiry_replies USING btree (enquiry_id, created_at);
CREATE INDEX notifications_user_id_read_at_created_at_idx ON public.notifications USING btree (user_id, read_at, created_at DESC);
CREATE INDEX product_view_events_company_id_viewed_at_idx ON public.product_view_events USING btree (company_id, viewed_at);
CREATE INDEX product_view_events_product_id_viewer_hash_viewed_at_idx ON public.product_view_events USING btree (product_id, viewer_hash, viewed_at);
CREATE INDEX products_category_id_directory_status_idx ON public.products USING btree (category_id, directory_status);
CREATE INDEX products_company_id_directory_status_idx ON public.products USING btree (company_id, directory_status);
CREATE INDEX products_name_idx ON public.products USING gin (name gin_trgm_ops);
CREATE INDEX products_search_idx ON public.products USING gin (search);
CREATE INDEX rate_events_user_id_action_at_idx ON public.rate_events USING btree (user_id, action, at DESC);

-- ===== row level security and policies =====
alter table public.audit_log enable row level security, force row level security;
alter table public.brochures enable row level security, force row level security;
alter table public.catalogue_selections enable row level security, force row level security;
alter table public.categories enable row level security, force row level security;
alter table public.cms_pages enable row level security, force row level security;
alter table public.companies enable row level security, force row level security;
alter table public.company_acquisition enable row level security, force row level security;
alter table public.company_categories enable row level security, force row level security;
alter table public.company_claim_evidence enable row level security, force row level security;
alter table public.company_claims enable row level security, force row level security;
alter table public.company_data_corrections enable row level security, force row level security;
alter table public.company_follow_ups enable row level security, force row level security;
alter table public.company_images enable row level security, force row level security;
alter table public.company_import_batches enable row level security, force row level security;
alter table public.company_import_rows enable row level security, force row level security;
alter table public.company_internal_notes enable row level security, force row level security;
alter table public.company_members enable row level security, force row level security;
alter table public.company_membership_audit enable row level security, force row level security;
alter table public.company_outreach_events enable row level security, force row level security;
alter table public.company_private enable row level security, force row level security;
alter table public.company_sources enable row level security, force row level security;
alter table public.company_verification_reviews enable row level security, force row level security;
alter table public.direct_messages enable row level security, force row level security;
alter table public.direct_threads enable row level security, force row level security;
alter table public.enquiries enable row level security, force row level security;
alter table public.enquiry_contact_access enable row level security, force row level security;
alter table public.enquiry_private enable row level security, force row level security;
alter table public.enquiry_replies enable row level security, force row level security;
alter table public.lead_responses enable row level security, force row level security;
alter table public.media_assets enable row level security, force row level security;
alter table public.moderation_actions enable row level security, force row level security;
alter table public.notifications enable row level security, force row level security;
alter table public.orders enable row level security, force row level security;
alter table public.product_group_items enable row level security, force row level security;
alter table public.product_groups enable row level security, force row level security;
alter table public.product_images enable row level security, force row level security;
alter table public.product_view_events enable row level security, force row level security;
alter table public.products enable row level security, force row level security;
alter table public.profiles enable row level security, force row level security;
alter table public.promotions enable row level security, force row level security;
alter table public.quotations enable row level security, force row level security;
alter table public.rate_events enable row level security, force row level security;
alter table public.seller_feedback enable row level security, force row level security;
alter table public.seller_settings enable row level security, force row level security;
alter table public.suppression_list enable row level security, force row level security;
alter table public.thread_reads enable row level security, force row level security;
create policy audit_read on public.audit_log as permissive for SELECT to public using (is_staff());
create policy bro_read on public.brochures as permissive for SELECT to public using ((is_company_member(company_id) OR is_staff()));
create policy bro_write on public.brochures as permissive for ALL to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role])) with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]));
create policy csel_del on public.catalogue_selections as permissive for DELETE to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy csel_ins on public.catalogue_selections as permissive for INSERT to public with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy csel_read on public.catalogue_selections as permissive for SELECT to public using (is_company_member(company_id));
create policy csel_upd on public.catalogue_selections as permissive for UPDATE to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role])) with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy categories_admin on public.categories as permissive for ALL to authenticated using (is_admin()) with check (is_admin());
create policy categories_read_anon on public.categories as permissive for SELECT to anon using ((NOT hidden));
create policy categories_read_auth on public.categories as permissive for SELECT to authenticated using (((NOT hidden) OR is_staff()));
create policy cms_admin on public.cms_pages as permissive for ALL to authenticated using (is_admin()) with check (is_admin());
create policy cms_read_anon on public.cms_pages as permissive for SELECT to anon using (published);
create policy cms_read_auth on public.cms_pages as permissive for SELECT to authenticated using ((published OR is_staff()));
create policy companies_member_update on public.companies as permissive for UPDATE to public using (has_company_role(id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role])) with check (has_company_role(id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy companies_read on public.companies as permissive for SELECT to public using ((is_company_member(id) OR user_is_claimant(id) OR is_staff()));
create policy companies_staff_update on public.companies as permissive for UPDATE to public using (is_staff()) with check (is_staff());
create policy cacq_staff on public.company_acquisition as permissive for ALL to public using (is_staff()) with check (is_staff());
create policy ccat_read on public.company_categories as permissive for SELECT to authenticated using ((company_is_live(company_id) OR is_company_member(company_id) OR is_staff()));
create policy ccat_write on public.company_categories as permissive for ALL to authenticated using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff())) with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
create policy cev_ins on public.company_claim_evidence as permissive for INSERT to public with check (((uploaded_by = auth.uid()) AND claim_is_open_for_me(claim_id)));
create policy cev_read on public.company_claim_evidence as permissive for SELECT to public using (((claim_claimant(claim_id) = auth.uid()) OR is_staff()));
create policy claims_read on public.company_claims as permissive for SELECT to public using (((claimant_id = auth.uid()) OR is_staff()));
create policy corr_read on public.company_data_corrections as permissive for SELECT to public using (((reporter_id = auth.uid()) OR is_staff() OR has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role])));
create policy corr_staff_upd on public.company_data_corrections as permissive for UPDATE to public using (is_staff()) with check ((is_staff() AND (reviewed_by = auth.uid())));
create policy cfu_staff on public.company_follow_ups as permissive for ALL to public using (is_staff()) with check (is_staff());
create policy cimg_del on public.company_images as permissive for DELETE to public using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff()));
create policy cimg_ins on public.company_images as permissive for INSERT to public with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff()));
create policy cimg_read on public.company_images as permissive for SELECT to public using ((is_company_member(company_id) OR is_staff()));
create policy cimg_upd on public.company_images as permissive for UPDATE to public using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff())) with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff()));
create policy cimp_b on public.company_import_batches as permissive for ALL to public using (is_staff()) with check ((is_staff() AND (operator_id = auth.uid())));
create policy cimp_r on public.company_import_rows as permissive for ALL to public using (is_staff()) with check (is_staff());
create policy cnote_ins on public.company_internal_notes as permissive for INSERT to public with check ((is_staff() AND (author_id = auth.uid())));
create policy cnote_read on public.company_internal_notes as permissive for SELECT to public using (is_staff());
create policy members_del on public.company_members as permissive for DELETE to public using (has_company_role(company_id, ARRAY['owner'::member_role]));
create policy members_ins on public.company_members as permissive for INSERT to public with check ((has_company_role(company_id, ARRAY['owner'::member_role]) AND (status = 'invited'::member_status) AND (user_id IS NULL) AND (role <> 'owner'::member_role)));
create policy members_read on public.company_members as permissive for SELECT to public using (((user_id = auth.uid()) OR is_company_member(company_id) OR is_staff()));
create policy members_upd on public.company_members as permissive for UPDATE to public using (has_company_role(company_id, ARRAY['owner'::member_role])) with check (has_company_role(company_id, ARRAY['owner'::member_role]));
create policy cma_read on public.company_membership_audit as permissive for SELECT to public using (is_staff());
create policy cout_insert on public.company_outreach_events as permissive for INSERT to public with check ((is_staff() AND (recorded_by = auth.uid())));
create policy cout_read on public.company_outreach_events as permissive for SELECT to public using (is_staff());
create policy cpriv_del on public.company_private as permissive for DELETE to public using (is_admin());
create policy cpriv_read on public.company_private as permissive for SELECT to public using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
create policy cpriv_upd on public.company_private as permissive for UPDATE to public using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff())) with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
create policy cpriv_write on public.company_private as permissive for INSERT to public with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
create policy csrc_staff on public.company_sources as permissive for ALL to public using (is_staff()) with check (is_staff());
create policy cvr_read on public.company_verification_reviews as permissive for SELECT to public using (is_staff());
create policy dm_ins on public.direct_messages as permissive for INSERT to public with check (((sender_id = auth.uid()) AND ((thread_buyer(thread_id) = auth.uid()) OR has_company_role(thread_company(thread_id), ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]))));
create policy dm_read on public.direct_messages as permissive for SELECT to public using (((thread_buyer(thread_id) = auth.uid()) OR has_company_role(thread_company(thread_id), ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]) OR is_staff()));
create policy dt_ins on public.direct_threads as permissive for INSERT to public with check ((buyer_id = auth.uid()));
create policy dt_read on public.direct_threads as permissive for SELECT to public using (((buyer_id = auth.uid()) OR has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]) OR is_staff()));
create policy enq_buyer_read on public.enquiries as permissive for SELECT to public using ((buyer_id = auth.uid()));
create policy enq_company_read on public.enquiries as permissive for SELECT to public using (((company_id IS NOT NULL) AND has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role])));
create policy enq_leads_read on public.enquiries as permissive for SELECT to public using (((kind = 'requirement'::enquiry_kind) AND seller_can_see_leads() AND lead_matches_my_company(category_id)));
create policy enq_staff_read on public.enquiries as permissive for SELECT to public using (is_staff());
create policy enq_staff_upd on public.enquiries as permissive for UPDATE to public using (is_staff()) with check (is_staff());
create policy enq_status_upd on public.enquiries as permissive for UPDATE to public using (((company_id IS NOT NULL) AND has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]))) with check (((company_id IS NOT NULL) AND has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role])));
create policy eca_read on public.enquiry_contact_access as permissive for SELECT to public using (is_staff());
create policy epriv_read on public.enquiry_private as permissive for SELECT to public using (((enquiry_buyer(enquiry_id) = auth.uid()) OR is_staff()));
create policy replies_ins on public.enquiry_replies as permissive for INSERT to public with check (((sender_id = auth.uid()) AND (((sender_side = 'buyer'::text) AND (enquiry_buyer(enquiry_id) = auth.uid())) OR ((sender_side = 'seller'::text) AND seller_can_reply(enquiry_id)))));
create policy replies_read on public.enquiry_replies as permissive for SELECT to public using (((enquiry_buyer(enquiry_id) = auth.uid()) OR seller_can_reply(enquiry_id) OR is_staff()));
create policy lr_read on public.lead_responses as permissive for SELECT to public using ((is_company_member(company_id) OR (enquiry_buyer(enquiry_id) = auth.uid()) OR is_staff()));
create policy media_admin on public.media_assets as permissive for ALL to authenticated using (is_staff()) with check (is_staff());
create policy media_read on public.media_assets as permissive for SELECT to public using (true);
create policy mod_read on public.moderation_actions as permissive for SELECT to public using (is_staff());
create policy notif_del on public.notifications as permissive for DELETE to public using ((user_id = auth.uid()));
create policy notif_read on public.notifications as permissive for SELECT to public using ((user_id = auth.uid()));
create policy notif_upd on public.notifications as permissive for UPDATE to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy orders_read on public.orders as permissive for SELECT to public using (((buyer_id = auth.uid()) OR has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]) OR is_staff()));
create policy gitems_del on public.product_group_items as permissive for DELETE to public using (has_company_role(group_company(group_id), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy gitems_ins on public.product_group_items as permissive for INSERT to public with check ((has_company_role(group_company(group_id), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) AND (product_company(product_id) = group_company(group_id))));
create policy gitems_read on public.product_group_items as permissive for SELECT to public using (is_company_member(group_company(group_id)));
create policy groups_del on public.product_groups as permissive for DELETE to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy groups_read on public.product_groups as permissive for SELECT to public using (is_company_member(company_id));
create policy groups_upd on public.product_groups as permissive for UPDATE to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role])) with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy groups_write on public.product_groups as permissive for INSERT to public with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy pimg_del on public.product_images as permissive for DELETE to public using ((has_company_role(product_company(product_id), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff()));
create policy pimg_ins on public.product_images as permissive for INSERT to public with check (has_company_role(product_company(product_id), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy pimg_read on public.product_images as permissive for SELECT to public using ((is_company_member(product_company(product_id)) OR is_staff()));
create policy pimg_upd on public.product_images as permissive for UPDATE to public using (has_company_role(product_company(product_id), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role])) with check (has_company_role(product_company(product_id), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy views_read on public.product_view_events as permissive for SELECT to public using ((is_company_member(company_id) OR is_staff()));
create policy products_del on public.products as permissive for DELETE to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]));
create policy products_ins on public.products as permissive for INSERT to public with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) AND (directory_status = ANY (ARRAY['draft'::directory_status, 'pending_review'::directory_status]))));
create policy products_read on public.products as permissive for SELECT to public using ((is_company_member(company_id) OR is_staff()));
create policy products_staff_upd on public.products as permissive for UPDATE to public using (is_staff()) with check (is_staff());
create policy products_upd on public.products as permissive for UPDATE to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role])) with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]));
create policy profiles_self_read on public.profiles as permissive for SELECT to public using (((id = auth.uid()) OR is_staff()));
create policy profiles_self_update on public.profiles as permissive for UPDATE to public using ((id = auth.uid())) with check ((id = auth.uid()));
create policy promos_read on public.promotions as permissive for SELECT to public using (is_company_member(company_id));
create policy promos_write on public.promotions as permissive for ALL to public using (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role])) with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) AND (product_company(product_id) = company_id)));
create policy quotes_ins on public.quotations as permissive for INSERT to public with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]));
create policy quotes_read on public.quotations as permissive for SELECT to public using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]) OR is_staff() OR ((enquiry_buyer(enquiry_id) = auth.uid()) AND ((status = ANY (ARRAY['sent'::quote_status, 'accepted'::quote_status, 'declined'::quote_status, 'expired'::quote_status])) OR ((status = 'withdrawn'::quote_status) AND (sent_at IS NOT NULL))))));
create policy quotes_upd on public.quotations as permissive for UPDATE to public using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]) AND (status = ANY (ARRAY['draft'::quote_status, 'sent'::quote_status])))) with check (has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]));
create policy fb_ins on public.seller_feedback as permissive for INSERT to public with check ((user_id = auth.uid()));
create policy fb_staff on public.seller_feedback as permissive for SELECT to public using (is_staff());
create policy settings_own on public.seller_settings as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy supp_staff on public.suppression_list as permissive for ALL to public using (is_staff()) with check (is_staff());
create policy reads_own on public.thread_reads as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy bro_obj_read on storage.objects as permissive for SELECT to authenticated using (((bucket_id = 'brochures'::text) AND (is_company_member(safe_uuid((storage.foldername(name))[1])) OR is_staff())));
create policy bro_obj_write on storage.objects as permissive for ALL to authenticated using (((bucket_id = 'brochures'::text) AND (has_company_role(safe_uuid((storage.foldername(name))[1]), ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()))) with check (((bucket_id = 'brochures'::text) AND (has_company_role(safe_uuid((storage.foldername(name))[1]), ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff())));
create policy cap_write on storage.objects as permissive for ALL to authenticated using (((bucket_id = 'company-assets-public'::text) AND (has_company_role(safe_uuid((storage.foldername(name))[1]), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff()))) with check (((bucket_id = 'company-assets-public'::text) AND (has_company_role(safe_uuid((storage.foldername(name))[1]), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff())));
create policy pmp_pending_rw on storage.objects as permissive for ALL to authenticated using (((bucket_id = 'product-media-pending'::text) AND (has_company_role(safe_uuid((storage.foldername(name))[1]), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff()))) with check (((bucket_id = 'product-media-pending'::text) AND (has_company_role(safe_uuid((storage.foldername(name))[1]), ARRAY['owner'::member_role, 'manager'::member_role, 'catalogue_editor'::member_role]) OR is_staff())));
create policy pmp_public_staff on storage.objects as permissive for ALL to authenticated using (((bucket_id = 'product-media-public'::text) AND is_staff())) with check (((bucket_id = 'product-media-public'::text) AND is_staff()));
create policy vd_admin_delete on storage.objects as permissive for DELETE to authenticated using (((bucket_id = 'verification-docs'::text) AND is_admin()));
create policy vd_insert on storage.objects as permissive for INSERT to authenticated with check (((bucket_id = 'verification-docs'::text) AND claim_is_open_for_me(safe_uuid((storage.foldername(name))[1]))));
create policy vd_read on storage.objects as permissive for SELECT to authenticated using (((bucket_id = 'verification-docs'::text) AND ((claim_claimant(safe_uuid((storage.foldername(name))[1])) = auth.uid()) OR is_staff())));

-- ===== triggers and views =====
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.audit_log FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();
CREATE TRIGGER trg_audit_companies AFTER UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'directory_status', 'claim_status', 'verification_status', 'data_review_status');
CREATE TRIGGER trg_companies_upd BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_company_publish BEFORE INSERT OR UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION company_publish_check();
CREATE TRIGGER trg_guard_company BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION guard_company_columns();
CREATE TRIGGER trg_rate_evid BEFORE INSERT ON public.company_claim_evidence FOR EACH ROW EXECUTE FUNCTION rate_trigger('evidence', '20', '1440');
CREATE TRIGGER trg_audit_claims AFTER UPDATE ON public.company_claims FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'status');
CREATE TRIGGER trg_claims_upd BEFORE UPDATE ON public.company_claims FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_guard_cimage BEFORE INSERT OR UPDATE ON public.company_images FOR EACH ROW EXECUTE FUNCTION guard_company_image();
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.company_internal_notes FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER trg_guard_member BEFORE INSERT OR DELETE OR UPDATE ON public.company_members FOR EACH ROW EXECUTE FUNCTION guard_member();
CREATE TRIGGER trg_member_audit AFTER INSERT OR DELETE OR UPDATE ON public.company_members FOR EACH ROW EXECUTE FUNCTION audit_membership();
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.company_membership_audit FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.company_outreach_events FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER trg_outreach_touch AFTER INSERT ON public.company_outreach_events FOR EACH ROW EXECUTE FUNCTION outreach_touch();
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.company_verification_reviews FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER trg_rate_dm BEFORE INSERT ON public.direct_messages FOR EACH ROW EXECUTE FUNCTION rate_trigger('dm', '60', '60');
CREATE TRIGGER trg_guard_dt BEFORE INSERT ON public.direct_threads FOR EACH ROW EXECUTE FUNCTION guard_direct_thread();
CREATE TRIGGER trg_rate_dt BEFORE INSERT ON public.direct_threads FOR EACH ROW EXECUTE FUNCTION rate_trigger('dthread', '10', '1440');
CREATE TRIGGER trg_audit_enq AFTER UPDATE ON public.enquiries FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'delivery', 'status');
CREATE TRIGGER trg_enq_upd BEFORE UPDATE ON public.enquiries FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_guard_enquiry BEFORE UPDATE ON public.enquiries FOR EACH ROW EXECUTE FUNCTION guard_enquiry();
CREATE TRIGGER trg_notify_enquiry AFTER INSERT ON public.enquiries FOR EACH ROW EXECUTE FUNCTION notify_on_enquiry();
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.enquiry_contact_access FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER trg_guard_reply BEFORE INSERT ON public.enquiry_replies FOR EACH ROW EXECUTE FUNCTION guard_reply();
CREATE TRIGGER trg_rate_reply BEFORE INSERT ON public.enquiry_replies FOR EACH ROW EXECUTE FUNCTION rate_trigger('reply', '60', '60');
CREATE TRIGGER trg_immutable BEFORE DELETE OR UPDATE ON public.moderation_actions FOR EACH ROW EXECUTE FUNCTION block_mutation();
CREATE TRIGGER trg_audit_orders AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'status');
CREATE TRIGGER trg_audit_images AFTER UPDATE ON public.product_images FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'review_status', 'rights_status', 'public_path');
CREATE TRIGGER trg_guard_image BEFORE INSERT OR UPDATE ON public.product_images FOR EACH ROW EXECUTE FUNCTION guard_product_image();
CREATE TRIGGER trg_audit_products AFTER UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'directory_status', 'data_review_status');
CREATE TRIGGER trg_guard_product BEFORE INSERT OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION guard_product();
CREATE TRIGGER trg_product_publish BEFORE INSERT OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION product_publish_check();
CREATE TRIGGER trg_products_upd BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_audit_profiles AFTER UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'app_role');
CREATE TRIGGER trg_guard_role BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION guard_profile_role();
CREATE TRIGGER trg_profiles_upd BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_audit_quotes AFTER UPDATE ON public.quotations FOR EACH ROW EXECUTE FUNCTION audit_changes('id', '-', 'status');
CREATE TRIGGER trg_guard_quote BEFORE INSERT OR UPDATE ON public.quotations FOR EACH ROW EXECUTE FUNCTION guard_quote();
CREATE TRIGGER trg_rate_fb BEFORE INSERT ON public.seller_feedback FOR EACH ROW EXECUTE FUNCTION rate_trigger('feedback', '10', '1440');
CREATE TRIGGER trg_suppression AFTER INSERT ON public.suppression_list FOR EACH ROW EXECUTE FUNCTION suppression_apply();

create view public.public_companies with (security_invoker=false) as  SELECT id, slug, name, business_type, about, city, state, country, website, logo_path,
        CASE
            WHEN verification_status = 'verified'::verification_status THEN 'Verified'::text
            WHEN verification_status = 'pending'::verification_status THEN 'Verification Pending'::text
            WHEN claim_status = 'approved'::claim_status THEN 'Claimed — Not Verified'::text
            WHEN claim_status = ANY (ARRAY['claim_submitted'::claim_status, 'evidence_requested'::claim_status, 'under_review'::claim_status]) THEN 'Claim Requested'::text
            ELSE 'Unclaimed — Not Verified'::text
        END AS public_label,
    claim_status = 'approved'::claim_status AS is_claimed,
    verification_status = 'verified'::verification_status AS is_verified,
    ( SELECT max(COALESCE(s.last_checked_at, s.collected_at)) AS max FROM company_sources s WHERE s.company_id = c.id) AS data_as_of,
    updated_at
   FROM companies c
  WHERE directory_status = 'published'::directory_status AND data_review_status = 'approved'::review_status;
create view public.public_company_categories with (security_invoker=false) as  SELECT cc.company_id, cc.category_id
   FROM company_categories cc JOIN public_companies c ON c.id = cc.company_id JOIN categories k ON k.id = cc.category_id AND NOT k.hidden;
create view public.public_company_images with (security_invoker=false) as  SELECT i.id, i.company_id, i.path, i."position"
   FROM company_images i JOIN public_companies c ON c.id = i.company_id
  WHERE i.review_status = 'approved'::review_status AND (i.rights_status = ANY (ARRAY['owned'::image_rights, 'licensed'::image_rights, 'permission_granted'::image_rights, 'public_domain'::image_rights]));
create view public.public_company_sources with (security_invoker=false) as  SELECT s.company_id, s.field_name, s.source_type, s.source_name, s.source_url, s.collected_at, s.last_checked_at
   FROM company_sources s JOIN companies c ON c.id = s.company_id
  WHERE c.directory_status = 'published'::directory_status AND c.data_review_status = 'approved'::review_status AND s.source_url !~~ 'direct-submission:%'::text;
create view public.public_products with (security_invoker=false) as  SELECT p.id, p.company_id, p.category_id, p.name, p.description, p.price, p.price_on_request, p.unit, p.moq, p.specs, p.tags, p.association_basis, p.source_name, p.source_url, p.last_checked_at, p.search, p.updated_at, c.slug AS company_slug, c.name AS company_name, pc.public_label AS company_label
   FROM products p JOIN companies c ON c.id = p.company_id JOIN public_companies pc ON pc.id = c.id JOIN categories k ON k.id = p.category_id AND NOT k.hidden
  WHERE p.directory_status = 'published'::directory_status AND p.data_review_status = 'approved'::review_status;
create view public.public_product_images with (security_invoker=false) as  SELECT i.id, i.product_id, i.public_path, i."position"
   FROM product_images i JOIN public_products p ON p.id = i.product_id
  WHERE i.public_path IS NOT NULL AND i.review_status = 'approved'::review_status AND (i.rights_status = ANY (ARRAY['owned'::image_rights, 'licensed'::image_rights, 'permission_granted'::image_rights, 'public_domain'::image_rights]));

-- ===== grants (generated from the verified ACL catalogue; PG17 MAINTAIN privilege omitted for PG16 reproducibility) =====
revoke all on table public.audit_log from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.audit_log to service_role;
grant select on table public.audit_log to authenticated;
revoke all on sequence public.audit_log_id_seq from anon, authenticated, service_role;
grant select, usage on sequence public.audit_log_id_seq to authenticated;
revoke all on table public.brochures from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.brochures to service_role;
grant insert, select, update, delete on table public.brochures to authenticated;
revoke all on table public.catalogue_selections from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.catalogue_selections to service_role;
grant insert, select, update, delete on table public.catalogue_selections to authenticated;
revoke all on table public.categories from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.categories to service_role;
grant insert, select, update, delete on table public.categories to authenticated;
grant select on table public.categories to anon;
revoke all on sequence public.categories_id_seq from anon, authenticated, service_role;
grant select, usage on sequence public.categories_id_seq to authenticated;
revoke all on table public.cms_pages from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.cms_pages to service_role;
grant insert, select, update, delete on table public.cms_pages to authenticated;
grant select on table public.cms_pages to anon;
revoke all on table public.companies from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.companies to service_role;
grant select, update on table public.companies to authenticated;
revoke all on table public.company_acquisition from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_acquisition to service_role;
grant insert, select, update, delete on table public.company_acquisition to authenticated;
revoke all on table public.company_categories from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_categories to service_role;
grant insert, select, update, delete on table public.company_categories to authenticated;
revoke all on table public.company_claim_evidence from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_claim_evidence to service_role;
grant insert, select on table public.company_claim_evidence to authenticated;
revoke all on table public.company_claims from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_claims to service_role;
grant select on table public.company_claims to authenticated;
revoke all on table public.company_data_corrections from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_data_corrections to service_role;
grant select, update on table public.company_data_corrections to authenticated;
revoke all on table public.company_follow_ups from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_follow_ups to service_role;
grant insert, select, update, delete on table public.company_follow_ups to authenticated;
revoke all on table public.company_images from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_images to service_role;
grant insert, select, update, delete on table public.company_images to authenticated;
revoke all on table public.company_import_batches from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_import_batches to service_role;
grant insert, select, update, delete on table public.company_import_batches to authenticated;
revoke all on table public.company_import_rows from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_import_rows to service_role;
grant insert, select, update, delete on table public.company_import_rows to authenticated;
revoke all on table public.company_internal_notes from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_internal_notes to service_role;
grant insert, select on table public.company_internal_notes to authenticated;
revoke all on table public.company_members from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_members to service_role;
grant insert, select, update, delete on table public.company_members to authenticated;
revoke all on table public.company_membership_audit from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_membership_audit to service_role;
grant select on table public.company_membership_audit to authenticated;
revoke all on sequence public.company_membership_audit_id_seq from anon, authenticated, service_role;
grant select, usage on sequence public.company_membership_audit_id_seq to authenticated;
revoke all on table public.company_outreach_events from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_outreach_events to service_role;
grant insert, select on table public.company_outreach_events to authenticated;
revoke all on table public.company_private from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_private to service_role;
grant insert, select, update, delete on table public.company_private to authenticated;
revoke all on table public.company_sources from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_sources to service_role;
grant insert, select, update, delete on table public.company_sources to authenticated;
revoke all on table public.company_verification_reviews from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.company_verification_reviews to service_role;
grant select on table public.company_verification_reviews to authenticated;
revoke all on table public.direct_messages from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.direct_messages to service_role;
grant insert, select on table public.direct_messages to authenticated;
revoke all on table public.direct_threads from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.direct_threads to service_role;
grant insert, select on table public.direct_threads to authenticated;
revoke all on table public.enquiries from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.enquiries to service_role;
grant select, update on table public.enquiries to authenticated;
revoke all on table public.enquiry_contact_access from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.enquiry_contact_access to service_role;
grant select on table public.enquiry_contact_access to authenticated;
revoke all on sequence public.enquiry_contact_access_id_seq from anon, authenticated, service_role;
grant select, usage on sequence public.enquiry_contact_access_id_seq to authenticated;
revoke all on table public.enquiry_private from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.enquiry_private to service_role;
grant select on table public.enquiry_private to authenticated;
revoke all on table public.enquiry_replies from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.enquiry_replies to service_role;
grant insert, select on table public.enquiry_replies to authenticated;
revoke all on table public.lead_responses from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.lead_responses to service_role;
grant select on table public.lead_responses to authenticated;
revoke all on table public.media_assets from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.media_assets to service_role;
grant insert, select, update, delete on table public.media_assets to authenticated;
grant select on table public.media_assets to anon;
revoke all on table public.moderation_actions from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.moderation_actions to service_role;
grant select on table public.moderation_actions to authenticated;
revoke all on table public.notifications from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.notifications to service_role;
grant select, update, delete on table public.notifications to authenticated;
revoke all on table public.orders from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.orders to service_role;
grant select on table public.orders to authenticated;
revoke all on table public.product_group_items from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.product_group_items to service_role;
grant insert, select, update, delete on table public.product_group_items to authenticated;
revoke all on table public.product_groups from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.product_groups to service_role;
grant insert, select, update, delete on table public.product_groups to authenticated;
revoke all on table public.product_images from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.product_images to service_role;
grant insert, select, update, delete on table public.product_images to authenticated;
revoke all on table public.product_view_events from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.product_view_events to service_role;
grant select on table public.product_view_events to authenticated;
revoke all on sequence public.product_view_events_id_seq from anon, authenticated, service_role;
grant select, usage on sequence public.product_view_events_id_seq to authenticated;
revoke all on table public.products from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.products to service_role;
grant insert, select, update, delete on table public.products to authenticated;
revoke all on table public.profiles from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.profiles to service_role;
grant select, update on table public.profiles to authenticated;
revoke all on table public.promotions from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.promotions to service_role;
grant insert, select, update, delete on table public.promotions to authenticated;
revoke all on table public.public_companies from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.public_companies to service_role;
grant select on table public.public_companies to anon;
grant select on table public.public_companies to authenticated;
revoke all on table public.public_company_categories from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.public_company_categories to service_role;
grant select on table public.public_company_categories to anon;
grant select on table public.public_company_categories to authenticated;
revoke all on table public.public_company_images from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.public_company_images to service_role;
grant select on table public.public_company_images to anon;
grant select on table public.public_company_images to authenticated;
revoke all on table public.public_company_sources from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.public_company_sources to service_role;
grant select on table public.public_company_sources to anon;
grant select on table public.public_company_sources to authenticated;
revoke all on table public.public_product_images from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.public_product_images to service_role;
grant select on table public.public_product_images to anon;
grant select on table public.public_product_images to authenticated;
revoke all on table public.public_products from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.public_products to service_role;
grant select on table public.public_products to anon;
grant select on table public.public_products to authenticated;
revoke all on table public.quotations from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.quotations to service_role;
grant insert, select, update on table public.quotations to authenticated;
revoke all on table public.rate_events from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.rate_events to service_role;
revoke all on sequence public.rate_events_id_seq from anon, authenticated, service_role;
grant select, usage on sequence public.rate_events_id_seq to authenticated;
revoke all on table public.seller_feedback from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.seller_feedback to service_role;
grant insert, select on table public.seller_feedback to authenticated;
revoke all on table public.seller_settings from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.seller_settings to service_role;
grant insert, select, update, delete on table public.seller_settings to authenticated;
revoke all on table public.suppression_list from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.suppression_list to service_role;
grant insert, select, update, delete on table public.suppression_list to authenticated;
revoke all on table public.thread_reads from anon, authenticated, service_role;
grant select, truncate, references, trigger on table public.thread_reads to service_role;
grant insert, select, update, delete on table public.thread_reads to authenticated;
revoke all on all functions in schema public from public, anon, authenticated, service_role;
grant execute on function public.accept_invitation(uuid) to authenticated;
grant execute on function public.accept_invitation(uuid) to service_role;
grant execute on function public.advance_order(uuid,order_status) to authenticated;
grant execute on function public.advance_order(uuid,order_status) to service_role;
grant execute on function public.approve_product_image(uuid,text) to authenticated;
grant execute on function public.approve_product_image(uuid,text) to service_role;
grant execute on function public.cancel_order(uuid) to authenticated;
grant execute on function public.cancel_order(uuid) to service_role;
grant execute on function public.claim_claimant(uuid) to authenticated;
grant execute on function public.claim_claimant(uuid) to service_role;
grant execute on function public.claim_company(uuid) to authenticated;
grant execute on function public.claim_company(uuid) to service_role;
grant execute on function public.claim_is_open_for_me(uuid) to authenticated;
grant execute on function public.claim_is_open_for_me(uuid) to service_role;
grant execute on function public.company_is_claimed(uuid) to authenticated;
grant execute on function public.company_is_claimed(uuid) to service_role;
grant execute on function public.company_is_live(uuid) to authenticated;
grant execute on function public.company_is_live(uuid) to service_role;
grant execute on function public.create_company_request(text,text,text,text) to authenticated;
grant execute on function public.create_company_request(text,text,text,text) to service_role;
grant execute on function public.create_order(uuid) to authenticated;
grant execute on function public.create_order(uuid) to service_role;
grant execute on function public.decline_invitation(uuid) to authenticated;
grant execute on function public.decline_invitation(uuid) to service_role;
grant execute on function public.enquiry_buyer(uuid) to authenticated;
grant execute on function public.enquiry_buyer(uuid) to service_role;
grant execute on function public.enquiry_company(uuid) to authenticated;
grant execute on function public.enquiry_company(uuid) to service_role;
grant execute on function public.group_company(uuid) to authenticated;
grant execute on function public.group_company(uuid) to service_role;
grant execute on function public.has_company_role(uuid,member_role[]) to authenticated;
grant execute on function public.has_company_role(uuid,member_role[]) to service_role;
grant execute on function public.import_apply(uuid) to authenticated;
grant execute on function public.import_apply(uuid) to service_role;
grant execute on function public.import_normalize(uuid) to authenticated;
grant execute on function public.import_normalize(uuid) to service_role;
grant execute on function public.import_rollback(uuid,text) to authenticated;
grant execute on function public.import_rollback(uuid,text) to service_role;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to service_role;
grant execute on function public.is_company_member(uuid) to authenticated;
grant execute on function public.is_company_member(uuid) to service_role;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.is_staff() to service_role;
grant execute on function public.is_trusted_session() to authenticated;
grant execute on function public.is_trusted_session() to service_role;
grant execute on function public.lead_matches_my_company(integer) to authenticated;
grant execute on function public.lead_matches_my_company(integer) to service_role;
grant execute on function public.make_slug(text) to authenticated;
grant execute on function public.make_slug(text) to service_role;
grant execute on function public.my_invitations() to authenticated;
grant execute on function public.my_invitations() to service_role;
grant execute on function public.norm_domain(text) to authenticated;
grant execute on function public.norm_domain(text) to service_role;
grant execute on function public.norm_name(text) to authenticated;
grant execute on function public.norm_name(text) to service_role;
grant execute on function public.product_company(uuid) to authenticated;
grant execute on function public.product_company(uuid) to service_role;
grant execute on function public.record_product_view(uuid,text) to service_role;
grant execute on function public.report_correction(uuid,uuid,text,text,text,text) to authenticated;
grant execute on function public.report_correction(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.respond_quotation(uuid,boolean) to authenticated;
grant execute on function public.respond_quotation(uuid,boolean) to service_role;
grant execute on function public.respond_to_lead(uuid,uuid) to authenticated;
grant execute on function public.respond_to_lead(uuid,uuid) to service_role;
grant execute on function public.reveal_buyer_contact(uuid,uuid) to authenticated;
grant execute on function public.reveal_buyer_contact(uuid,uuid) to service_role;
grant execute on function public.review_claim(uuid,claim_status,text) to authenticated;
grant execute on function public.review_claim(uuid,claim_status,text) to service_role;
grant execute on function public.safe_uuid(text) to authenticated;
grant execute on function public.safe_uuid(text) to service_role;
grant execute on function public.seller_can_reply(uuid) to authenticated;
grant execute on function public.seller_can_reply(uuid) to service_role;
grant execute on function public.seller_can_see_leads() to authenticated;
grant execute on function public.seller_can_see_leads() to service_role;
grant execute on function public.set_data_review(text,uuid,review_status,text) to authenticated;
grant execute on function public.set_data_review(text,uuid,review_status,text) to service_role;
grant execute on function public.set_directory_status(text,uuid,directory_status,text) to authenticated;
grant execute on function public.set_directory_status(text,uuid,directory_status,text) to service_role;
grant execute on function public.set_verification(uuid,verification_status,text) to authenticated;
grant execute on function public.set_verification(uuid,verification_status,text) to service_role;
grant execute on function public.staff_mark_enquiry(uuid,enquiry_delivery,text,text) to authenticated;
grant execute on function public.staff_mark_enquiry(uuid,enquiry_delivery,text,text) to service_role;
grant execute on function public.submit_claim(uuid,text,text) to authenticated;
grant execute on function public.submit_claim(uuid,text,text) to service_role;
grant execute on function public.submit_enquiry(enquiry_kind,uuid,uuid,integer,text,numeric,text,text,text,text,text,text,text,boolean,text) to authenticated;
grant execute on function public.submit_enquiry(enquiry_kind,uuid,uuid,integer,text,numeric,text,text,text,text,text,text,text,boolean,text) to service_role;
grant execute on function public.thread_buyer(uuid) to authenticated;
grant execute on function public.thread_buyer(uuid) to service_role;
grant execute on function public.thread_company(uuid) to authenticated;
grant execute on function public.thread_company(uuid) to service_role;
grant execute on function public.user_is_claimant(uuid) to authenticated;
grant execute on function public.user_is_claimant(uuid) to service_role;
grant execute on function public.withdraw_claim(uuid) to authenticated;
grant execute on function public.withdraw_claim(uuid) to service_role;
-- ===== table comments (data-classification notes present in staging) =====
comment on table public.audit_log is 'class=staff; immutable; every privileged status change.';
comment on table public.brochures is 'class=member; is_public=false by default; public delivery only via server-signed URL.';
comment on table public.catalogue_selections is 'class=member';
comment on table public.categories is 'class=public; taxonomy seeded from v16 SECTIONS. hidden=true hides from public.';
comment on table public.cms_pages is 'class=public when published.';
comment on table public.companies is 'class=member; columns are the public-approved directory fields. Anonymous access ONLY through view public_companies.';
comment on table public.company_acquisition is 'class=staff; outreach state per company.';
comment on table public.company_categories is 'class=public; categories a company operates in.';
comment on table public.company_claim_evidence is 'class=private; metadata for files in the private verification-docs bucket.';
comment on table public.company_claims is 'class=private; claimant + staff only. Status changes only through RPC.';
comment on table public.company_data_corrections is 'class=member; reporter sees own; staff review.';
comment on table public.company_follow_ups is 'class=staff';
comment on table public.company_images is 'class=member; public only via view when rights ok AND reviewed.';
comment on table public.company_import_batches is 'class=staff; one row per import run; terms_checked must be true before apply.';
comment on table public.company_import_rows is 'class=staff; raw -> normalised -> duplicate check -> approval.';
comment on table public.company_internal_notes is 'class=staff; immutable append-only. Do not store passwords, OTPs or unnecessary personal data.';
comment on table public.company_members is 'class=member; effective only while companies.claim_status = approved.';
comment on table public.company_membership_audit is 'class=staff; immutable; written by trigger on company_members.';
comment on table public.company_outreach_events is 'class=staff; immutable. delivery=sent requires provider_ref from a real channel; manual notes are logged_manual.';
comment on table public.company_private is 'class=private; contact details. Readable by claimed-company members and staff only; never public.';
comment on table public.company_sources is 'class=public-attribution via view; source per field. Staff write. Staff-only columns hidden in public views.';
comment on table public.company_verification_reviews is 'class=staff; immutable. Reviewer, decision, timestamp and reason.';
comment on table public.direct_messages is 'class=member; viewers cannot post.';
comment on table public.direct_threads is 'class=member; allowed only with published AND claimed companies.';
comment on table public.enquiries is 'class=member; NO buyer contact fields. Created only via submit_enquiry().';
comment on table public.enquiry_contact_access is 'class=staff; immutable audit of every disclosure of buyer contact details.';
comment on table public.enquiry_private is 'class=private; buyer identity/contact. Buyer + staff only. Sellers get access only via reveal_buyer_contact() (audited).';
comment on table public.enquiry_replies is 'class=member; thread messages on an enquiry.';
comment on table public.lead_responses is 'class=member; created only via respond_to_lead(). Prerequisite for contact reveal.';
comment on table public.media_assets is 'class=public; stock photos with mandatory source/licence note.';
comment on table public.moderation_actions is 'class=staff; immutable; companies see actions on their own products via view-less RPC only.';
comment on table public.notifications is 'class=private; inserts by triggers/functions only.';
comment on table public.orders is 'class=member; created only by create_order(); status changes only via advance_order()/cancel_order().';
comment on table public.product_group_items is 'class=member';
comment on table public.product_groups is 'class=member';
comment on table public.product_images is 'class=member; image provenance and rights per image. Public only via view when approved.';
comment on table public.product_view_events is 'class=member-read; inserts via record_product_view() (service_role only; dedupes per viewer_hash/hour).';
comment on table public.products is 'class=member; anonymous access only through view public_products.';
comment on table public.profiles is 'class=private; one row per auth user. app_role is server-controlled.';
comment on table public.promotions is 'class=member';
comment on table public.quotations is 'class=member; sellers create/send; ONLY buyer (via respond_quotation) can accept/decline.';
comment on table public.rate_events is 'class=system; used by check_rate().';
comment on table public.seller_feedback is 'class=staff';
comment on table public.seller_settings is 'class=private';
comment on table public.suppression_list is 'class=staff; removal/suppression requests; blocks re-import.';
comment on table public.thread_reads is 'class=private';

-- ===== storage buckets (configuration rows; storage objects are never part of a baseline) =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('brochures','brochures','f'::boolean,10485760,'{application/pdf}'::text[]),
  ('company-assets-public','company-assets-public','t'::boolean,5242880,'{image/jpeg,image/png,image/webp}'::text[]),
  ('product-media-pending','product-media-pending','f'::boolean,5242880,'{image/jpeg,image/png,image/webp}'::text[]),
  ('product-media-public','product-media-public','t'::boolean,5242880,'{image/jpeg,image/png,image/webp}'::text[]),
  ('verification-docs','verification-docs','f'::boolean,10485760,'{application/pdf,image/jpeg,image/png}'::text[])
on conflict (id) do nothing;
commit;

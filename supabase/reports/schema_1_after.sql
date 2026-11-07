--
-- PostgreSQL database dump
--


-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA storage;


ALTER SCHEMA storage OWNER TO postgres;

--
-- Name: acquisition_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.acquisition_status AS ENUM (
    'not_contacted',
    'contact_attempted',
    'in_conversation',
    'invited_to_claim',
    'claim_started',
    'declined',
    'do_not_contact'
);


ALTER TYPE public.acquisition_status OWNER TO postgres;

--
-- Name: app_role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.app_role AS ENUM (
    'buyer',
    'seller',
    'reviewer',
    'admin'
);


ALTER TYPE public.app_role OWNER TO postgres;

--
-- Name: assoc_basis; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.assoc_basis AS ENUM (
    'manufacturer',
    'brand_owner',
    'distributor',
    'reseller',
    'marketplace_seller',
    'unknown'
);


ALTER TYPE public.assoc_basis OWNER TO postgres;

--
-- Name: claim_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.claim_status AS ENUM (
    'unclaimed',
    'claim_submitted',
    'evidence_requested',
    'under_review',
    'approved',
    'rejected',
    'withdrawn'
);


ALTER TYPE public.claim_status OWNER TO postgres;

--
-- Name: directory_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.directory_status AS ENUM (
    'draft',
    'pending_review',
    'published',
    'paused',
    'rejected',
    'suspended'
);


ALTER TYPE public.directory_status OWNER TO postgres;

--
-- Name: enquiry_delivery; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.enquiry_delivery AS ENUM (
    'stored',
    'awaiting_admin',
    'visible_to_seller',
    'sent_external',
    'failed'
);


ALTER TYPE public.enquiry_delivery OWNER TO postgres;

--
-- Name: enquiry_kind; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.enquiry_kind AS ENUM (
    'product',
    'requirement'
);


ALTER TYPE public.enquiry_kind OWNER TO postgres;

--
-- Name: enquiry_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.enquiry_status AS ENUM (
    'new',
    'read',
    'replied',
    'quoted',
    'closed',
    'spam'
);


ALTER TYPE public.enquiry_status OWNER TO postgres;

--
-- Name: image_rights; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.image_rights AS ENUM (
    'unknown',
    'owned',
    'licensed',
    'permission_granted',
    'public_domain',
    'rejected'
);


ALTER TYPE public.image_rights OWNER TO postgres;

--
-- Name: lead_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.lead_status AS ENUM (
    'new',
    'assigned',
    'contact_pending',
    'contacted',
    'interested',
    'not_interested',
    'claim_invitation_sent',
    'registration_started',
    'verification_pending',
    'seller_activated',
    'follow_up_required',
    'no_suitable_supplier',
    'closed'
);


ALTER TYPE public.lead_status OWNER TO postgres;

--
-- Name: match_route; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.match_route AS ENUM (
    'direct',
    'admin'
);


ALTER TYPE public.match_route OWNER TO postgres;

--
-- Name: member_role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.member_role AS ENUM (
    'owner',
    'manager',
    'sales',
    'catalogue_editor',
    'viewer'
);


ALTER TYPE public.member_role OWNER TO postgres;

--
-- Name: member_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.member_status AS ENUM (
    'invited',
    'active',
    'removed'
);


ALTER TYPE public.member_status OWNER TO postgres;

--
-- Name: notif_kind; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.notif_kind AS ENUM (
    'system',
    'tip',
    'lead',
    'enquiry',
    'message',
    'moderation',
    'claim',
    'admin'
);


ALTER TYPE public.notif_kind OWNER TO postgres;

--
-- Name: outreach_delivery; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.outreach_delivery AS ENUM (
    'logged_manual',
    'queued',
    'sent',
    'failed'
);


ALTER TYPE public.outreach_delivery OWNER TO postgres;

--
-- Name: outreach_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.outreach_type AS ENUM (
    'call',
    'email',
    'message',
    'invitation',
    'follow_up',
    'note'
);


ALTER TYPE public.outreach_type OWNER TO postgres;

--
-- Name: review_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.review_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);


ALTER TYPE public.review_status OWNER TO postgres;

--
-- Name: source_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.source_type AS ENUM (
    'official_website',
    'public_business_directory',
    'trade_association',
    'exhibitor_directory',
    'government_registry',
    'direct_submission',
    'licensed_data_provider',
    'other_approved'
);


ALTER TYPE public.source_type OWNER TO postgres;

--
-- Name: verification_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.verification_status AS ENUM (
    'not_verified',
    'pending',
    'verified',
    'rejected',
    'expired'
);


ALTER TYPE public.verification_status OWNER TO postgres;

--
-- Name: _claim_approval_gate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public._claim_approval_gate() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    if not exists(select 1 from public.claim_verifications where claim_id = new.id and channel = 'email' and verified_at is not null) then raise exception 'claim cannot be approved: claimant email not verified'; end if;
    if exists(select 1 from public.company_claims o where o.company_id = new.company_id and o.id <> new.id and o.claimant_id <> new.claimant_id and o.status in ('claim_submitted','evidence_requested','under_review')) then raise exception 'claim cannot be approved: conflicting open claim needs separate review'; end if;
  end if; return new; end $$;


ALTER FUNCTION public._claim_approval_gate() OWNER TO postgres;

--
-- Name: _company_lead_eligible(uuid, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public._company_lead_eligible(p_company uuid, p_category integer) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists(
    select 1 from public.companies c cross join public.lead_routing_settings s
    where c.id = p_company and s.id = 1
      and c.claim_status = 'approved' and c.verification_status = 'verified' and c.directory_status = 'published'
      and not c.lead_delivery_blocked
      and exists(select 1 from public.company_members m where m.company_id = c.id and m.status = 'active' and m.role in ('owner','manager','sales'))
      and (p_category is null or exists(select 1 from public.company_categories cc where cc.company_id = c.id and cc.category_id = p_category))
      and (not s.require_verified_email or exists(select 1 from public.company_contacts k where k.company_id = c.id and k.kind = 'email' and k.status = 'verified' and k.last_verified_at > now() - make_interval(days => s.contact_max_age_days)))
      and (not s.require_verified_phone or exists(select 1 from public.company_contacts k where k.company_id = c.id and k.kind = 'phone' and k.status = 'verified' and k.last_verified_at > now() - make_interval(days => s.contact_max_age_days))))
$$;


ALTER FUNCTION public._company_lead_eligible(p_company uuid, p_category integer) OWNER TO postgres;

--
-- Name: _lead_case_history(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public._lead_case_history() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if tg_op = 'INSERT' then insert into public.lead_status_history(case_id, from_status, to_status, assigned_to, actor_id, note) values (new.id, null, new.status, new.assigned_to, auth.uid(), 'case created: ' || new.queue);
  elsif new.status is distinct from old.status or new.assigned_to is distinct from old.assigned_to then
    insert into public.lead_status_history(case_id, from_status, to_status, assigned_to, actor_id, note) values (new.id, old.status, new.status, new.assigned_to, auth.uid(), current_setting('app.lead_note', true));
  end if; return new; end $$;


ALTER FUNCTION public._lead_case_history() OWNER TO postgres;

--
-- Name: _match_requirement(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public._match_requirement(p_enq uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare e public.enquiries; d public.requirement_details; s public.lead_routing_settings;
  r record; term text; direct_n integer := 0; total_n integer := 0; unclaimed boolean := false; unverified boolean := false; capped boolean := false;
  route_v public.match_route; elig boolean; reasons jsonb; ins integer; case_id uuid; q text; m record;
begin
  select * into e from public.enquiries where id = p_enq and kind = 'requirement'; if not found then raise exception 'requirement not found'; end if;
  select * into d from public.requirement_details where enquiry_id = p_enq; if not found then raise exception 'requirement details missing'; end if;
  select * into s from public.lead_routing_settings where id = 1;
  term := regexp_replace(d.product_norm, '([%_\\])', '\\\1', 'g');
  select count(*) into direct_n from public.requirement_matches where enquiry_id = p_enq and route = 'direct';  -- already delivered stay counted
  for r in
    with cand as (
      select c.id, c.name, c.claim_status,
        (e.category_id is not null and exists(select 1 from public.company_categories cc where cc.company_id = c.id and cc.category_id = e.category_id)) f_cat,
        exists(select 1 from public.products p where p.company_id = c.id and p.directory_status = 'published' and (lower(p.name) like '%' || term || '%' or lower(coalesce(p.tags,'')) like '%' || term || '%')) f_prod,
        (coalesce(trim(d.destination_country),'') <> '' and (lower(trim(d.destination_country)) in (select lower(x) from unnest(c.export_markets) x) or lower(trim(d.destination_country)) = lower(coalesce(c.country,'')))) f_dest,
        (coalesce(trim(e.city),'') <> '' and lower(trim(e.city)) = lower(coalesce(c.city,''))) f_city,
        ('manufacturer' = any(c.business_types)) f_mfr
      from public.companies c where c.directory_status = 'published' and not c.is_demo)
    select *, (f_cat::int*40 + f_prod::int*30 + f_dest::int*15 + f_city::int*10 + f_mfr::int*5) score from cand
    where (f_cat or f_prod) order by (f_cat::int*40 + f_prod::int*30 + f_dest::int*15 + f_city::int*10 + f_mfr::int*5) desc, name
  loop
    continue when r.score < s.min_score;
    total_n := total_n + 1;
    reasons := '[]'::jsonb;
    if r.f_cat then reasons := reasons || jsonb_build_object('factor','category','points',40,'detail','Company operates in the requested category'); end if;
    if r.f_prod then reasons := reasons || jsonb_build_object('factor','product','points',30,'detail','A published product name or tag contains the requested product'); end if;
    if r.f_dest then reasons := reasons || jsonb_build_object('factor','destination','points',15,'detail','Company exports to, or is located in, the destination country'); end if;
    if r.f_city then reasons := reasons || jsonb_build_object('factor','location','points',10,'detail','Same city as the buyer'); end if;
    if r.f_mfr then reasons := reasons || jsonb_build_object('factor','manufacturer','points',5,'detail','Listed as a manufacturer'); end if;
    elig := public._company_lead_eligible(r.id, e.category_id);
    if elig and direct_n < s.max_direct_per_requirement then route_v := 'direct';
    else route_v := 'admin';
      if elig then capped := true; reasons := reasons || jsonb_build_object('factor','cap','points',0,'detail','Eligible, but the per-requirement direct delivery cap was reached; staff to review');
      elsif r.claim_status = 'approved' then unverified := true; reasons := reasons || jsonb_build_object('factor','not_eligible','points',0,'detail','Claimed but not verified or otherwise not eligible for direct leads');
      else unclaimed := true; reasons := reasons || jsonb_build_object('factor','unclaimed','points',0,'detail','Unclaimed business: managed by the admin lead desk');
      end if;
    end if;
    insert into public.requirement_matches(enquiry_id, company_id, score, reasons, route) values (p_enq, r.id, r.score, reasons, route_v)
      on conflict (enquiry_id, company_id) do update set score = excluded.score, reasons = excluded.reasons, route = excluded.route
      where public.requirement_matches.route = 'admin' and excluded.route = 'direct';
    if route_v = 'direct' then
      insert into public.lead_distribution_events(enquiry_id, company_id, event, reason) values (p_enq, r.id, 'delivered_direct', 'verified eligible seller') on conflict do nothing;
      get diagnostics ins = row_count;
      if ins > 0 then
        direct_n := direct_n + 1;
        insert into public.notifications(user_id, company_id, kind, title, body, link)
          select m2.user_id, r.id, 'lead', 'New buyer requirement', left(d.product_required, 120), '#leads' from public.company_members m2 where m2.company_id = r.id and m2.status = 'active' and m2.role in ('owner','manager','sales');
      end if;
    else
      insert into public.lead_distribution_events(enquiry_id, company_id, event, reason) values (p_enq, r.id, 'routed_admin', left(reasons->(jsonb_array_length(reasons)-1)->>'detail', 200)) on conflict do nothing;
    end if;
  end loop;
  -- admin lead desk entry for anything not fully handled by direct delivery
  if total_n = 0 then q := 'unmatched';
    insert into public.lead_distribution_events(enquiry_id, event, reason) values (p_enq, 'no_match', 'no supplier reached the minimum score') on conflict do nothing;
  elsif exists(select 1 from public.requirement_matches where enquiry_id = p_enq and route = 'admin') then
    q := case when unclaimed then 'unclaimed_matches' when unverified then 'unverified_matches' else 'capped_eligible' end;
  end if;
  if q is not null then
    insert into public.lead_cases(enquiry_id, queue) values (p_enq, q) on conflict (enquiry_id) do update set queue = excluded.queue, updated_at = now();
  end if;
  update public.enquiries set delivery = case when direct_n > 0 then 'visible_to_seller'::public.enquiry_delivery else 'awaiting_admin'::public.enquiry_delivery end where id = p_enq;
end $$;


ALTER FUNCTION public._match_requirement(p_enq uuid) OWNER TO postgres;

--
-- Name: admin_approve_invitation(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_approve_invitation(p_inv uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update public.claim_invitations set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_inv and status = 'draft'; if not found then raise exception 'invitation not in draft'; end if; end $$;


ALTER FUNCTION public.admin_approve_invitation(p_inv uuid) OWNER TO postgres;

--
-- Name: admin_assign_lead(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_assign_lead(p_case uuid, p_staff uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if not exists(select 1 from public.profiles where id = p_staff and app_role in ('admin','reviewer')) then raise exception 'assignee is not staff'; end if;
  perform set_config('app.lead_note', 'assigned by admin', true);
  update public.lead_cases set assigned_to = p_staff, assigned_at = now(), status = case when status = 'new' then 'assigned' else status end, updated_at = now() where id = p_case;
  if not found then raise exception 'case not found'; end if;
end $$;


ALTER FUNCTION public.admin_assign_lead(p_case uuid, p_staff uuid) OWNER TO postgres;

--
-- Name: admin_lead_overview(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_lead_overview() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return jsonb_build_object(
    'new_requirements', (select count(*) from public.lead_cases where status = 'new'),
    'unmatched', (select count(*) from public.lead_cases where queue = 'unmatched' and status <> 'closed'),
    'matched_unclaimed', (select count(*) from public.lead_cases where queue = 'unclaimed_matches' and status <> 'closed'),
    'matched_registered_direct', (select count(distinct enquiry_id) from public.lead_distribution_events where event = 'delivered_direct'),
    'calls_pending', (select count(*) from public.lead_cases where status in ('assigned','contact_pending')),
    'follow_ups_due_today', (select count(*) from public.lead_cases where status <> 'closed' and next_follow_up_at < date_trunc('day', now()) + interval '1 day'),
    'claims_awaiting_approval', (select count(*) from public.company_claims where status in ('claim_submitted','under_review','evidence_requested')),
    'sellers_activated', (select count(*) from public.lead_cases where status = 'seller_activated'));
end $$;


ALTER FUNCTION public.admin_lead_overview() OWNER TO postgres;

--
-- Name: admin_rematch(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_rematch(p_enquiry uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if; perform public._match_requirement(p_enquiry); end $$;


ALTER FUNCTION public.admin_rematch(p_enquiry uuid) OWNER TO postgres;

--
-- Name: admin_rematch_for_company(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_rematch_for_company(p_company uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare r record; n integer := 0;
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  for r in select distinct rm.enquiry_id from public.requirement_matches rm join public.enquiries e on e.id = rm.enquiry_id where rm.company_id = p_company and rm.route = 'admin' and e.status not in ('closed','spam') loop
    perform public._match_requirement(r.enquiry_id); n := n + 1; end loop; return n; end $$;


ALTER FUNCTION public.admin_rematch_for_company(p_company uuid) OWNER TO postgres;

--
-- Name: admin_set_routing_settings(integer, integer, boolean, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.admin_set_routing_settings(p_min_score integer, p_max_direct integer, p_req_email boolean, p_req_phone boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update public.lead_routing_settings set min_score = p_min_score, max_direct_per_requirement = p_max_direct, require_verified_email = p_req_email, require_verified_phone = p_req_phone, updated_by = auth.uid(), updated_at = now() where id = 1; end $$;


ALTER FUNCTION public.admin_set_routing_settings(p_min_score integer, p_max_direct integer, p_req_email boolean, p_req_phone boolean) OWNER TO postgres;

--
-- Name: block_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.block_mutation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$ begin raise exception 'immutable'; end $$;


ALTER FUNCTION public.block_mutation() OWNER TO postgres;

--
-- Name: buyer_requirement_status(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.buyer_requirement_status(p_enquiry uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare n integer;
begin
  if public.enquiry_buyer(p_enquiry) is distinct from auth.uid() then raise exception 'not your requirement' using errcode = '42501'; end if;
  select count(*) into n from public.lead_distribution_events where enquiry_id = p_enquiry and event = 'delivered_direct';
  return jsonb_build_object('delivered_to_verified_suppliers', n,
    'being_handled_by_team', exists(select 1 from public.lead_cases where enquiry_id = p_enquiry and status <> 'closed'),
    'message', case when n > 0 then 'Sent to ' || n || ' verified supplier(s).' else 'Received. Our team is looking for suitable suppliers. No supplier has received it yet.' end);
end $$;


ALTER FUNCTION public.buyer_requirement_status(p_enquiry uuid) OWNER TO postgres;

--
-- Name: check_rate(text, integer, interval); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ begin if (select count(*) from rate_events where user_id=auth.uid() and action=p_action and at>now()-p_window)>=p_max then raise exception 'rate limit'; end if; insert into rate_events(user_id,action) values (auth.uid(),p_action); end $$;


ALTER FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) OWNER TO postgres;

--
-- Name: claim_claimant(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.claim_claimant(cid uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select claimant_id from company_claims where id=cid $$;


ALTER FUNCTION public.claim_claimant(cid uuid) OWNER TO postgres;

--
-- Name: claim_is_open_for_me(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.claim_is_open_for_me(cid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_claims where id=cid and claimant_id=auth.uid() and status in ('claim_submitted','evidence_requested','under_review')) $$;


ALTER FUNCTION public.claim_is_open_for_me(cid uuid) OWNER TO postgres;

--
-- Name: claim_verification_summary(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.claim_verification_summary(p_claim uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare cl public.company_claims;
begin
  select * into cl from public.company_claims where id = p_claim; if not found then raise exception 'not found'; end if;
  if cl.claimant_id is distinct from auth.uid() and not public.staff_can_access_company(cl.company_id, null, p_claim) then raise exception 'not authorised' using errcode = '42501'; end if;
  return jsonb_build_object(
    'email_verified', exists(select 1 from public.claim_verifications where claim_id = p_claim and channel = 'email' and verified_at is not null),
    'phone_verified', exists(select 1 from public.claim_verifications where claim_id = p_claim and channel = 'phone' and verified_at is not null),
    'email_domain_matches_website', exists(select 1 from public.claim_verifications where claim_id = p_claim and channel = 'email' and verified_at is not null and domain_matches_website),
    'conflicting_open_claims', (select count(*) from public.company_claims o where o.company_id = cl.company_id and o.id <> cl.id and o.claimant_id <> cl.claimant_id and o.status in ('claim_submitted','evidence_requested','under_review')));
end $$;


ALTER FUNCTION public.claim_verification_summary(p_claim uuid) OWNER TO postgres;

--
-- Name: confirm_claim_verification(uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.confirm_claim_verification(p_claim uuid, p_channel text, p_code text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare r public.claim_verifications;
begin
  if not exists(select 1 from public.company_claims where id = p_claim and claimant_id = auth.uid()) then raise exception 'not your claim' using errcode = '42501'; end if;
  select * into r from public.claim_verifications where claim_id = p_claim and channel = p_channel and verified_at is null order by created_at desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_pending_verification'); end if;
  if r.expires_at <= now() then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;
  if r.attempts >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_attempts'); end if;
  if r.code_hash is distinct from digest(coalesce(trim(p_code),'') || ':' || r.id::text, 'sha256') then
    update public.claim_verifications set attempts = attempts + 1 where id = r.id;
    return jsonb_build_object('ok', false, 'reason', 'incorrect_code'); end if;
  update public.claim_verifications set verified_at = now() where id = r.id;
  delete from public.claim_verification_outbox where verification_id = r.id;
  return jsonb_build_object('ok', true);
end $$;


ALTER FUNCTION public.confirm_claim_verification(p_claim uuid, p_channel text, p_code text) OWNER TO postgres;

--
-- Name: create_requirement(uuid, text, text, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_requirement(p_enquiry uuid, p_product text, p_material text, p_size text, p_quality text, p_specs text, p_destination text, p_timeline text, p_additional text, p_contact_pref text DEFAULT 'either'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare e public.enquiries; norm text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '28000'; end if;
  select * into e from public.enquiries where id = p_enquiry and kind = 'requirement';
  if not found or e.buyer_id <> auth.uid() then raise exception 'not your requirement' using errcode = '42501'; end if;
  perform public.check_rate('requirement', 10, interval '1 day');
  norm := lower(regexp_replace(trim(coalesce(p_product,'')), '\s+', ' ', 'g'));
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text || norm));
  if exists(select 1 from public.requirement_details x where x.buyer_id = auth.uid() and x.product_norm = norm and coalesce(x.destination_country,'') = coalesce(trim(p_destination),'') and x.created_at > now() - interval '24 hours') then
    raise exception 'duplicate requirement'; end if;
  insert into public.requirement_details(enquiry_id, buyer_id, product_required, material, size, quality, specifications, destination_country, delivery_timeline, additional, contact_pref)
    values (p_enquiry, auth.uid(), p_product, left(p_material,200), left(p_size,200), left(p_quality,300), left(p_specs,2000), left(trim(p_destination),100), left(p_timeline,200), left(p_additional,2000), coalesce(p_contact_pref,'either'));
  perform public._match_requirement(p_enquiry);
  return public.buyer_requirement_status(p_enquiry);
end $$;


ALTER FUNCTION public.create_requirement(p_enquiry uuid, p_product text, p_material text, p_size text, p_quality text, p_specs text, p_destination text, p_timeline text, p_additional text, p_contact_pref text) OWNER TO postgres;

--
-- Name: enquiry_buyer(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enquiry_buyer(eid uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select buyer_id from enquiries where id=eid $$;


ALTER FUNCTION public.enquiry_buyer(eid uuid) OWNER TO postgres;

--
-- Name: has_company_role(uuid, public.member_role[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active' and m.role=any(roles)) $$;


ALTER FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) OWNER TO postgres;

--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from profiles where id=auth.uid() and app_role='admin') $$;


ALTER FUNCTION public.is_admin() OWNER TO postgres;

--
-- Name: is_company_member(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_company_member(cid uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from company_members m where m.company_id=cid and m.user_id=auth.uid() and m.status='active') $$;


ALTER FUNCTION public.is_company_member(cid uuid) OWNER TO postgres;

--
-- Name: is_staff(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_staff() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ select exists(select 1 from profiles where id=auth.uid() and app_role in ('admin','reviewer')) $$;


ALTER FUNCTION public.is_staff() OWNER TO postgres;

--
-- Name: lead_matches_my_company(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.lead_matches_my_company(cat integer) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists(select 1 from public.company_members m where m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner','manager','sales') and public._company_lead_eligible(m.company_id, cat))
$$;


ALTER FUNCTION public.lead_matches_my_company(cat integer) OWNER TO postgres;

--
-- Name: norm_domain(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.norm_domain(t text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $_$ select lower(regexp_replace(regexp_replace(coalesce(t,''),'^https?://(www\.)?',''),'[/:?#].*$','')) $_$;


ALTER FUNCTION public.norm_domain(t text) OWNER TO postgres;

--
-- Name: redeem_invitation(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.redeem_invitation(p_token text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare i public.claim_invitations;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '28000'; end if;
  perform public.check_rate('invite_redeem', 5, interval '1 hour');
  select * into i from public.claim_invitations where token_hash = digest(coalesce(p_token,''), 'sha256') and status = 'sent_manual' and expires_at > now();
  if not found then raise exception 'invalid or expired invitation'; end if;
  update public.claim_invitations set status = 'redeemed', redeemed_by = auth.uid(), redeemed_at = now() where id = i.id;
  return i.company_id;  -- the caller must still use submit_claim(); an invitation approves nothing
end $$;


ALTER FUNCTION public.redeem_invitation(p_token text) OWNER TO postgres;

--
-- Name: review_claim(uuid, public.claim_status, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ begin if not is_staff() then raise exception 'staff only'; end if; update company_claims set status=p_decision, decided_by=auth.uid(), decided_at=now(), decision_reason=p_reason where id=p_claim; if p_decision='approved' then update companies set claim_status='approved' where id=(select company_id from company_claims where id=p_claim); end if; end $$;


ALTER FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) OWNER TO postgres;

--
-- Name: safe_uuid(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.safe_uuid(t text) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$ begin return t::uuid; exception when others then return null; end $$;


ALTER FUNCTION public.safe_uuid(t text) OWNER TO postgres;

--
-- Name: seller_can_see_leads(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seller_can_see_leads() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists(select 1 from public.company_members m where m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner','manager','sales') and public._company_lead_eligible(m.company_id, null))
$$;


ALTER FUNCTION public.seller_can_see_leads() OWNER TO postgres;

--
-- Name: seller_lead_visible(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seller_lead_visible(p_enq uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists(select 1 from public.requirement_matches rm where rm.enquiry_id = p_enq and public.seller_match_visible(rm.company_id, p_enq))
$$;


ALTER FUNCTION public.seller_lead_visible(p_enq uuid) OWNER TO postgres;

--
-- Name: seller_match_visible(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.seller_match_visible(p_company uuid, p_enq uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists(select 1 from public.requirement_matches rm join public.enquiries e on e.id = rm.enquiry_id
    join public.company_members m on m.company_id = rm.company_id and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner','manager','sales')
    where rm.enquiry_id = p_enq and rm.company_id = p_company and rm.route = 'direct' and public._company_lead_eligible(rm.company_id, e.category_id))
$$;


ALTER FUNCTION public.seller_match_visible(p_company uuid, p_enq uuid) OWNER TO postgres;

--
-- Name: staff_add_contact(uuid, text, text, public.source_type, text, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_add_contact(p_company uuid, p_kind text, p_value text, p_source_type public.source_type, p_source_name text, p_source_url text DEFAULT NULL::text, p_purpose text DEFAULT NULL::text, p_case uuid DEFAULT NULL::uuid, p_claim uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
declare v text := trim(p_value); cid uuid;
begin
  if not public.is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  if not public.staff_can_access_company(p_company, p_case, p_claim) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if coalesce(trim(p_purpose),'') = '' then raise exception 'purpose required'; end if;
  if p_kind not in ('email','phone') then raise exception 'invalid kind'; end if;
  if p_kind = 'email' and v !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email'; end if;
  if p_kind = 'phone' and v !~ '^[0-9+\-\s()]{7,20}$' then raise exception 'invalid phone'; end if;
  if coalesce(trim(p_source_name),'') = '' then raise exception 'source required'; end if;
  insert into public.company_contacts(company_id, kind, value, source_type, source_name, source_url, created_by) values (p_company, p_kind, v, p_source_type, p_source_name, p_source_url, auth.uid()) returning id into cid;
  insert into public.contact_access_log(actor_id, action, company_id, contact_id, purpose, lead_case_id, claim_id) values (auth.uid(), 'add', p_company, cid, left(p_purpose,200), p_case, p_claim);
  return cid;
end $_$;


ALTER FUNCTION public.staff_add_contact(p_company uuid, p_kind text, p_value text, p_source_type public.source_type, p_source_name text, p_source_url text, p_purpose text, p_case uuid, p_claim uuid) OWNER TO postgres;

--
-- Name: staff_can_access_company(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_can_access_company(p_company uuid, p_case uuid DEFAULT NULL::uuid, p_claim uuid DEFAULT NULL::uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select public.is_admin() or (public.is_staff() and (
    (p_case is not null and exists(select 1 from public.lead_cases lc join public.requirement_matches rm on rm.enquiry_id = lc.enquiry_id
        where lc.id = p_case and lc.assigned_to = auth.uid() and rm.company_id = p_company and rm.route = 'admin'))
    or (p_claim is not null and exists(select 1 from public.company_claims cl where cl.id = p_claim and cl.company_id = p_company
        and cl.status in ('claim_submitted','evidence_requested','under_review')))))
$$;


ALTER FUNCTION public.staff_can_access_company(p_company uuid, p_case uuid, p_claim uuid) OWNER TO postgres;

--
-- Name: staff_can_review_claim(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_can_review_claim(p_claim uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.company_claims c where c.id = p_claim and c.status in ('claim_submitted','evidence_requested','under_review')))
$$;


ALTER FUNCTION public.staff_can_review_claim(p_claim uuid) OWNER TO postgres;

--
-- Name: staff_can_see_case(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_can_see_case(p_case uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.lead_cases lc where lc.id = p_case and lc.assigned_to = auth.uid()))
$$;


ALTER FUNCTION public.staff_can_see_case(p_case uuid) OWNER TO postgres;

--
-- Name: staff_can_see_enquiry(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_can_see_enquiry(p_enq uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.lead_cases lc where lc.enquiry_id = p_enq and lc.assigned_to = auth.uid()))
$$;


ALTER FUNCTION public.staff_can_see_enquiry(p_enq uuid) OWNER TO postgres;

--
-- Name: staff_create_invitation(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare k public.company_contacts; tok text; iid uuid;
begin
  if not public.is_staff() or not public.staff_can_access_company(p_company, p_case, null) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if coalesce(trim(p_purpose),'') = '' then raise exception 'purpose required'; end if;
  select * into k from public.company_contacts where id = p_contact and company_id = p_company;
  if not found or k.kind <> 'email' or k.status in ('invalid','do_not_contact') then raise exception 'contact not usable for an invitation'; end if;
  if exists(select 1 from public.company_acquisition where company_id = p_company and acquisition_status = 'do_not_contact') then raise exception 'supplier is marked do-not-contact'; end if;
  if exists(select 1 from public.companies where id = p_company and claim_status = 'approved') then raise exception 'company already claimed'; end if;
  perform public.check_rate('invite', 20, interval '1 day');
  tok := encode(gen_random_bytes(24), 'hex');
  insert into public.claim_invitations(company_id, contact_id, case_id, created_by, token_hash) values (p_company, p_contact, p_case, auth.uid(), digest(tok, 'sha256')) returning id into iid;
  insert into public.contact_access_log(actor_id, action, company_id, contact_id, purpose, lead_case_id) values (auth.uid(), 'view', p_company, p_contact, 'claim invitation: ' || left(p_purpose,150), p_case);
  return jsonb_build_object('invitation_id', iid, 'token', tok, 'note', 'token is shown once; invitation needs admin approval before it can be marked sent');
end $$;


ALTER FUNCTION public.staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text) OWNER TO postgres;

--
-- Name: staff_get_contacts(uuid, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_get_contacts(p_company uuid, p_purpose text, p_case uuid DEFAULT NULL::uuid, p_claim uuid DEFAULT NULL::uuid) RETURNS TABLE(id uuid, kind text, value text, status text, source_name text, source_url text, last_verified_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  if not public.staff_can_access_company(p_company, p_case, p_claim) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if coalesce(trim(p_purpose),'') = '' then raise exception 'purpose required'; end if;
  insert into public.contact_access_log(actor_id, action, company_id, purpose, lead_case_id, claim_id) values (auth.uid(), 'view', p_company, left(p_purpose,200), p_case, p_claim);
  return query select c.id, c.kind, case when c.status = 'do_not_contact' then null else c.value end, c.status, c.source_name, c.source_url, c.last_verified_at
    from public.company_contacts c where c.company_id = p_company order by c.kind, c.created_at;
end $$;


ALTER FUNCTION public.staff_get_contacts(p_company uuid, p_purpose text, p_case uuid, p_claim uuid) OWNER TO postgres;

--
-- Name: staff_log_call(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_log_call(p_case uuid, p_company uuid, p_summary text, p_outcome text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare id uuid;
begin
  if not public.staff_can_access_company(p_company, p_case, null) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if exists(select 1 from public.company_acquisition where company_id = p_company and acquisition_status = 'do_not_contact') then raise exception 'supplier is marked do-not-contact'; end if;
  insert into public.company_outreach_events(company_id, event_type, channel, summary, outcome, delivery, recorded_by) values (p_company, 'call', 'phone', left(p_summary,1000), left(p_outcome,200), 'logged_manual', auth.uid()) returning company_outreach_events.id into id;
  return id;
end $$;


ALTER FUNCTION public.staff_log_call(p_case uuid, p_company uuid, p_summary text, p_outcome text) OWNER TO postgres;

--
-- Name: staff_mark_enquiry(uuid, public.enquiry_delivery, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.is_staff() or not public.staff_can_see_enquiry(p_enquiry) then raise exception 'staff only' using errcode = '42501'; end if;
  if p_delivery = 'sent_external' and coalesce(trim(p_provider_ref),'') = '' then raise exception 'sent_external requires a provider reference'; end if;
  update public.enquiries set delivery = p_delivery, delivery_note = left(coalesce(p_note,'') || case when p_provider_ref is not null then ' [ref ' || p_provider_ref || ']' else '' end, 500) where id = p_enquiry;
  if not found then raise exception 'enquiry not found'; end if;
end $$;


ALTER FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) OWNER TO postgres;

--
-- Name: staff_mark_invitation_sent(uuid, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_mark_invitation_sent(p_inv uuid, p_provider_ref text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare i public.claim_invitations;
begin
  select * into i from public.claim_invitations where id = p_inv; if not found then raise exception 'not found'; end if;
  if not (public.is_admin() or (public.is_staff() and i.created_by = auth.uid())) then raise exception 'not authorised' using errcode = '42501'; end if;
  if i.status <> 'approved' then raise exception 'invitation must be approved by an admin first'; end if;
  update public.claim_invitations set status = 'sent_manual', sent_at = now(), delivery = case when coalesce(trim(p_provider_ref),'') <> '' then 'sent'::public.outreach_delivery else 'logged_manual'::public.outreach_delivery end, provider_ref = nullif(trim(p_provider_ref),'') where id = p_inv;
  insert into public.company_outreach_events(company_id, event_type, channel, summary, delivery, provider_ref, recorded_by) values (i.company_id, 'invitation', 'email', 'claim invitation marked sent', case when coalesce(trim(p_provider_ref),'') <> '' then 'sent'::public.outreach_delivery else 'logged_manual'::public.outreach_delivery end, nullif(trim(p_provider_ref),''), auth.uid());
  if i.case_id is not null then perform set_config('app.lead_note', 'claim invitation marked sent', true); update public.lead_cases set status = 'claim_invitation_sent', updated_at = now() where id = i.case_id and status not in ('closed','seller_activated'); end if;
end $$;


ALTER FUNCTION public.staff_mark_invitation_sent(p_inv uuid, p_provider_ref text) OWNER TO postgres;

--
-- Name: staff_my_leads(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_my_leads() RETURNS TABLE(case_id uuid, enquiry_id uuid, queue text, status public.lead_status, product text, quantity numeric, unit text, destination text, next_follow_up_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select lc.id, lc.enquiry_id, lc.queue, lc.status, d.product_required, e.quantity, e.unit, d.destination_country, lc.next_follow_up_at
  from public.lead_cases lc join public.enquiries e on e.id = lc.enquiry_id left join public.requirement_details d on d.enquiry_id = lc.enquiry_id
  where public.is_staff() and lc.assigned_to = auth.uid() order by lc.next_follow_up_at nulls last, lc.created_at
$$;


ALTER FUNCTION public.staff_my_leads() OWNER TO postgres;

--
-- Name: staff_set_contact_status(uuid, text, text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_set_contact_status(p_contact uuid, p_status text, p_purpose text, p_case uuid DEFAULT NULL::uuid, p_claim uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
declare cc public.company_contacts;
begin
  if not public.is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  select * into cc from public.company_contacts where id = p_contact; if not found then raise exception 'not found'; end if;
  if not public.staff_can_access_company(cc.company_id, p_case, p_claim) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if coalesce(trim(p_purpose),'') = '' then raise exception 'purpose required'; end if;
  if p_status not in ('unverified','verified','invalid','do_not_contact') then raise exception 'invalid status'; end if;
  if cc.status = 'do_not_contact' and not public.is_admin() then raise exception 'only admin can clear do-not-contact'; end if;
  update public.company_contacts set status = p_status,
    last_verified_at = case when p_status = 'verified' then now() else last_verified_at end,
    verified_by = case when p_status = 'verified' then auth.uid() else verified_by end where id = p_contact;
  if p_status = 'do_not_contact' then
    insert into public.company_acquisition(company_id, acquisition_status) values (cc.company_id, 'do_not_contact') on conflict (company_id) do update set acquisition_status = 'do_not_contact', updated_at = now();
  end if;
  insert into public.contact_access_log(actor_id, action, company_id, contact_id, purpose, lead_case_id, claim_id) values (auth.uid(), 'set_status', cc.company_id, p_contact, left(p_purpose,200), p_case, p_claim);
end $$;


ALTER FUNCTION public.staff_set_contact_status(p_contact uuid, p_status text, p_purpose text, p_case uuid, p_claim uuid) OWNER TO postgres;

--
-- Name: staff_update_lead(uuid, public.lead_status, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.staff_update_lead(p_case uuid, p_status public.lead_status, p_note text, p_next_follow_up timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
begin
  if not public.staff_can_see_case(p_case) then raise exception 'not assigned to you' using errcode = '42501'; end if;
  perform set_config('app.lead_note', left(coalesce(p_note,''), 500), true);
  update public.lead_cases set status = p_status, next_follow_up_at = coalesce(p_next_follow_up, next_follow_up_at), updated_at = now(), closed_at = case when p_status = 'closed' then now() else null end where id = p_case;
end $$;


ALTER FUNCTION public.staff_update_lead(p_case uuid, p_status public.lead_status, p_note text, p_next_follow_up timestamp with time zone) OWNER TO postgres;

--
-- Name: start_claim_verification(uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.start_claim_verification(p_claim uuid, p_channel text, p_target text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
declare cl public.company_claims; v text := trim(p_target); code text; vid uuid; exp timestamptz; dm boolean; site text;
begin
  select * into cl from public.company_claims where id = p_claim;
  if not found or cl.claimant_id is distinct from auth.uid() or cl.status not in ('claim_submitted','evidence_requested','under_review') then raise exception 'not your open claim' using errcode = '42501'; end if;
  if p_channel not in ('email','phone') then raise exception 'invalid channel'; end if;
  if p_channel = 'email' and v !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'invalid email'; end if;
  if p_channel = 'phone' and v !~ '^[0-9+\-\s()]{7,20}$' then raise exception 'invalid phone'; end if;
  perform public.check_rate('claim_verify', 5, interval '1 hour');
  update public.claim_verifications set expires_at = now() where claim_id = p_claim and channel = p_channel and verified_at is null and expires_at > now();
  if p_channel = 'email' then code := encode(gen_random_bytes(16), 'hex'); exp := now() + interval '24 hours';
    select public.norm_domain(website) into site from public.companies where id = cl.company_id;
    dm := coalesce(site,'') <> '' and lower(split_part(v,'@',2)) = site;
  else code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0'); exp := now() + interval '10 minutes'; end if;
  insert into public.claim_verifications(claim_id, channel, target, domain_matches_website, code_hash, expires_at, id)
    values (p_claim, p_channel, lower(v), dm, digest(code, 'sha256'), exp, gen_random_uuid()) returning id into vid;
  update public.claim_verifications set code_hash = digest(code || ':' || vid::text, 'sha256') where id = vid;
  insert into public.claim_verification_outbox(verification_id, channel, target, code, expires_at) values (vid, p_channel, lower(v), code, exp);
  return jsonb_build_object('verification_id', vid, 'expires_at', exp, 'delivery', 'queued (delivery provider not enabled)');
end $_$;


ALTER FUNCTION public.start_claim_verification(p_claim uuid, p_channel text, p_target text) OWNER TO postgres;

--
-- Name: submit_claim(uuid, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$ declare cl uuid; begin insert into company_claims(company_id,claimant_id,claimant_role_title,statement) values (p_company,auth.uid(),p_title,p_statement) returning id into cl; return cl; end $$;


ALTER FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) OWNER TO postgres;

--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: postgres
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$ select string_to_array(name,'/') $$;


ALTER FUNCTION storage.foldername(name text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    actor_id uuid,
    actor_role text,
    action text,
    entity text,
    entity_id text,
    old_value jsonb,
    new_value jsonb,
    at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.audit_log OWNER TO postgres;

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    slug text,
    name text,
    hue integer,
    spec_template jsonb,
    hidden boolean DEFAULT false,
    "position" integer,
    parent_id integer
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categories_id_seq OWNER TO postgres;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: claim_invitations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.claim_invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    case_id uuid,
    created_by uuid NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    token_hash bytea NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '14 days'::interval) NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    delivery public.outreach_delivery DEFAULT 'logged_manual'::public.outreach_delivery NOT NULL,
    provider_ref text,
    sent_at timestamp with time zone,
    redeemed_by uuid,
    redeemed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT claim_invitations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'sent_manual'::text, 'redeemed'::text, 'expired'::text, 'cancelled'::text])))
);


ALTER TABLE public.claim_invitations OWNER TO postgres;

--
-- Name: claim_verification_outbox; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.claim_verification_outbox (
    verification_id uuid NOT NULL,
    channel text NOT NULL,
    target text NOT NULL,
    code text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT claim_verification_outbox_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'sent'::text, 'failed'::text])))
);


ALTER TABLE public.claim_verification_outbox OWNER TO postgres;

--
-- Name: TABLE claim_verification_outbox; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.claim_verification_outbox IS 'class=system; plaintext one-time codes awaiting an (unapproved) delivery provider. service_role only. Rows are deleted on successful verification.';


--
-- Name: claim_verifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.claim_verifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    claim_id uuid NOT NULL,
    channel text NOT NULL,
    target text NOT NULL,
    domain_matches_website boolean,
    code_hash bytea NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    attempts smallint DEFAULT 0 NOT NULL,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT claim_verifications_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'phone'::text])))
);


ALTER TABLE public.claim_verifications OWNER TO postgres;

--
-- Name: companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text,
    name text NOT NULL,
    business_type text,
    about text,
    city text,
    state text,
    country text,
    website text,
    logo_path text,
    directory_status public.directory_status DEFAULT 'draft'::public.directory_status NOT NULL,
    claim_status public.claim_status DEFAULT 'unclaimed'::public.claim_status NOT NULL,
    verification_status public.verification_status DEFAULT 'not_verified'::public.verification_status NOT NULL,
    verified_at timestamp with time zone,
    verified_by uuid,
    data_review_status public.review_status DEFAULT 'pending'::public.review_status NOT NULL,
    data_reviewed_by uuid,
    data_reviewed_at timestamp with time zone,
    dedupe_key text,
    import_batch_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    is_demo boolean DEFAULT false NOT NULL,
    business_types text[] DEFAULT '{}'::text[] NOT NULL,
    export_markets text[] DEFAULT '{}'::text[] NOT NULL,
    capabilities text,
    lead_delivery_blocked boolean DEFAULT false NOT NULL,
    CONSTRAINT companies_business_types_valid CHECK ((business_types <@ ARRAY['manufacturer'::text, 'wholesaler'::text, 'distributor'::text, 'exporter'::text, 'importer'::text, 'trader'::text, 'supplier'::text, 'service_provider'::text]))
);


ALTER TABLE public.companies OWNER TO postgres;

--
-- Name: company_acquisition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_acquisition (
    company_id uuid NOT NULL,
    acquisition_status public.acquisition_status DEFAULT 'not_contacted'::public.acquisition_status,
    last_contacted_at timestamp with time zone,
    next_follow_up_at timestamp with time zone,
    contact_channel text,
    contact_outcome text,
    owner_id uuid,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_acquisition OWNER TO postgres;

--
-- Name: company_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_categories (
    company_id uuid NOT NULL,
    category_id integer NOT NULL
);


ALTER TABLE public.company_categories OWNER TO postgres;

--
-- Name: company_claim_evidence; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_claim_evidence (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    claim_id uuid,
    storage_path text,
    description text,
    uploaded_by uuid,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_claim_evidence OWNER TO postgres;

--
-- Name: company_claims; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    claimant_id uuid,
    claimant_role_title text,
    statement text,
    status public.claim_status DEFAULT 'claim_submitted'::public.claim_status NOT NULL,
    decided_by uuid,
    decided_at timestamp with time zone,
    decision_reason text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_claims OWNER TO postgres;

--
-- Name: company_contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    kind text NOT NULL,
    value text NOT NULL,
    value_norm text GENERATED ALWAYS AS (lower(TRIM(BOTH FROM value))) STORED,
    status text DEFAULT 'unverified'::text NOT NULL,
    source_type public.source_type NOT NULL,
    source_name text NOT NULL,
    source_url text,
    collected_at timestamp with time zone DEFAULT now() NOT NULL,
    last_verified_at timestamp with time zone,
    verified_by uuid,
    legal_basis text DEFAULT 'legitimate_interest_b2b_public'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT company_contacts_kind_check CHECK ((kind = ANY (ARRAY['phone'::text, 'email'::text]))),
    CONSTRAINT company_contacts_status_check CHECK ((status = ANY (ARRAY['unverified'::text, 'verified'::text, 'invalid'::text, 'do_not_contact'::text]))),
    CONSTRAINT company_contacts_value_check CHECK (((length(value) >= 5) AND (length(value) <= 200)))
);


ALTER TABLE public.company_contacts OWNER TO postgres;

--
-- Name: TABLE company_contacts; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.company_contacts IS 'class=private; business contacts. No anon/buyer/staff direct access. Staff read only via staff_get_contacts() (purpose + assignment + immutable audit). Company owner/manager may read their own.';


--
-- Name: company_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    user_id uuid,
    invite_email text,
    role public.member_role NOT NULL,
    status public.member_status DEFAULT 'active'::public.member_status NOT NULL,
    invited_by uuid,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_members OWNER TO postgres;

--
-- Name: company_outreach_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_outreach_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    event_type public.outreach_type NOT NULL,
    channel text,
    summary text,
    outcome text,
    delivery public.outreach_delivery DEFAULT 'logged_manual'::public.outreach_delivery NOT NULL,
    provider_ref text,
    occurred_at timestamp with time zone DEFAULT now(),
    recorded_by uuid
);


ALTER TABLE public.company_outreach_events OWNER TO postgres;

--
-- Name: company_private; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.company_private (
    company_id uuid NOT NULL,
    phone text,
    email text,
    address text,
    pin text,
    contact_person text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.company_private OWNER TO postgres;

--
-- Name: contact_access_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contact_access_log (
    id bigint NOT NULL,
    actor_id uuid NOT NULL,
    action text NOT NULL,
    company_id uuid NOT NULL,
    contact_id uuid,
    purpose text NOT NULL,
    lead_case_id uuid,
    claim_id uuid,
    at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT contact_access_log_action_check CHECK ((action = ANY (ARRAY['view'::text, 'add'::text, 'set_status'::text]))),
    CONSTRAINT contact_access_log_purpose_check CHECK ((length(TRIM(BOTH FROM purpose)) > 0))
);


ALTER TABLE public.contact_access_log OWNER TO postgres;

--
-- Name: TABLE contact_access_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.contact_access_log IS 'class=staff; immutable audit of contact-vault view/add/status change, with related lead case or claim.';


--
-- Name: contact_access_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.contact_access_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.contact_access_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: enquiries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enquiries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ref text,
    kind public.enquiry_kind NOT NULL,
    buyer_id uuid NOT NULL,
    product_id uuid,
    company_id uuid,
    category_id integer,
    subject text,
    quantity numeric(14,2),
    unit text,
    message text,
    city text,
    status public.enquiry_status DEFAULT 'new'::public.enquiry_status NOT NULL,
    delivery public.enquiry_delivery DEFAULT 'stored'::public.enquiry_delivery NOT NULL,
    delivery_note text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.enquiries OWNER TO postgres;

--
-- Name: enquiry_private; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enquiry_private (
    enquiry_id uuid NOT NULL,
    buyer_name text,
    buyer_phone text,
    buyer_email text,
    buyer_company text,
    consent_at timestamp with time zone,
    notice_version text
);


ALTER TABLE public.enquiry_private OWNER TO postgres;

--
-- Name: lead_cases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_cases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enquiry_id uuid NOT NULL,
    queue text NOT NULL,
    status public.lead_status DEFAULT 'new'::public.lead_status NOT NULL,
    assigned_to uuid,
    assigned_at timestamp with time zone,
    next_follow_up_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT lead_cases_queue_check CHECK ((queue = ANY (ARRAY['unclaimed_matches'::text, 'unverified_matches'::text, 'capped_eligible'::text, 'unmatched'::text])))
);


ALTER TABLE public.lead_cases OWNER TO postgres;

--
-- Name: lead_distribution_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_distribution_events (
    id bigint NOT NULL,
    enquiry_id uuid NOT NULL,
    company_id uuid,
    case_id uuid,
    event text NOT NULL,
    reason text,
    actor_id uuid,
    at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lead_distribution_events_event_check CHECK ((event = ANY (ARRAY['delivered_direct'::text, 'routed_admin'::text, 'no_match'::text])))
);


ALTER TABLE public.lead_distribution_events OWNER TO postgres;

--
-- Name: lead_distribution_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_distribution_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.lead_distribution_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lead_routing_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_routing_settings (
    id integer DEFAULT 1 NOT NULL,
    min_score integer DEFAULT 40 NOT NULL,
    max_direct_per_requirement integer DEFAULT 5 NOT NULL,
    require_verified_email boolean DEFAULT true NOT NULL,
    require_verified_phone boolean DEFAULT true NOT NULL,
    contact_max_age_days integer DEFAULT 365 NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lead_routing_settings_contact_max_age_days_check CHECK ((contact_max_age_days > 0)),
    CONSTRAINT lead_routing_settings_id_check CHECK ((id = 1)),
    CONSTRAINT lead_routing_settings_max_direct_per_requirement_check CHECK ((max_direct_per_requirement >= 1)),
    CONSTRAINT lead_routing_settings_min_score_check CHECK (((min_score >= 0) AND (min_score <= 100)))
);


ALTER TABLE public.lead_routing_settings OWNER TO postgres;

--
-- Name: lead_status_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lead_status_history (
    id bigint NOT NULL,
    case_id uuid NOT NULL,
    from_status public.lead_status,
    to_status public.lead_status NOT NULL,
    assigned_to uuid,
    actor_id uuid,
    note text,
    at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.lead_status_history OWNER TO postgres;

--
-- Name: lead_status_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_status_history ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.lead_status_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    company_id uuid,
    kind public.notif_kind NOT NULL,
    title text,
    body text,
    link text,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.notifications OWNER TO postgres;

--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid,
    category_id integer,
    name text NOT NULL,
    description text,
    tags text,
    directory_status public.directory_status DEFAULT 'draft'::public.directory_status,
    search tsvector
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    full_name text,
    phone text,
    company_name text,
    city text,
    country text,
    preferred_location text,
    app_role public.app_role DEFAULT 'buyer'::public.app_role NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.profiles OWNER TO postgres;

--
-- Name: public_companies; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.public_companies WITH (security_invoker='false') AS
 SELECT id,
    slug,
    name,
    business_type,
    about,
    city,
    state,
    country,
    website,
    logo_path,
        CASE
            WHEN (verification_status = 'verified'::public.verification_status) THEN 'Verified business'::text
            WHEN (claim_status = 'approved'::public.claim_status) THEN 'Claimed business'::text
            ELSE 'Unclaimed business'::text
        END AS public_label,
    (claim_status = 'approved'::public.claim_status) AS is_claimed,
    (verification_status = 'verified'::public.verification_status) AS is_verified,
    updated_at AS data_as_of,
    updated_at
   FROM public.companies
  WHERE ((directory_status = 'published'::public.directory_status) AND (data_review_status = 'approved'::public.review_status));


ALTER VIEW public.public_companies OWNER TO postgres;

--
-- Name: rate_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rate_events (
    id bigint NOT NULL,
    user_id uuid,
    action text,
    at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.rate_events OWNER TO postgres;

--
-- Name: rate_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.rate_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.rate_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: requirement_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.requirement_details (
    enquiry_id uuid NOT NULL,
    buyer_id uuid NOT NULL,
    product_required text NOT NULL,
    product_norm text GENERATED ALWAYS AS (lower(regexp_replace(TRIM(BOTH FROM product_required), '\s+'::text, ' '::text, 'g'::text))) STORED,
    material text,
    size text,
    quality text,
    specifications text,
    destination_country text,
    delivery_timeline text,
    additional text,
    contact_pref text DEFAULT 'either'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT requirement_details_contact_pref_check CHECK ((contact_pref = ANY (ARRAY['phone'::text, 'email'::text, 'either'::text]))),
    CONSTRAINT requirement_details_product_required_check CHECK (((length(TRIM(BOTH FROM product_required)) >= 2) AND (length(TRIM(BOTH FROM product_required)) <= 200)))
);


ALTER TABLE public.requirement_details OWNER TO postgres;

--
-- Name: requirement_matches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.requirement_matches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    enquiry_id uuid NOT NULL,
    company_id uuid NOT NULL,
    score smallint NOT NULL,
    reasons jsonb NOT NULL,
    route public.match_route NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT requirement_matches_score_check CHECK (((score >= 0) AND (score <= 100)))
);


ALTER TABLE public.requirement_matches OWNER TO postgres;

--
-- Name: objects; Type: TABLE; Schema: storage; Owner: postgres
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text
);


ALTER TABLE storage.objects OWNER TO postgres;

--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: claim_invitations claim_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_invitations
    ADD CONSTRAINT claim_invitations_pkey PRIMARY KEY (id);


--
-- Name: claim_verification_outbox claim_verification_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_verification_outbox
    ADD CONSTRAINT claim_verification_outbox_pkey PRIMARY KEY (verification_id);


--
-- Name: claim_verifications claim_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_verifications
    ADD CONSTRAINT claim_verifications_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: company_acquisition company_acquisition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_acquisition
    ADD CONSTRAINT company_acquisition_pkey PRIMARY KEY (company_id);


--
-- Name: company_categories company_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_categories
    ADD CONSTRAINT company_categories_pkey PRIMARY KEY (company_id, category_id);


--
-- Name: company_claim_evidence company_claim_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claim_evidence
    ADD CONSTRAINT company_claim_evidence_pkey PRIMARY KEY (id);


--
-- Name: company_claims company_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claims
    ADD CONSTRAINT company_claims_pkey PRIMARY KEY (id);


--
-- Name: company_contacts company_contacts_company_id_kind_value_norm_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_company_id_kind_value_norm_key UNIQUE (company_id, kind, value_norm);


--
-- Name: company_contacts company_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_pkey PRIMARY KEY (id);


--
-- Name: company_members company_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_members
    ADD CONSTRAINT company_members_pkey PRIMARY KEY (id);


--
-- Name: company_outreach_events company_outreach_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_outreach_events
    ADD CONSTRAINT company_outreach_events_pkey PRIMARY KEY (id);


--
-- Name: company_private company_private_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_private
    ADD CONSTRAINT company_private_pkey PRIMARY KEY (company_id);


--
-- Name: contact_access_log contact_access_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contact_access_log
    ADD CONSTRAINT contact_access_log_pkey PRIMARY KEY (id);


--
-- Name: enquiries enquiries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enquiries
    ADD CONSTRAINT enquiries_pkey PRIMARY KEY (id);


--
-- Name: enquiry_private enquiry_private_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enquiry_private
    ADD CONSTRAINT enquiry_private_pkey PRIMARY KEY (enquiry_id);


--
-- Name: lead_cases lead_cases_enquiry_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_cases
    ADD CONSTRAINT lead_cases_enquiry_id_key UNIQUE (enquiry_id);


--
-- Name: lead_cases lead_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_cases
    ADD CONSTRAINT lead_cases_pkey PRIMARY KEY (id);


--
-- Name: lead_distribution_events lead_distribution_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_distribution_events
    ADD CONSTRAINT lead_distribution_events_pkey PRIMARY KEY (id);


--
-- Name: lead_routing_settings lead_routing_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_routing_settings
    ADD CONSTRAINT lead_routing_settings_pkey PRIMARY KEY (id);


--
-- Name: lead_status_history lead_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_status_history
    ADD CONSTRAINT lead_status_history_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: rate_events rate_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rate_events
    ADD CONSTRAINT rate_events_pkey PRIMARY KEY (id);


--
-- Name: requirement_details requirement_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.requirement_details
    ADD CONSTRAINT requirement_details_pkey PRIMARY KEY (enquiry_id);


--
-- Name: requirement_matches requirement_matches_enquiry_id_company_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.requirement_matches
    ADD CONSTRAINT requirement_matches_enquiry_id_company_id_key UNIQUE (enquiry_id, company_id);


--
-- Name: requirement_matches requirement_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.requirement_matches
    ADD CONSTRAINT requirement_matches_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: postgres
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: categories_parent_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX categories_parent_idx ON public.categories USING btree (parent_id);


--
-- Name: claim_invitations_one_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX claim_invitations_one_active ON public.claim_invitations USING btree (company_id) WHERE (status = ANY (ARRAY['draft'::text, 'approved'::text, 'sent_manual'::text]));


--
-- Name: claim_verifications_claim_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX claim_verifications_claim_idx ON public.claim_verifications USING btree (claim_id, channel, created_at DESC);


--
-- Name: lead_cases_assigned_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lead_cases_assigned_idx ON public.lead_cases USING btree (assigned_to, status);


--
-- Name: lead_events_no_dup; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX lead_events_no_dup ON public.lead_distribution_events USING btree (enquiry_id, company_id, event) WHERE (company_id IS NOT NULL);


--
-- Name: lead_events_one_no_match; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX lead_events_one_no_match ON public.lead_distribution_events USING btree (enquiry_id) WHERE (event = 'no_match'::text);


--
-- Name: requirement_details_dedupe_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX requirement_details_dedupe_idx ON public.requirement_details USING btree (buyer_id, product_norm, created_at DESC);


--
-- Name: contact_access_log calog_immutable; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER calog_immutable BEFORE DELETE OR UPDATE ON public.contact_access_log FOR EACH ROW EXECUTE FUNCTION public.block_mutation();


--
-- Name: company_claims company_claims_approval_gate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER company_claims_approval_gate BEFORE UPDATE OF status ON public.company_claims FOR EACH ROW EXECUTE FUNCTION public._claim_approval_gate();


--
-- Name: lead_distribution_events lde_immutable; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lde_immutable BEFORE DELETE OR UPDATE ON public.lead_distribution_events FOR EACH ROW EXECUTE FUNCTION public.block_mutation();


--
-- Name: lead_cases lead_cases_history; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lead_cases_history AFTER INSERT OR UPDATE ON public.lead_cases FOR EACH ROW EXECUTE FUNCTION public._lead_case_history();


--
-- Name: lead_status_history lsh_immutable; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER lsh_immutable BEFORE DELETE OR UPDATE ON public.lead_status_history FOR EACH ROW EXECUTE FUNCTION public.block_mutation();


--
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE RESTRICT;


--
-- Name: claim_invitations claim_invitations_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_invitations
    ADD CONSTRAINT claim_invitations_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.lead_cases(id) ON DELETE SET NULL;


--
-- Name: claim_invitations claim_invitations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_invitations
    ADD CONSTRAINT claim_invitations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: claim_invitations claim_invitations_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_invitations
    ADD CONSTRAINT claim_invitations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.company_contacts(id);


--
-- Name: claim_verification_outbox claim_verification_outbox_verification_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_verification_outbox
    ADD CONSTRAINT claim_verification_outbox_verification_id_fkey FOREIGN KEY (verification_id) REFERENCES public.claim_verifications(id) ON DELETE CASCADE;


--
-- Name: claim_verifications claim_verifications_claim_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.claim_verifications
    ADD CONSTRAINT claim_verifications_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES public.company_claims(id) ON DELETE CASCADE;


--
-- Name: company_acquisition company_acquisition_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_acquisition
    ADD CONSTRAINT company_acquisition_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_categories company_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_categories
    ADD CONSTRAINT company_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: company_categories company_categories_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_categories
    ADD CONSTRAINT company_categories_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: company_claim_evidence company_claim_evidence_claim_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claim_evidence
    ADD CONSTRAINT company_claim_evidence_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES public.company_claims(id);


--
-- Name: company_claims company_claims_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_claims
    ADD CONSTRAINT company_claims_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_contacts company_contacts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_contacts
    ADD CONSTRAINT company_contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: company_members company_members_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_members
    ADD CONSTRAINT company_members_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_outreach_events company_outreach_events_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_outreach_events
    ADD CONSTRAINT company_outreach_events_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: company_private company_private_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.company_private
    ADD CONSTRAINT company_private_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: enquiry_private enquiry_private_enquiry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enquiry_private
    ADD CONSTRAINT enquiry_private_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES public.enquiries(id);


--
-- Name: lead_cases lead_cases_enquiry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_cases
    ADD CONSTRAINT lead_cases_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES public.enquiries(id) ON DELETE CASCADE;


--
-- Name: lead_distribution_events lead_distribution_events_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_distribution_events
    ADD CONSTRAINT lead_distribution_events_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.lead_cases(id) ON DELETE SET NULL;


--
-- Name: lead_distribution_events lead_distribution_events_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_distribution_events
    ADD CONSTRAINT lead_distribution_events_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: lead_distribution_events lead_distribution_events_enquiry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_distribution_events
    ADD CONSTRAINT lead_distribution_events_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES public.enquiries(id) ON DELETE CASCADE;


--
-- Name: lead_status_history lead_status_history_case_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lead_status_history
    ADD CONSTRAINT lead_status_history_case_id_fkey FOREIGN KEY (case_id) REFERENCES public.lead_cases(id) ON DELETE CASCADE;


--
-- Name: products products_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: requirement_details requirement_details_enquiry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.requirement_details
    ADD CONSTRAINT requirement_details_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES public.enquiries(id) ON DELETE CASCADE;


--
-- Name: requirement_matches requirement_matches_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.requirement_matches
    ADD CONSTRAINT requirement_matches_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: requirement_matches requirement_matches_enquiry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.requirement_matches
    ADD CONSTRAINT requirement_matches_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES public.enquiries(id) ON DELETE CASCADE;


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: company_acquisition cacq_staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cacq_staff ON public.company_acquisition USING (public.is_staff()) WITH CHECK (public.is_staff());


--
-- Name: contact_access_log calog_admin_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY calog_admin_read ON public.contact_access_log FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: categories cat_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cat_read ON public.categories FOR SELECT USING (true);


--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: company_categories cc_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cc_read ON public.company_categories FOR SELECT USING (true);


--
-- Name: company_contacts ccontacts_own_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY ccontacts_own_read ON public.company_contacts FOR SELECT TO authenticated USING (public.has_company_role(company_id, ARRAY['owner'::public.member_role, 'manager'::public.member_role]));


--
-- Name: company_claim_evidence cev_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cev_read ON public.company_claim_evidence FOR SELECT USING (((public.claim_claimant(claim_id) = auth.uid()) OR public.is_staff()));


--
-- Name: claim_invitations cinv_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cinv_read ON public.claim_invitations FOR SELECT TO authenticated USING ((public.is_admin() OR (public.is_staff() AND (created_by = auth.uid()))));


--
-- Name: claim_invitations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.claim_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: claim_verification_outbox; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.claim_verification_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: claim_verifications; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.claim_verifications ENABLE ROW LEVEL SECURITY;

--
-- Name: company_claims claims_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY claims_read ON public.company_claims FOR SELECT USING (((claimant_id = auth.uid()) OR public.staff_can_review_claim(id)));


--
-- Name: companies comp_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY comp_read ON public.companies FOR SELECT USING (((directory_status = 'published'::public.directory_status) OR public.is_staff() OR public.is_company_member(id)));


--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: company_acquisition; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_acquisition ENABLE ROW LEVEL SECURITY;

--
-- Name: company_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: company_claim_evidence; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_claim_evidence ENABLE ROW LEVEL SECURITY;

--
-- Name: company_claims; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: company_contacts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: company_members; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;

--
-- Name: company_outreach_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_outreach_events ENABLE ROW LEVEL SECURITY;

--
-- Name: company_private; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.company_private ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_access_log; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.contact_access_log ENABLE ROW LEVEL SECURITY;

--
-- Name: company_outreach_events cout_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cout_insert ON public.company_outreach_events FOR INSERT WITH CHECK (public.is_staff());


--
-- Name: company_outreach_events cout_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cout_read ON public.company_outreach_events FOR SELECT USING (public.is_staff());


--
-- Name: company_private cpriv_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY cpriv_read ON public.company_private FOR SELECT USING ((public.has_company_role(company_id, ARRAY['owner'::public.member_role, 'manager'::public.member_role]) OR public.is_staff()));


--
-- Name: enquiries enq_buyer_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_buyer_read ON public.enquiries FOR SELECT USING ((buyer_id = auth.uid()));


--
-- Name: enquiries enq_company_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_company_read ON public.enquiries FOR SELECT USING (((company_id IS NOT NULL) AND public.has_company_role(company_id, ARRAY['owner'::public.member_role, 'manager'::public.member_role, 'sales'::public.member_role])));


--
-- Name: enquiries enq_leads_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_leads_read ON public.enquiries FOR SELECT USING (((kind = 'requirement'::public.enquiry_kind) AND public.seller_lead_visible(id)));


--
-- Name: enquiries enq_staff_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_staff_read ON public.enquiries FOR SELECT USING (public.staff_can_see_enquiry(id));


--
-- Name: enquiries enq_staff_upd; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY enq_staff_upd ON public.enquiries FOR UPDATE USING (public.staff_can_see_enquiry(id)) WITH CHECK (public.staff_can_see_enquiry(id));


--
-- Name: enquiries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.enquiries ENABLE ROW LEVEL SECURITY;

--
-- Name: enquiry_private; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.enquiry_private ENABLE ROW LEVEL SECURITY;

--
-- Name: enquiry_private epriv_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY epriv_read ON public.enquiry_private FOR SELECT USING (((public.enquiry_buyer(enquiry_id) = auth.uid()) OR public.staff_can_see_enquiry(enquiry_id)));


--
-- Name: lead_cases lc_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lc_read ON public.lead_cases FOR SELECT TO authenticated USING (public.staff_can_see_case(id));


--
-- Name: lead_distribution_events lde_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lde_read ON public.lead_distribution_events FOR SELECT TO authenticated USING ((public.staff_can_see_enquiry(enquiry_id) OR ((event = 'delivered_direct'::text) AND (company_id IS NOT NULL) AND public.seller_match_visible(company_id, enquiry_id))));


--
-- Name: lead_cases; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_cases ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_distribution_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_distribution_events ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_routing_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_routing_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_status_history; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.lead_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: lead_routing_settings lrs_admin_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lrs_admin_read ON public.lead_routing_settings FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: lead_status_history lsh_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY lsh_read ON public.lead_status_history FOR SELECT TO authenticated USING (public.staff_can_see_case(case_id));


--
-- Name: company_members members_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY members_read ON public.company_members FOR SELECT USING (((user_id = auth.uid()) OR public.is_staff()));


--
-- Name: notifications notif_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY notif_read ON public.notifications FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: products prod_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY prod_read ON public.products FOR SELECT USING (((directory_status = 'published'::public.directory_status) OR public.is_staff()));


--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_self_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY profiles_self_read ON public.profiles FOR SELECT USING (((id = auth.uid()) OR public.is_staff()));


--
-- Name: rate_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.rate_events ENABLE ROW LEVEL SECURITY;

--
-- Name: requirement_details rd_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY rd_read ON public.requirement_details FOR SELECT TO authenticated USING (((buyer_id = auth.uid()) OR public.staff_can_see_enquiry(enquiry_id) OR public.seller_lead_visible(enquiry_id)));


--
-- Name: requirement_details; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.requirement_details ENABLE ROW LEVEL SECURITY;

--
-- Name: requirement_matches; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.requirement_matches ENABLE ROW LEVEL SECURITY;

--
-- Name: requirement_matches rm_read; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY rm_read ON public.requirement_matches FOR SELECT TO authenticated USING ((public.staff_can_see_enquiry(enquiry_id) OR public.seller_match_visible(company_id, enquiry_id)));


--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: postgres
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: objects vd_read; Type: POLICY; Schema: storage; Owner: postgres
--

CREATE POLICY vd_read ON storage.objects FOR SELECT TO authenticated USING (((bucket_id = 'verification-docs'::text) AND ((public.claim_claimant(public.safe_uuid((storage.foldername(name))[1])) = auth.uid()) OR public.staff_can_review_claim(public.safe_uuid((storage.foldername(name))[1])))));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;


--
-- Name: FUNCTION _claim_approval_gate(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public._claim_approval_gate() FROM PUBLIC;


--
-- Name: FUNCTION _company_lead_eligible(p_company uuid, p_category integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public._company_lead_eligible(p_company uuid, p_category integer) FROM PUBLIC;


--
-- Name: FUNCTION _lead_case_history(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public._lead_case_history() FROM PUBLIC;


--
-- Name: FUNCTION _match_requirement(p_enq uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public._match_requirement(p_enq uuid) FROM PUBLIC;


--
-- Name: FUNCTION admin_approve_invitation(p_inv uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_approve_invitation(p_inv uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_approve_invitation(p_inv uuid) TO authenticated;


--
-- Name: FUNCTION admin_assign_lead(p_case uuid, p_staff uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_assign_lead(p_case uuid, p_staff uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_assign_lead(p_case uuid, p_staff uuid) TO authenticated;


--
-- Name: FUNCTION admin_lead_overview(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_lead_overview() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_lead_overview() TO authenticated;


--
-- Name: FUNCTION admin_rematch(p_enquiry uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_rematch(p_enquiry uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_rematch(p_enquiry uuid) TO authenticated;


--
-- Name: FUNCTION admin_rematch_for_company(p_company uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_rematch_for_company(p_company uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_rematch_for_company(p_company uuid) TO authenticated;


--
-- Name: FUNCTION admin_set_routing_settings(p_min_score integer, p_max_direct integer, p_req_email boolean, p_req_phone boolean); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.admin_set_routing_settings(p_min_score integer, p_max_direct integer, p_req_email boolean, p_req_phone boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_set_routing_settings(p_min_score integer, p_max_direct integer, p_req_email boolean, p_req_phone boolean) TO authenticated;


--
-- Name: FUNCTION block_mutation(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.block_mutation() FROM PUBLIC;
GRANT ALL ON FUNCTION public.block_mutation() TO authenticated;
GRANT ALL ON FUNCTION public.block_mutation() TO service_role;


--
-- Name: FUNCTION buyer_requirement_status(p_enquiry uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.buyer_requirement_status(p_enquiry uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.buyer_requirement_status(p_enquiry uuid) TO authenticated;


--
-- Name: FUNCTION check_rate(p_action text, p_max integer, p_window interval); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) TO authenticated;
GRANT ALL ON FUNCTION public.check_rate(p_action text, p_max integer, p_window interval) TO service_role;


--
-- Name: FUNCTION claim_claimant(cid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.claim_claimant(cid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_claimant(cid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.claim_claimant(cid uuid) TO service_role;


--
-- Name: FUNCTION claim_is_open_for_me(cid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.claim_is_open_for_me(cid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_is_open_for_me(cid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.claim_is_open_for_me(cid uuid) TO service_role;


--
-- Name: FUNCTION claim_verification_summary(p_claim uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.claim_verification_summary(p_claim uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.claim_verification_summary(p_claim uuid) TO authenticated;


--
-- Name: FUNCTION confirm_claim_verification(p_claim uuid, p_channel text, p_code text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.confirm_claim_verification(p_claim uuid, p_channel text, p_code text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.confirm_claim_verification(p_claim uuid, p_channel text, p_code text) TO authenticated;


--
-- Name: FUNCTION create_requirement(p_enquiry uuid, p_product text, p_material text, p_size text, p_quality text, p_specs text, p_destination text, p_timeline text, p_additional text, p_contact_pref text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.create_requirement(p_enquiry uuid, p_product text, p_material text, p_size text, p_quality text, p_specs text, p_destination text, p_timeline text, p_additional text, p_contact_pref text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_requirement(p_enquiry uuid, p_product text, p_material text, p_size text, p_quality text, p_specs text, p_destination text, p_timeline text, p_additional text, p_contact_pref text) TO authenticated;


--
-- Name: FUNCTION enquiry_buyer(eid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.enquiry_buyer(eid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.enquiry_buyer(eid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.enquiry_buyer(eid uuid) TO service_role;


--
-- Name: FUNCTION has_company_role(cid uuid, roles public.member_role[]); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) TO authenticated;
GRANT ALL ON FUNCTION public.has_company_role(cid uuid, roles public.member_role[]) TO service_role;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_admin() TO service_role;


--
-- Name: FUNCTION is_company_member(cid uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_company_member(cid uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_company_member(cid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_company_member(cid uuid) TO service_role;


--
-- Name: FUNCTION is_staff(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.is_staff() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_staff() TO authenticated;
GRANT ALL ON FUNCTION public.is_staff() TO service_role;


--
-- Name: FUNCTION lead_matches_my_company(cat integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.lead_matches_my_company(cat integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.lead_matches_my_company(cat integer) TO authenticated;
GRANT ALL ON FUNCTION public.lead_matches_my_company(cat integer) TO service_role;


--
-- Name: FUNCTION norm_domain(t text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.norm_domain(t text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.norm_domain(t text) TO authenticated;
GRANT ALL ON FUNCTION public.norm_domain(t text) TO service_role;


--
-- Name: FUNCTION redeem_invitation(p_token text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.redeem_invitation(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.redeem_invitation(p_token text) TO authenticated;


--
-- Name: FUNCTION review_claim(p_claim uuid, p_decision public.claim_status, p_reason text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) TO service_role;


--
-- Name: FUNCTION safe_uuid(t text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.safe_uuid(t text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.safe_uuid(t text) TO authenticated;
GRANT ALL ON FUNCTION public.safe_uuid(t text) TO service_role;


--
-- Name: FUNCTION seller_can_see_leads(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.seller_can_see_leads() FROM PUBLIC;
GRANT ALL ON FUNCTION public.seller_can_see_leads() TO authenticated;
GRANT ALL ON FUNCTION public.seller_can_see_leads() TO service_role;


--
-- Name: FUNCTION seller_lead_visible(p_enq uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.seller_lead_visible(p_enq uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.seller_lead_visible(p_enq uuid) TO authenticated;


--
-- Name: FUNCTION seller_match_visible(p_company uuid, p_enq uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.seller_match_visible(p_company uuid, p_enq uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.seller_match_visible(p_company uuid, p_enq uuid) TO authenticated;


--
-- Name: FUNCTION staff_add_contact(p_company uuid, p_kind text, p_value text, p_source_type public.source_type, p_source_name text, p_source_url text, p_purpose text, p_case uuid, p_claim uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_add_contact(p_company uuid, p_kind text, p_value text, p_source_type public.source_type, p_source_name text, p_source_url text, p_purpose text, p_case uuid, p_claim uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_add_contact(p_company uuid, p_kind text, p_value text, p_source_type public.source_type, p_source_name text, p_source_url text, p_purpose text, p_case uuid, p_claim uuid) TO authenticated;


--
-- Name: FUNCTION staff_can_access_company(p_company uuid, p_case uuid, p_claim uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_can_access_company(p_company uuid, p_case uuid, p_claim uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_can_access_company(p_company uuid, p_case uuid, p_claim uuid) TO authenticated;


--
-- Name: FUNCTION staff_can_review_claim(p_claim uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_can_review_claim(p_claim uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_can_review_claim(p_claim uuid) TO authenticated;


--
-- Name: FUNCTION staff_can_see_case(p_case uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_can_see_case(p_case uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_can_see_case(p_case uuid) TO authenticated;


--
-- Name: FUNCTION staff_can_see_enquiry(p_enq uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_can_see_enquiry(p_enq uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_can_see_enquiry(p_enq uuid) TO authenticated;


--
-- Name: FUNCTION staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text) TO authenticated;


--
-- Name: FUNCTION staff_get_contacts(p_company uuid, p_purpose text, p_case uuid, p_claim uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_get_contacts(p_company uuid, p_purpose text, p_case uuid, p_claim uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_get_contacts(p_company uuid, p_purpose text, p_case uuid, p_claim uuid) TO authenticated;


--
-- Name: FUNCTION staff_log_call(p_case uuid, p_company uuid, p_summary text, p_outcome text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_log_call(p_case uuid, p_company uuid, p_summary text, p_outcome text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_log_call(p_case uuid, p_company uuid, p_summary text, p_outcome text) TO authenticated;


--
-- Name: FUNCTION staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) TO authenticated;
GRANT ALL ON FUNCTION public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text) TO service_role;


--
-- Name: FUNCTION staff_mark_invitation_sent(p_inv uuid, p_provider_ref text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_mark_invitation_sent(p_inv uuid, p_provider_ref text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_mark_invitation_sent(p_inv uuid, p_provider_ref text) TO authenticated;


--
-- Name: FUNCTION staff_my_leads(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_my_leads() FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_my_leads() TO authenticated;


--
-- Name: FUNCTION staff_set_contact_status(p_contact uuid, p_status text, p_purpose text, p_case uuid, p_claim uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_set_contact_status(p_contact uuid, p_status text, p_purpose text, p_case uuid, p_claim uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_set_contact_status(p_contact uuid, p_status text, p_purpose text, p_case uuid, p_claim uuid) TO authenticated;


--
-- Name: FUNCTION staff_update_lead(p_case uuid, p_status public.lead_status, p_note text, p_next_follow_up timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.staff_update_lead(p_case uuid, p_status public.lead_status, p_note text, p_next_follow_up timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.staff_update_lead(p_case uuid, p_status public.lead_status, p_note text, p_next_follow_up timestamp with time zone) TO authenticated;


--
-- Name: FUNCTION start_claim_verification(p_claim uuid, p_channel text, p_target text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.start_claim_verification(p_claim uuid, p_channel text, p_target text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.start_claim_verification(p_claim uuid, p_channel text, p_target text) TO authenticated;


--
-- Name: FUNCTION submit_claim(p_company uuid, p_title text, p_statement text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) TO authenticated;
GRANT ALL ON FUNCTION public.submit_claim(p_company uuid, p_title text, p_statement text) TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_log TO authenticated;


--
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.categories TO authenticated;


--
-- Name: TABLE claim_invitations; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.claim_invitations TO authenticated;


--
-- Name: TABLE claim_verification_outbox; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,DELETE,UPDATE ON TABLE public.claim_verification_outbox TO service_role;


--
-- Name: TABLE companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.companies TO authenticated;


--
-- Name: TABLE company_acquisition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_acquisition TO authenticated;


--
-- Name: TABLE company_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_categories TO authenticated;


--
-- Name: TABLE company_claim_evidence; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_claim_evidence TO authenticated;


--
-- Name: TABLE company_claims; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_claims TO authenticated;


--
-- Name: TABLE company_contacts; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.company_contacts TO authenticated;


--
-- Name: TABLE company_members; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_members TO authenticated;


--
-- Name: TABLE company_outreach_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_outreach_events TO authenticated;


--
-- Name: TABLE company_private; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.company_private TO authenticated;


--
-- Name: TABLE contact_access_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.contact_access_log TO authenticated;


--
-- Name: TABLE enquiries; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.enquiries TO authenticated;


--
-- Name: TABLE enquiry_private; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.enquiry_private TO authenticated;


--
-- Name: TABLE lead_cases; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lead_cases TO authenticated;


--
-- Name: TABLE lead_distribution_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lead_distribution_events TO authenticated;


--
-- Name: TABLE lead_routing_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lead_routing_settings TO authenticated;


--
-- Name: TABLE lead_status_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.lead_status_history TO authenticated;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.notifications TO authenticated;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.products TO authenticated;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE public_companies; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.public_companies TO anon;
GRANT SELECT ON TABLE public.public_companies TO authenticated;


--
-- Name: TABLE rate_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.rate_events TO authenticated;


--
-- Name: TABLE requirement_details; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.requirement_details TO authenticated;


--
-- Name: TABLE requirement_matches; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.requirement_matches TO authenticated;


--
-- Name: TABLE objects; Type: ACL; Schema: storage; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE storage.objects TO authenticated;


--
-- PostgreSQL database dump complete
--



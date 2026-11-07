-- DRAFT — NOT APPLIED to any Supabase project.
-- Structured buyer requirements, explainable matching, verified-only direct routing, admin lead desk, assignment-scoped staff access.
-- Replaces (drop+create) staging policies: enq_leads_read, enq_staff_read, enq_staff_upd, epriv_read; redefines functions
-- seller_can_see_leads(), lead_matches_my_company(int), staff_mark_enquiry(...). Originals are restored by down/0002_down.sql.
begin;

create type public.lead_status as enum ('new','assigned','contact_pending','contacted','interested','not_interested','claim_invitation_sent','registration_started','verification_pending','seller_activated','follow_up_required','no_suitable_supplier','closed');
create type public.match_route as enum ('direct','admin');

create table public.lead_routing_settings (
  id integer primary key default 1 check (id = 1),
  min_score integer not null default 40 check (min_score between 0 and 100),
  max_direct_per_requirement integer not null default 5 check (max_direct_per_requirement >= 1),
  require_verified_email boolean not null default true,
  require_verified_phone boolean not null default true,
  contact_max_age_days integer not null default 365 check (contact_max_age_days > 0),
  updated_by uuid, updated_at timestamptz not null default now()
);
insert into public.lead_routing_settings(id) values (1);

create table public.requirement_details (
  enquiry_id uuid primary key references public.enquiries(id) on delete cascade,
  buyer_id uuid not null,
  product_required text not null check (length(trim(product_required)) between 2 and 200),
  product_norm text generated always as (lower(regexp_replace(trim(product_required), '\s+', ' ', 'g'))) stored,
  material text, size text, quality text, specifications text,
  destination_country text, delivery_timeline text, additional text,
  contact_pref text not null default 'either' check (contact_pref in ('phone','email','either')),
  created_at timestamptz not null default now()
);
create index requirement_details_dedupe_idx on public.requirement_details(buyer_id, product_norm, created_at desc);

create table public.requirement_matches (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null references public.enquiries(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  score smallint not null check (score between 0 and 100),
  reasons jsonb not null,
  route public.match_route not null,
  created_at timestamptz not null default now(),
  unique (enquiry_id, company_id)   -- one match row per requirement/company: duplicate delivery protection
);

create table public.lead_cases (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null unique references public.enquiries(id) on delete cascade,
  queue text not null check (queue in ('unclaimed_matches','unverified_matches','capped_eligible','unmatched')),
  status public.lead_status not null default 'new',
  assigned_to uuid, assigned_at timestamptz,
  next_follow_up_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), closed_at timestamptz
);
create index lead_cases_assigned_idx on public.lead_cases(assigned_to, status);

create table public.lead_status_history (
  id bigint generated always as identity primary key,
  case_id uuid not null references public.lead_cases(id) on delete cascade,
  from_status public.lead_status, to_status public.lead_status not null,
  assigned_to uuid, actor_id uuid, note text, at timestamptz not null default now()
);
create table public.lead_distribution_events (
  id bigint generated always as identity primary key,
  enquiry_id uuid not null references public.enquiries(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  case_id uuid references public.lead_cases(id) on delete set null,
  event text not null check (event in ('delivered_direct','routed_admin','no_match')),
  reason text, actor_id uuid, at timestamptz not null default now()
);
create unique index lead_events_no_dup on public.lead_distribution_events(enquiry_id, company_id, event) where company_id is not null;
create unique index lead_events_one_no_match on public.lead_distribution_events(enquiry_id) where event='no_match';

create trigger lsh_immutable before update or delete on public.lead_status_history for each row execute function public.block_mutation();
create trigger lde_immutable before update or delete on public.lead_distribution_events for each row execute function public.block_mutation();

-- ---------- helper predicates ----------
create function public.staff_can_see_enquiry(p_enq uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.lead_cases lc where lc.enquiry_id = p_enq and lc.assigned_to = auth.uid()))
$$;
create function public.staff_can_see_case(p_case uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.lead_cases lc where lc.id = p_case and lc.assigned_to = auth.uid()))
$$;
-- Assignment-scoped access to one supplier's private records.
create function public.staff_can_access_company(p_company uuid, p_case uuid default null, p_claim uuid default null) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and (
    (p_case is not null and exists(select 1 from public.lead_cases lc join public.requirement_matches rm on rm.enquiry_id = lc.enquiry_id
        where lc.id = p_case and lc.assigned_to = auth.uid() and rm.company_id = p_company and rm.route = 'admin'))
    or (p_claim is not null and exists(select 1 from public.company_claims cl where cl.id = p_claim and cl.company_id = p_company
        and cl.status in ('claim_submitted','evidence_requested','under_review')))))
$$;
-- INTERNAL eligibility rule (no grants): all conditions of verified-only direct routing.
create function public._company_lead_eligible(p_company uuid, p_category integer) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
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
revoke all on function public._company_lead_eligible(uuid, integer) from public, anon, authenticated;

-- Seller-facing predicates (used by RLS; return only facts about the caller's own companies)
create function public.seller_match_visible(p_company uuid, p_enq uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.requirement_matches rm join public.enquiries e on e.id = rm.enquiry_id
    join public.company_members m on m.company_id = rm.company_id and m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner','manager','sales')
    where rm.enquiry_id = p_enq and rm.company_id = p_company and rm.route = 'direct' and public._company_lead_eligible(rm.company_id, e.category_id))
$$;
create function public.seller_lead_visible(p_enq uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.requirement_matches rm where rm.enquiry_id = p_enq and public.seller_match_visible(rm.company_id, p_enq))
$$;
-- Defense in depth: the two legacy helpers now also require verification etc.
create or replace function public.seller_can_see_leads() returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.company_members m where m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner','manager','sales') and public._company_lead_eligible(m.company_id, null))
$$;
create or replace function public.lead_matches_my_company(cat integer) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.company_members m where m.user_id = auth.uid() and m.status = 'active' and m.role in ('owner','manager','sales') and public._company_lead_eligible(m.company_id, cat))
$$;
grant execute on function public.staff_can_see_enquiry(uuid), public.staff_can_see_case(uuid), public.staff_can_access_company(uuid,uuid,uuid), public.seller_match_visible(uuid,uuid), public.seller_lead_visible(uuid) to authenticated;
revoke execute on function public.staff_can_see_enquiry(uuid), public.staff_can_see_case(uuid), public.staff_can_access_company(uuid,uuid,uuid), public.seller_match_visible(uuid,uuid), public.seller_lead_visible(uuid) from public, anon;

-- ---------- RLS on new tables (reads only; writes only through functions) ----------
do $$ declare t text; begin
  foreach t in array array['lead_routing_settings','requirement_details','requirement_matches','lead_cases','lead_status_history','lead_distribution_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop; end $$;
create policy lrs_admin_read on public.lead_routing_settings for select to authenticated using (public.is_admin());
create policy rd_read on public.requirement_details for select to authenticated using (buyer_id = auth.uid() or public.staff_can_see_enquiry(enquiry_id) or public.seller_lead_visible(enquiry_id));
create policy rm_read on public.requirement_matches for select to authenticated using (public.staff_can_see_enquiry(enquiry_id) or public.seller_match_visible(company_id, enquiry_id));
create policy lc_read on public.lead_cases for select to authenticated using (public.staff_can_see_case(id));
create policy lsh_read on public.lead_status_history for select to authenticated using (public.staff_can_see_case(case_id));
create policy lde_read on public.lead_distribution_events for select to authenticated using (public.staff_can_see_enquiry(enquiry_id) or (event = 'delivered_direct' and company_id is not null and public.seller_match_visible(company_id, enquiry_id)));

-- ---------- replace role-wide staff policies on existing tables ----------
drop policy enq_leads_read on public.enquiries;
create policy enq_leads_read on public.enquiries for select using (kind = 'requirement' and public.seller_lead_visible(id));
drop policy enq_staff_read on public.enquiries;
create policy enq_staff_read on public.enquiries for select using (public.staff_can_see_enquiry(id));
drop policy enq_staff_upd on public.enquiries;
create policy enq_staff_upd on public.enquiries for update using (public.staff_can_see_enquiry(id)) with check (public.staff_can_see_enquiry(id));
drop policy epriv_read on public.enquiry_private;
create policy epriv_read on public.enquiry_private for select using (public.enquiry_buyer(enquiry_id) = auth.uid() or public.staff_can_see_enquiry(enquiry_id));
create or replace function public.staff_mark_enquiry(p_enquiry uuid, p_delivery public.enquiry_delivery, p_note text, p_provider_ref text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_staff() or not public.staff_can_see_enquiry(p_enquiry) then raise exception 'staff only' using errcode = '42501'; end if;
  if p_delivery = 'sent_external' and coalesce(trim(p_provider_ref),'') = '' then raise exception 'sent_external requires a provider reference'; end if;
  update public.enquiries set delivery = p_delivery, delivery_note = left(coalesce(p_note,'') || case when p_provider_ref is not null then ' [ref ' || p_provider_ref || ']' else '' end, 500) where id = p_enquiry;
  if not found then raise exception 'enquiry not found'; end if;
end $$;

-- ---------- matching & routing (internal) ----------
create function public._match_requirement(p_enq uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
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
revoke all on function public._match_requirement(uuid) from public, anon, authenticated;

-- lead_cases audit trail
create function public._lead_case_history() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then insert into public.lead_status_history(case_id, from_status, to_status, assigned_to, actor_id, note) values (new.id, null, new.status, new.assigned_to, auth.uid(), 'case created: ' || new.queue);
  elsif new.status is distinct from old.status or new.assigned_to is distinct from old.assigned_to then
    insert into public.lead_status_history(case_id, from_status, to_status, assigned_to, actor_id, note) values (new.id, old.status, new.status, new.assigned_to, auth.uid(), current_setting('app.lead_note', true));
  end if; return new; end $$;
revoke all on function public._lead_case_history() from public, anon, authenticated;
create trigger lead_cases_history after insert or update on public.lead_cases for each row execute function public._lead_case_history();

-- ---------- buyer entry point ----------
create function public.create_requirement(p_enquiry uuid, p_product text, p_material text, p_size text, p_quality text, p_specs text, p_destination text, p_timeline text, p_additional text, p_contact_pref text default 'either')
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
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
create function public.buyer_requirement_status(p_enquiry uuid) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  if public.enquiry_buyer(p_enquiry) is distinct from auth.uid() then raise exception 'not your requirement' using errcode = '42501'; end if;
  select count(*) into n from public.lead_distribution_events where enquiry_id = p_enquiry and event = 'delivered_direct';
  return jsonb_build_object('delivered_to_verified_suppliers', n,
    'being_handled_by_team', exists(select 1 from public.lead_cases where enquiry_id = p_enquiry and status <> 'closed'),
    'message', case when n > 0 then 'Sent to ' || n || ' verified supplier(s).' else 'Received. Our team is looking for suitable suppliers. No supplier has received it yet.' end);
end $$;

-- ---------- admin / staff lead desk ----------
create function public.admin_rematch(p_enquiry uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if; perform public._match_requirement(p_enquiry); end $$;
create function public.admin_rematch_for_company(p_company uuid) returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n integer := 0;
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  for r in select distinct rm.enquiry_id from public.requirement_matches rm join public.enquiries e on e.id = rm.enquiry_id where rm.company_id = p_company and rm.route = 'admin' and e.status not in ('closed','spam') loop
    perform public._match_requirement(r.enquiry_id); n := n + 1; end loop; return n; end $$;
create function public.admin_assign_lead(p_case uuid, p_staff uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if not exists(select 1 from public.profiles where id = p_staff and app_role in ('admin','reviewer')) then raise exception 'assignee is not staff'; end if;
  perform set_config('app.lead_note', 'assigned by admin', true);
  update public.lead_cases set assigned_to = p_staff, assigned_at = now(), status = case when status = 'new' then 'assigned' else status end, updated_at = now() where id = p_case;
  if not found then raise exception 'case not found'; end if;
end $$;
create function public.staff_update_lead(p_case uuid, p_status public.lead_status, p_note text, p_next_follow_up timestamptz default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.staff_can_see_case(p_case) then raise exception 'not assigned to you' using errcode = '42501'; end if;
  perform set_config('app.lead_note', left(coalesce(p_note,''), 500), true);
  update public.lead_cases set status = p_status, next_follow_up_at = coalesce(p_next_follow_up, next_follow_up_at), updated_at = now(), closed_at = case when p_status = 'closed' then now() else null end where id = p_case;
end $$;
create function public.staff_my_leads() returns table(case_id uuid, enquiry_id uuid, queue text, status public.lead_status, product text, quantity numeric, unit text, destination text, next_follow_up_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select lc.id, lc.enquiry_id, lc.queue, lc.status, d.product_required, e.quantity, e.unit, d.destination_country, lc.next_follow_up_at
  from public.lead_cases lc join public.enquiries e on e.id = lc.enquiry_id left join public.requirement_details d on d.enquiry_id = lc.enquiry_id
  where public.is_staff() and lc.assigned_to = auth.uid() order by lc.next_follow_up_at nulls last, lc.created_at
$$;
create function public.staff_log_call(p_case uuid, p_company uuid, p_summary text, p_outcome text) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare id uuid;
begin
  if not public.staff_can_access_company(p_company, p_case, null) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if exists(select 1 from public.company_acquisition where company_id = p_company and acquisition_status = 'do_not_contact') then raise exception 'supplier is marked do-not-contact'; end if;
  insert into public.company_outreach_events(company_id, event_type, channel, summary, outcome, delivery, recorded_by) values (p_company, 'call', 'phone', left(p_summary,1000), left(p_outcome,200), 'logged_manual', auth.uid()) returning company_outreach_events.id into id;
  return id;
end $$;
create function public.admin_lead_overview() returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
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
create function public.admin_set_routing_settings(p_min_score integer, p_max_direct integer, p_req_email boolean, p_req_phone boolean) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update public.lead_routing_settings set min_score = p_min_score, max_direct_per_requirement = p_max_direct, require_verified_email = p_req_email, require_verified_phone = p_req_phone, updated_by = auth.uid(), updated_at = now() where id = 1; end $$;

do $$ declare f text; begin
  foreach f in array array['create_requirement(uuid,text,text,text,text,text,text,text,text,text)','buyer_requirement_status(uuid)','admin_rematch(uuid)','admin_rematch_for_company(uuid)','admin_assign_lead(uuid,uuid)','staff_update_lead(uuid,public.lead_status,text,timestamptz)','staff_my_leads()','staff_log_call(uuid,uuid,text,text)','admin_lead_overview()','admin_set_routing_settings(integer,integer,boolean,boolean)','staff_mark_enquiry(uuid,public.enquiry_delivery,text,text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop; end $$;
commit;

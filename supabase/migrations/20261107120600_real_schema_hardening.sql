-- DRAFT — NOT APPLIED to any Supabase project. Stacked on 0001-0005.
-- Written AFTER reading the REAL staging catalog (read-only, 2026-11-07). Fixes gaps that only the real function bodies/policies revealed:
--  F-R1  respond_to_lead / reveal_buyer_contact / seller_can_reply let ANY claimed+published member respond to ANY requirement in a category
--        and then reveal buyer phone/email (verified-only routing bypass).                           -> re-checked eligibility at access time
--  F-R2  notify_on_enquiry notifies every claimed+published seller in the category of every new requirement (subject leaked) -> removed
--  F-R3  submit_enquiry delivers product enquiries to claimed-but-UNVERIFIED sellers (visible_to_seller)  -> verified-only; honest notice
--  F-R4  guard_company_columns does not protect companies.lead_delivery_blocked / is_demo (0001 columns); owner/manager/catalogue_editor
--        have UPDATE on companies -> a restricted seller could clear its own restriction                    -> columns protected
--  F-R5  review_claim lets ANY staff approve ANY claim (staff_can_review_claim was not assignment-scoped)   -> claim reviewer assignment
--  F-R6  cev_read / company_claim_evidence readable by ALL staff; no audit of evidence reads               -> claimant-only table access + audited grant RPC
--  F-R7  company_private (phone/email/address) readable+writable by ALL staff                              -> owner/manager only; staff use the audited vault
--  F-R8  profiles_self_read lets all staff read every profile (buyer phone numbers)                        -> own/admin/staff-role rows only
--  F-R9  new tables lacked FORCE ROW LEVEL SECURITY used by every existing table                           -> forced
-- Every replaced object is restored by down/0006_down.sql. No existing control is weakened.
begin;

-- ===== F-R4 protect 0001 columns =====
create or replace function public.guard_company_columns() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if not is_trusted_session() and (
        new.directory_status is distinct from old.directory_status or new.claim_status is distinct from old.claim_status
     or new.verification_status is distinct from old.verification_status or new.verified_at is distinct from old.verified_at
     or new.verified_by is distinct from old.verified_by or new.data_review_status is distinct from old.data_review_status
     or new.data_reviewed_by is distinct from old.data_reviewed_by or new.slug is distinct from old.slug
     or new.dedupe_key is distinct from old.dedupe_key or new.import_batch_id is distinct from old.import_batch_id
     or new.created_by is distinct from old.created_by
     or new.lead_delivery_blocked is distinct from old.lead_delivery_blocked or new.is_demo is distinct from old.is_demo) then
    raise exception 'protected company column: use the review RPCs' using errcode='42501';
  end if;
  return new;
end $$;

-- ===== F-R5 claim reviewer assignment =====
create table public.claim_reviewer_assignments (
  claim_id uuid primary key references public.company_claims(id) on delete cascade,
  reviewer_id uuid not null references public.profiles(id),
  assigned_by uuid not null,
  assigned_at timestamptz not null default now()
);
create or replace function public.staff_can_review_claim(p_claim uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and exists(
    select 1 from public.company_claims c join public.claim_reviewer_assignments a on a.claim_id = c.id
    where c.id = p_claim and a.reviewer_id = auth.uid() and c.status in ('claim_submitted','evidence_requested','under_review')))
$$;
create function public.admin_assign_claim_reviewer(p_claim uuid, p_reviewer uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if not exists(select 1 from public.company_claims where id = p_claim and status in ('claim_submitted','evidence_requested','under_review')) then raise exception 'claim is not open'; end if;
  if not exists(select 1 from public.profiles where id = p_reviewer and app_role in ('reviewer','admin')) then raise exception 'reviewer must be a staff account'; end if;
  insert into public.claim_reviewer_assignments(claim_id, reviewer_id, assigned_by) values (p_claim, p_reviewer, auth.uid())
    on conflict (claim_id) do update set reviewer_id = excluded.reviewer_id, assigned_by = excluded.assigned_by, assigned_at = now();
  insert into public.audit_log(actor_id, actor_role, action, entity, entity_id, new_value) values (auth.uid(), current_user, 'claim_reviewer_assigned', 'company_claims', p_claim::text, jsonb_build_object('reviewer', p_reviewer));
end $$;
-- the 0002 company-access helper had the same role-wide claim branch -> scope it to the assigned reviewer
create or replace function public.staff_can_access_company(p_company uuid, p_case uuid default null, p_claim uuid default null) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and (
    (p_case is not null and exists(select 1 from public.lead_cases lc join public.requirement_matches rm on rm.enquiry_id = lc.enquiry_id
        where lc.id = p_case and lc.assigned_to = auth.uid() and rm.company_id = p_company and rm.route = 'admin'))
    or (p_claim is not null and exists(select 1 from public.company_claims cl where cl.id = p_claim and cl.company_id = p_company)
        and public.staff_can_review_claim(p_claim))))
$$;
-- review_claim: identical to staging body except the first guard (is_staff() -> assignment-scoped)
create or replace function public.review_claim(p_claim uuid, p_decision public.claim_status, p_reason text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare cl company_claims; c companies;
begin
  if not is_staff() or not public.staff_can_review_claim(p_claim) then raise exception 'not authorised for this claim' using errcode='42501'; end if;
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
end $$;

-- ===== F-R6 claim evidence: claimant-only table access, staff only through an audited, time-limited grant =====
create table public.claim_evidence_access_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  claim_id uuid,                     -- deliberately NO foreign key: audit rows must survive deletions (null only if the caller sent a null claim)
  company_id uuid not null,
  purpose text not null,
  evidence_count integer not null,
  at timestamptz not null default now(),
  outcome text not null default 'granted' check (outcome in ('granted','denied','rate_limited','invalid')),
  evidence_ids uuid[] not null default '{}',   -- exact evidence ids opened / for which links were issued
  ttl_seconds integer check (ttl_seconds is null or ttl_seconds between 1 and 600),
  denial_reason text,
  constraint ceal_purpose_when_granted check (outcome <> 'granted' or length(trim(purpose)) >= 5)
);
create trigger ceal_immutable before update or delete on public.claim_evidence_access_log for each row execute function public.block_mutation();
create table public.claim_evidence_grants (
  claim_id uuid not null, staff_id uuid not null, expires_at timestamptz not null, primary key (claim_id, staff_id)
);
create function public.evidence_grant_active(p_claim uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_claim is not null and exists(select 1 from public.claim_evidence_grants g where g.claim_id = p_claim and g.staff_id = auth.uid() and g.expires_at > now())
    and public.staff_can_review_claim(p_claim)
$$;
-- Shared gate for both evidence entry points. NON-RAISING for staff on purpose: a raised exception would roll back the
-- audit row, so denials / rate limits / invalid requests are logged and reported as an outcome. Non-staff get a plain error and no log row.
create function public._evidence_gate(p_claim uuid, p_purpose text, p_ids uuid[], p_ttl integer, p_listing boolean) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); cid uuid; pur text := left(trim(coalesce(p_purpose,'')),500); ids uuid[] := coalesce(p_ids,'{}'); outcome text; reason text; logged uuid[] := '{}';
begin
  if uid is null or not public.is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  select company_id into cid from public.company_claims where id = p_claim;
  cid := coalesce(cid, '00000000-0000-0000-0000-000000000000'::uuid);
  if (select count(*) from public.claim_evidence_access_log l where l.actor_id = uid and l.outcome in ('denied','invalid') and l.at > now() - interval '1 hour') >= 20
     or (select count(*) from public.claim_evidence_access_log l where l.actor_id = uid and l.claim_id = p_claim and l.outcome = 'granted' and l.at > now() - interval '1 hour') >= 10
     or (select count(*) from public.claim_evidence_access_log l where l.actor_id = uid and l.outcome = 'granted' and l.at > now() - interval '1 day') >= 100 then
    outcome := 'rate_limited'; reason := 'rate limit';
  elsif p_claim is null or not public.staff_can_review_claim(p_claim) then
    outcome := 'denied'; reason := 'not assigned or claim closed';
  elsif length(pur) < 5 then
    outcome := 'invalid'; reason := 'purpose required';
  elsif not p_listing and (cardinality(ids) not between 1 and 10 or exists(select 1 from unnest(ids) x where x is null) or (select count(distinct x) from unnest(ids) x) <> cardinality(ids)) then
    outcome := 'invalid'; reason := 'bad evidence id list';
  elsif not p_listing and (p_ttl is null or p_ttl not between 1 and 600) then
    outcome := 'invalid'; reason := 'bad lifetime';
  elsif not p_listing and (select count(*) from public.company_claim_evidence e where e.claim_id = p_claim and e.id = any(ids)) <> cardinality(ids) then
    outcome := 'denied'; reason := 'evidence not on this claim';
  else
    outcome := 'ok';
  end if;
  if outcome = 'ok' then
    if p_listing then select coalesce(array_agg(e.id order by e.created_at), '{}') into ids from public.company_claim_evidence e where e.claim_id = p_claim; end if;
    insert into public.claim_evidence_access_log(actor_id, claim_id, company_id, purpose, evidence_count, outcome, evidence_ids, ttl_seconds)
      values (uid, p_claim, cid, pur, cardinality(ids), 'granted', ids, case when p_listing then null else p_ttl end);
    insert into public.claim_evidence_grants(claim_id, staff_id, expires_at) values (p_claim, uid, now() + interval '10 minutes')
      on conflict (claim_id, staff_id) do update set expires_at = excluded.expires_at;
  elsif not (outcome = 'rate_limited' and exists(select 1 from public.claim_evidence_access_log l where l.actor_id = uid and l.outcome = 'rate_limited' and l.at > now() - interval '1 minute')) then
    -- requested ids are logged only if they are well-formed uuids (they always are: the parameter is uuid[]); never returned to the caller
    insert into public.claim_evidence_access_log(actor_id, claim_id, company_id, purpose, evidence_count, outcome, evidence_ids, ttl_seconds, denial_reason)
      values (uid, p_claim, cid, pur, cardinality(ids), outcome, coalesce(ids,'{}'), case when p_ttl between 1 and 600 then p_ttl end, reason);
  end if;
  return outcome;
end $$;
create function public.staff_open_claim_evidence(p_claim uuid, p_purpose text) returns table(evidence_id uuid, storage_path text, description text, uploaded_at timestamptz, access_expires_at timestamptz, max_signed_url_seconds integer)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if public._evidence_gate(p_claim, p_purpose, null, null, true) <> 'ok' then return; end if;   -- empty result; reason is in the audit log only
  return query select e.id, e.storage_path, e.description, e.created_at, g.expires_at, 600
    from public.company_claim_evidence e join public.claim_evidence_grants g on g.claim_id = e.claim_id and g.staff_id = auth.uid()
    where e.claim_id = p_claim order by e.created_at;
end $$;
-- Edge Function entry point: validates, audits (BEFORE any URL exists) and grants in one step. Returns outcome 'ok'|'denied'|'rate_limited'|'invalid';
-- paths are returned only with 'ok'. Unauthorised callers learn nothing about ids or paths.
create function public.staff_request_evidence_links(p_claim uuid, p_evidence_ids uuid[], p_purpose text, p_ttl integer default 120)
returns table(outcome text, evidence_id uuid, storage_path text, access_expires_at timestamptz, ttl_seconds integer)
language plpgsql security definer set search_path = public, pg_temp as $$
declare o text;
begin
  o := public._evidence_gate(p_claim, p_purpose, p_evidence_ids, p_ttl, false);
  if o <> 'ok' then return query select o, null::uuid, null::text, null::timestamptz, null::integer; return; end if;
  return query select 'ok'::text, e.id, e.storage_path, g.expires_at, p_ttl
    from public.company_claim_evidence e join public.claim_evidence_grants g on g.claim_id = e.claim_id and g.staff_id = auth.uid()
    where e.claim_id = p_claim and e.id = any(p_evidence_ids) order by e.created_at;
end $$;
drop policy cev_read on public.company_claim_evidence;
create policy cev_read on public.company_claim_evidence for select using (public.claim_claimant(claim_id) = auth.uid());
drop policy vd_read on storage.objects;
create policy vd_read on storage.objects for select to authenticated using (bucket_id = 'verification-docs' and (
  public.claim_claimant(public.safe_uuid((storage.foldername(name))[1])) = auth.uid()
  or public.evidence_grant_active(public.safe_uuid((storage.foldername(name))[1]))));

-- ===== F-R1 / F-R3 verified-only access to buyer leads, re-checked at access time =====
create function public.seller_product_enquiry_visible(p_enq uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.enquiries e where e.id = p_enq and e.kind = 'product' and e.company_id is not null and e.delivery = 'visible_to_seller'
    and public.has_company_role(e.company_id, array['owner','manager','sales']::public.member_role[]) and public._company_lead_eligible(e.company_id, e.category_id))
$$;
drop policy enq_company_read on public.enquiries;
create policy enq_company_read on public.enquiries for select using (public.seller_product_enquiry_visible(id));
drop policy enq_status_upd on public.enquiries;
create policy enq_status_upd on public.enquiries for update using (public.seller_product_enquiry_visible(id)) with check (public.seller_product_enquiry_visible(id));
create or replace function public.seller_can_reply(eid uuid) returns boolean language sql stable security definer set search_path to 'public','pg_temp' as $$
  select exists(select 1 from enquiries e where e.id=eid and (
      (e.kind='product' and public.seller_product_enquiry_visible(e.id))
   or (e.kind='requirement' and exists(select 1 from lead_responses lr where lr.enquiry_id=e.id and public.seller_match_visible(lr.company_id, e.id))))) $$;
create or replace function public.respond_to_lead(p_enquiry uuid, p_company uuid) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare e enquiries;
begin
  select * into e from enquiries where id=p_enquiry and kind='requirement';
  if not found then raise exception 'lead not found'; end if;
  if not has_company_role(p_company, array['owner','manager','sales']::member_role[]) or not company_is_live(p_company) then
    raise exception 'not authorised' using errcode='42501'; end if;
  -- verified-only: the lead must have been delivered directly to THIS company and the company must still be eligible now
  if not public.seller_match_visible(p_company, p_enquiry) then raise exception 'lead not available to your company' using errcode='42501'; end if;
  perform check_rate('lead_response',30,interval '1 day');
  insert into lead_responses(enquiry_id,company_id,responded_by) values (p_enquiry,p_company,auth.uid()) on conflict do nothing;
end $$;
create or replace function public.reveal_buyer_contact(p_enquiry uuid, p_company uuid) returns table(buyer_name text, buyer_phone text, buyer_email text, buyer_company text) language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare e enquiries; basis text;
begin
  select * into e from enquiries where id=p_enquiry;
  if not found then raise exception 'not found'; end if;
  if not has_company_role(p_company, array['owner','manager','sales']::member_role[]) then raise exception 'not authorised' using errcode='42501'; end if;
  if e.kind='product' then
    if e.company_id is distinct from p_company or e.delivery <> 'visible_to_seller' or not public._company_lead_eligible(p_company, e.category_id) then raise exception 'not authorised' using errcode='42501'; end if;
    basis := 'product_enquiry';
  else
    if not exists(select 1 from lead_responses where enquiry_id=p_enquiry and company_id=p_company) then raise exception 'respond to the lead first' using errcode='42501'; end if;
    if not public.seller_match_visible(p_company, p_enquiry) then raise exception 'not authorised' using errcode='42501'; end if;
    basis := 'lead_response';
  end if;
  perform check_rate('reveal',100,interval '1 day');
  insert into enquiry_contact_access(enquiry_id,accessor_id,company_id,basis) values (p_enquiry,auth.uid(),p_company,basis);
  return query select ep.buyer_name, ep.buyer_phone, ep.buyer_email, ep.buyer_company from enquiry_private ep where ep.enquiry_id=p_enquiry;
end $$;
-- F-R2: no per-seller notification at requirement creation (delivery notifications belong to the delivery step, disabled until authorised);
--       unclaimed/awaiting-admin notices go to admins only (reviewers see only their ASSIGNED leads under 0002)
create or replace function public.notify_on_enquiry() returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if new.delivery='visible_to_seller' then
    insert into notifications(user_id,company_id,kind,title,body,link)
      select m.user_id,new.company_id,'enquiry','New enquiry: '||left(new.subject,80),'Open Messages to view and reply.','msgs'
      from company_members m left join seller_settings s on s.user_id=m.user_id
      where m.company_id=new.company_id and m.status='active' and m.role in ('owner','manager','sales') and coalesce(s.notify_enquiry,true);
  elsif new.delivery='awaiting_admin' then
    insert into notifications(user_id,company_id,kind,title,body,link)
      select p.id,new.company_id,'admin','Enquiry held for admin','Reference '||new.ref||'. Hold and follow up.','admin/enquiries'
      from profiles p where p.app_role = 'admin';
  end if;
  return new;
end $$;
create or replace function public.submit_enquiry(p_kind enquiry_kind, p_product uuid, p_company uuid, p_category integer, p_subject text, p_quantity numeric, p_unit text, p_message text, p_city text, p_buyer_name text, p_phone text, p_email text, p_buyer_company text, p_consent boolean, p_notice_version text) returns table(enquiry_ref text, delivery enquiry_delivery, notice text) language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare uid uuid := auth.uid(); cid uuid; cat int; d enquiry_delivery; eid uuid; r text; n text;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if not coalesce(p_consent,false) then raise exception 'consent required'; end if;
  if coalesce(trim(p_buyer_name),'')='' then raise exception 'name required'; end if;
  if nullif(trim(p_phone),'') is null and nullif(trim(p_email),'') is null then raise exception 'phone or email required'; end if;
  perform check_rate('enquiry',10,interval '1 hour'); perform check_rate('enquiry_day',30,interval '1 day');
  if p_kind='requirement' then
    -- step 1 of the 2-step requirement flow (step 2 = create_requirement, which matches suppliers). Nothing is delivered here.
    if p_category is null or not exists(select 1 from categories where id=p_category and not hidden) then raise exception 'valid category required'; end if;
    cat := p_category; cid := null; d := 'stored';
    n := 'Your requirement '||'%REF%'||' has been recorded. No supplier has been contacted yet; delivery status will be shown once it is processed.';
  else
  if p_product is not null then
    select p.company_id, p.category_id into cid, cat from products p join companies c on c.id=p.company_id
     where p.id=p_product and p.directory_status='published' and p.data_review_status='approved' and c.directory_status='published';
    if cid is null then raise exception 'product not available'; end if;
    if p_company is not null and p_company<>cid then raise exception 'company does not match product'; end if;
  else
    select id into cid from companies where id=p_company and directory_status='published';
    if cid is null then raise exception 'company not available'; end if;
  end if;
  if public._company_lead_eligible(cid, cat) then
    d := 'visible_to_seller';
    n := 'Your enquiry '||'%REF%'||' has been recorded and is visible to the supplier in their GlobalTradeB2B seller account. We cannot confirm they have read it.';
  elsif company_is_claimed(cid) then
    d := 'awaiting_admin';
    n := 'Your enquiry '||'%REF%'||' has been recorded. This company has not completed GlobalTradeB2B verification for direct enquiries, so your enquiry has NOT been delivered to it directly. Our team holds it and may contact the company.';
  else
    d := 'awaiting_admin';
    n := 'Your enquiry '||'%REF%'||' has been recorded. This company has not joined GlobalTradeB2B, so your enquiry has NOT been sent to them. Our team holds it and may contact the company.';
  end if;
  end if;
  insert into enquiries(kind,buyer_id,product_id,company_id,category_id,subject,quantity,unit,message,city,delivery)
    values (p_kind,uid,p_product,cid,cat,left(trim(p_subject),200),p_quantity,left(p_unit,30),left(p_message,2000),left(p_city,80),d)
    returning id, ref into eid, r;
  insert into enquiry_private(enquiry_id,buyer_name,buyer_phone,buyer_email,buyer_company,consent_at,notice_version)
    values (eid,left(trim(p_buyer_name),120),left(nullif(trim(p_phone),''),30),left(nullif(trim(p_email),''),160),left(p_buyer_company,160),now(),coalesce(p_notice_version,'v1'));
  if p_kind='product' and d='awaiting_admin' then
    -- C1: held product enquiries enter the Admin Lead Desk (assignment-scoped like requirement cases)
    insert into lead_cases(enquiry_id,queue) values (eid,'product_enquiry_review') on conflict (enquiry_id) do nothing;
    insert into lead_distribution_events(enquiry_id,company_id,event,reason) values (eid,cid,'routed_admin','product enquiry held: supplier not eligible for direct delivery') on conflict do nothing;
  end if;
  return query select r, d, replace(n,'%REF%',r);
end $$;

-- ===== F-R7 legacy company_private: owner/manager only (staff read supplier contacts only through the audited vault functions) =====
drop policy cpriv_read on public.company_private;
create policy cpriv_read on public.company_private for select using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role]));
drop policy cpriv_upd on public.company_private;
create policy cpriv_upd on public.company_private for update using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role])) with check (has_company_role(company_id, array['owner'::member_role,'manager'::member_role]));
drop policy cpriv_write on public.company_private;
create policy cpriv_write on public.company_private for insert with check (has_company_role(company_id, array['owner'::member_role,'manager'::member_role]));

-- ===== F-R8 profiles: staff no longer read every user's profile (phone etc.) =====
drop policy profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles for select using (id = auth.uid() or is_admin() or (is_staff() and app_role in ('admin','reviewer')));

-- ===== F-R9 force RLS on every table added by 0001-0006 (matches all 46 existing tables) + new object privileges =====
do $$ declare t text; begin
  foreach t in array array['company_contacts','contact_access_log','lead_routing_settings','requirement_details','requirement_matches','lead_cases','lead_status_history','lead_distribution_events','claim_verifications','claim_verification_outbox','claim_invitations','claim_reviewer_assignments','claim_evidence_access_log','claim_evidence_grants'] loop
    execute format('alter table public.%I force row level security', t); end loop;
  foreach t in array array['claim_reviewer_assignments','claim_evidence_access_log','claim_evidence_grants'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t); end loop;
end $$;
grant select on public.claim_reviewer_assignments, public.claim_evidence_access_log to authenticated;
create policy cra_read on public.claim_reviewer_assignments for select to authenticated using (public.is_admin() or reviewer_id = auth.uid());
create policy ceal_admin_read on public.claim_evidence_access_log for select to authenticated using (public.is_admin());

-- ===== C1 product enquiries held for admin review: Admin Lead Desk queue + guarded release =====
alter table public.lead_cases drop constraint lead_cases_queue_check;
alter table public.lead_cases add constraint lead_cases_queue_check check (queue in ('unclaimed_matches','unverified_matches','capped_eligible','unmatched','product_enquiry_review'));
-- Existing staff_mark_enquiry let any staff who can see an enquiry set delivery='visible_to_seller' for ANY supplier (buyer would be told the
-- supplier can see it). Now: only for product enquiries whose supplier is currently eligible; requirements are delivered by matching only.
-- Releasing creates the seller notification (in-app row only; no email/SMS exists in this schema) and closes the desk case.
create or replace function public.staff_mark_enquiry(p_enquiry uuid, p_delivery enquiry_delivery, p_note text, p_provider_ref text default null) returns void
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare e enquiries;
begin
  if not public.is_staff() or not public.staff_can_see_enquiry(p_enquiry) then raise exception 'staff only' using errcode = '42501'; end if;
  select * into e from public.enquiries where id = p_enquiry;
  if not found then raise exception 'enquiry not found'; end if;
  if p_delivery = 'sent_external' and coalesce(trim(p_provider_ref),'') = '' then raise exception 'sent_external requires a provider reference'; end if;
  if p_delivery = 'visible_to_seller' then
    if e.kind <> 'product' then raise exception 'requirement delivery is decided by supplier matching, not by manual marking' using errcode='42501'; end if;
    if e.company_id is null or not public._company_lead_eligible(e.company_id, e.category_id) then
      raise exception 'supplier is not eligible for direct delivery; enquiry stays with the admin desk' using errcode='42501'; end if;
  end if;
  update public.enquiries set delivery = p_delivery, delivery_note = left(coalesce(p_note,'') || case when p_provider_ref is not null then ' [ref ' || p_provider_ref || ']' else '' end, 500) where id = p_enquiry;
  if p_delivery = 'visible_to_seller' and e.delivery is distinct from 'visible_to_seller' then
    insert into public.notifications(user_id,company_id,kind,title,body,link)
      select m.user_id,e.company_id,'enquiry','New enquiry: '||left(e.subject,80),'Open Messages to view and reply.','msgs'
      from public.company_members m left join public.seller_settings s on s.user_id=m.user_id
      where m.company_id=e.company_id and m.status='active' and m.role in ('owner','manager','sales') and coalesce(s.notify_enquiry,true);
  end if;
  if p_delivery in ('visible_to_seller','sent_external') then
    update public.lead_cases set status='closed', closed_at=now() where enquiry_id=p_enquiry and queue='product_enquiry_review' and status<>'closed';
  end if;
end $$;

-- ===== DECISION 2: messages, quotations, orders =====
-- orders: buyer, seller roles, ADMIN only (no general staff access).
-- direct_threads/direct_messages/enquiry_replies/quotations: buyer + seller roles + ADMIN; other staff ONLY for an ASSIGNED enquiry
-- (admin or lead_cases.assigned_to) AND only while an audited 10-minute communications grant is active (staff_open_enquiry_comms).
-- A direct thread is "associated" with an assigned enquiry when the thread buyer is the enquiry buyer and the thread company is the
-- enquiry's company or a matched company of that requirement.
-- Admin reads through RLS are not individually logged (admin oversight); staff reads are always preceded by a logged grant.
create table public.staff_comms_access_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null, enquiry_id uuid not null,   -- no FK: audit rows survive deletions
  purpose text not null check (length(trim(purpose)) >= 5), at timestamptz not null default now());
create trigger scal_immutable before update or delete on public.staff_comms_access_log for each row execute function public.block_mutation();
create table public.staff_comms_grants (enquiry_id uuid not null, staff_id uuid not null, expires_at timestamptz not null, primary key (enquiry_id, staff_id));
create function public.comms_grant_active(p_enq uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_enq is not null and public.is_staff() and public.staff_can_see_enquiry(p_enq)
     and exists(select 1 from public.staff_comms_grants g where g.enquiry_id = p_enq and g.staff_id = auth.uid() and g.expires_at > now())
$$;
create function public.staff_thread_comms_ok(p_thread uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_staff() and exists(
    select 1 from public.direct_threads t join public.enquiries e on e.buyer_id = t.buyer_id
      and (e.company_id = t.company_id or exists(select 1 from public.requirement_matches rm where rm.enquiry_id = e.id and rm.company_id = t.company_id))
    where t.id = p_thread and public.comms_grant_active(e.id))
$$;
create function public.staff_open_enquiry_comms(p_enquiry uuid, p_purpose text) returns timestamptz language plpgsql security definer set search_path = public, pg_temp as $$
declare exp timestamptz := now() + interval '10 minutes';
begin
  if not public.is_staff() or not public.staff_can_see_enquiry(p_enquiry) then raise exception 'not authorised for this enquiry' using errcode = '42501'; end if;
  if coalesce(length(trim(p_purpose)),0) < 5 then raise exception 'purpose required (min 5 characters)'; end if;
  perform public.check_rate('comms_open', 200, interval '1 day');
  insert into public.staff_comms_access_log(actor_id, enquiry_id, purpose) values (auth.uid(), p_enquiry, trim(p_purpose));
  insert into public.staff_comms_grants(enquiry_id, staff_id, expires_at) values (p_enquiry, auth.uid(), exp)
    on conflict (enquiry_id, staff_id) do update set expires_at = excluded.expires_at;
  return exp;
end $$;
drop policy dt_read on public.direct_threads;
create policy dt_read on public.direct_threads for select using (buyer_id = auth.uid() or has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin() or public.staff_thread_comms_ok(id));
drop policy dm_read on public.direct_messages;
create policy dm_read on public.direct_messages for select using (thread_buyer(thread_id) = auth.uid() or has_company_role(thread_company(thread_id), array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin() or public.staff_thread_comms_ok(thread_id));
drop policy orders_read on public.orders;
create policy orders_read on public.orders for select using (buyer_id = auth.uid() or has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin());
drop policy replies_read on public.enquiry_replies;
create policy replies_read on public.enquiry_replies for select using (enquiry_buyer(enquiry_id) = auth.uid() or seller_can_reply(enquiry_id) or is_admin() or public.comms_grant_active(enquiry_id));
drop policy quotes_read on public.quotations;
create policy quotes_read on public.quotations for select using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or is_admin() or public.comms_grant_active(enquiry_id) or ((enquiry_buyer(enquiry_id) = auth.uid()) and (status = any (array['sent'::quote_status,'accepted'::quote_status,'declined'::quote_status,'expired'::quote_status]) or (status = 'withdrawn'::quote_status and sent_at is not null))));
alter table public.staff_comms_access_log enable row level security; alter table public.staff_comms_access_log force row level security;
alter table public.staff_comms_grants enable row level security; alter table public.staff_comms_grants force row level security;
revoke all on public.staff_comms_access_log, public.staff_comms_grants from public, anon, authenticated;
grant select on public.staff_comms_access_log to authenticated;
create policy scal_admin_read on public.staff_comms_access_log for select to authenticated using (public.is_admin());
revoke all on function public.comms_grant_active(uuid), public.staff_thread_comms_ok(uuid), public.staff_open_enquiry_comms(uuid,text) from public, anon, authenticated;
grant execute on function public.comms_grant_active(uuid), public.staff_thread_comms_ok(uuid), public.staff_open_enquiry_comms(uuid,text) to authenticated;

-- ===== DECISION 1: publication is admin-only; reviewers recommend on assigned records =====
create function public.staff_assigned_to_company(p_company uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and (
    exists(select 1 from public.claim_reviewer_assignments a join public.company_claims c on c.id = a.claim_id
            where a.reviewer_id = auth.uid() and c.company_id = p_company and c.status in ('claim_submitted','evidence_requested','under_review'))
    or exists(select 1 from public.lead_cases lc join public.requirement_matches rm on rm.enquiry_id = lc.enquiry_id
            where lc.assigned_to = auth.uid() and rm.company_id = p_company and lc.status <> 'closed')
    or exists(select 1 from public.lead_cases lc join public.enquiries e on e.id = lc.enquiry_id
            where lc.assigned_to = auth.uid() and e.company_id = p_company and lc.status <> 'closed')))
$$;
create table public.review_recommendations (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('company','product','product_image')),
  target_id uuid not null, company_id uuid not null,
  recommendation text not null check (recommendation in ('approve','reject','needs_changes','publish','unpublish')),
  note text not null check (length(trim(note)) >= 5),
  reviewer_id uuid not null, created_at timestamptz not null default now());
create trigger rr_immutable before update or delete on public.review_recommendations for each row execute function public.block_mutation();
create function public.staff_recommend_review(p_target text, p_id uuid, p_recommendation text, p_note text) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare cid uuid; rid uuid;
begin
  if not public.is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  if p_target = 'company' then cid := p_id;
  elsif p_target = 'product' then select company_id into cid from public.products where id = p_id;
  elsif p_target = 'product_image' then select p.company_id into cid from public.product_images i join public.products p on p.id = i.product_id where i.id = p_id;
  else raise exception 'unknown target'; end if;
  if cid is null or not exists(select 1 from public.companies where id = cid) then raise exception 'target not found'; end if;
  if not public.staff_assigned_to_company(cid) then raise exception 'not assigned to this record' using errcode = '42501'; end if;
  insert into public.review_recommendations(target_type, target_id, company_id, recommendation, note, reviewer_id)
    values (p_target, p_id, cid, p_recommendation, trim(p_note), auth.uid()) returning id into rid;
  insert into public.moderation_actions(target_type, target_id, action, reason, admin_id) values (case when p_target = 'product_image' then 'image' else p_target end, p_id::text, 'recommendation:' || p_recommendation, left(p_note, 500), auth.uid());
  return rid;
end $$;
alter table public.review_recommendations enable row level security; alter table public.review_recommendations force row level security;
revoke all on public.review_recommendations from public, anon, authenticated; grant select on public.review_recommendations to authenticated;
create policy rr_read on public.review_recommendations for select to authenticated using (public.is_admin() or reviewer_id = auth.uid());
revoke all on function public.staff_assigned_to_company(uuid), public.staff_recommend_review(text,uuid,text,text) from public, anon, authenticated;
grant execute on function public.staff_assigned_to_company(uuid), public.staff_recommend_review(text,uuid,text,text) to authenticated;
-- same bodies as staging (incl. moderation_actions audit); only the first guard changes: is_staff() -> is_admin()
create or replace function public.set_data_review(p_target text, p_id uuid, p_status review_status, p_note text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if not is_admin() then raise exception 'admin only: reviewers may recommend, not decide' using errcode='42501'; end if;
  if p_target='company' then
    update companies set data_review_status=p_status, data_reviewed_by=auth.uid(), data_reviewed_at=now(),
        directory_status=case when p_status='approved' then directory_status when p_status='rejected' then 'rejected' when directory_status='published' then 'pending_review' else directory_status end
     where id=p_id;
  elsif p_target='product' then
    update products set data_review_status=p_status, data_reviewed_by=auth.uid(), data_reviewed_at=now(),
        rejected_reason=case when p_status='rejected' then p_note end,
        directory_status=case when p_status='approved' then directory_status when p_status='rejected' then 'rejected' when directory_status='published' then 'pending_review' else directory_status end
     where id=p_id;
  else raise exception 'unknown target'; end if;
  if not found then raise exception 'target not found'; end if;
  insert into moderation_actions(target_type,target_id,action,reason,admin_id) values (p_target,p_id::text,'data_review:'||p_status::text,p_note,auth.uid());
end $$;
create or replace function public.set_directory_status(p_target text, p_id uuid, p_status directory_status, p_reason text) returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if not is_admin() then raise exception 'admin only: reviewers may recommend, not decide' using errcode='42501'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'reason required'; end if;
  if p_target='company' then update companies set directory_status=p_status where id=p_id;
  elsif p_target='product' then update products set directory_status=p_status, rejected_reason=case when p_status='rejected' then p_reason end where id=p_id;
  else raise exception 'unknown target'; end if;
  if not found then raise exception 'target not found'; end if;
  insert into moderation_actions(target_type,target_id,action,reason,admin_id) values (p_target,p_id::text,'status:'||p_status::text,p_reason,auth.uid());
end $$;

-- ===== DECISION 3: explicit revocation of a reviewer's evidence access =====
create function public.admin_unassign_claim_reviewer(p_claim uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  delete from public.claim_evidence_grants where claim_id = p_claim;
  delete from public.claim_reviewer_assignments where claim_id = p_claim;
  insert into public.audit_log(actor_id, actor_role, action, entity, entity_id, new_value) values (auth.uid(), current_user, 'claim_reviewer_unassigned', 'company_claims', p_claim::text, '{}'::jsonb);
end $$;
revoke all on function public.admin_unassign_claim_reviewer(uuid) from public, anon, authenticated; grant execute on function public.admin_unassign_claim_reviewer(uuid) to authenticated;

-- =====================================================================================================================
-- ROUND 4 (A) the remaining staff-wide policies: assignment-scoped (staff_assigned_to_company = admin OR assigned staff) or admin-only.
-- Decision table: docs/STAFF_POLICY_DECISIONS.md. Kept staff-wide with documented reason: categories_read_auth, cms_read_auth,
-- profiles_self_read (staff directory, no buyer data), cinv_read (already scoped to creator/admin by 0004).
-- =====================================================================================================================
drop policy audit_read on public.audit_log;                 create policy audit_read on public.audit_log for select using (is_admin());
drop policy bro_read on public.brochures;                   create policy bro_read on public.brochures for select using (is_company_member(company_id) or public.staff_assigned_to_company(company_id));
drop policy companies_read on public.companies;             create policy companies_read on public.companies for select using (is_company_member(id) or user_is_claimant(id) or public.staff_assigned_to_company(id));
drop policy companies_staff_update on public.companies;     create policy companies_staff_update on public.companies for update using (public.staff_assigned_to_company(id)) with check (public.staff_assigned_to_company(id));
drop policy cacq_staff on public.company_acquisition;       create policy cacq_staff on public.company_acquisition for all using (public.staff_assigned_to_company(company_id)) with check (public.staff_assigned_to_company(company_id));
drop policy ccat_read on public.company_categories;         create policy ccat_read on public.company_categories for select using (company_is_live(company_id) or is_company_member(company_id) or public.staff_assigned_to_company(company_id));
drop policy ccat_write on public.company_categories;        create policy ccat_write on public.company_categories for all using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role]) or is_admin()) with check (has_company_role(company_id, array['owner'::member_role,'manager'::member_role]) or is_admin());
drop policy corr_read on public.company_data_corrections;   create policy corr_read on public.company_data_corrections for select using (reporter_id = auth.uid() or public.staff_assigned_to_company(company_id) or has_company_role(company_id, array['owner'::member_role,'manager'::member_role]));
drop policy corr_staff_upd on public.company_data_corrections; create policy corr_staff_upd on public.company_data_corrections for update using (public.staff_assigned_to_company(company_id)) with check (public.staff_assigned_to_company(company_id) and reviewed_by = auth.uid());
drop policy cfu_staff on public.company_follow_ups;         create policy cfu_staff on public.company_follow_ups for all using (public.staff_assigned_to_company(company_id)) with check (public.staff_assigned_to_company(company_id));
drop policy cimg_del on public.company_images;              create policy cimg_del on public.company_images for delete using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(company_id));
drop policy cimg_ins on public.company_images;              create policy cimg_ins on public.company_images for insert with check (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(company_id));
drop policy cimg_read on public.company_images;             create policy cimg_read on public.company_images for select using (is_company_member(company_id) or public.staff_assigned_to_company(company_id));
drop policy cimg_upd on public.company_images;              create policy cimg_upd on public.company_images for update using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(company_id)) with check (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(company_id));
drop policy cimp_b on public.company_import_batches;        create policy cimp_b on public.company_import_batches for all using (is_admin()) with check (is_admin() and operator_id = auth.uid());
drop policy cimp_r on public.company_import_rows;           create policy cimp_r on public.company_import_rows for all using (is_admin()) with check (is_admin());
drop policy cnote_ins on public.company_internal_notes;     create policy cnote_ins on public.company_internal_notes for insert with check (is_staff() and author_id = auth.uid() and public.staff_assigned_to_company(company_id));
drop policy cnote_read on public.company_internal_notes;    create policy cnote_read on public.company_internal_notes for select using (public.staff_assigned_to_company(company_id));
drop policy members_read on public.company_members;         create policy members_read on public.company_members for select using (user_id = auth.uid() or is_company_member(company_id) or public.staff_assigned_to_company(company_id));
drop policy cma_read on public.company_membership_audit;    create policy cma_read on public.company_membership_audit for select using (is_admin());
drop policy cout_insert on public.company_outreach_events;  create policy cout_insert on public.company_outreach_events for insert with check (is_staff() and recorded_by = auth.uid() and public.staff_assigned_to_company(company_id));
drop policy cout_read on public.company_outreach_events;    create policy cout_read on public.company_outreach_events for select using (public.staff_assigned_to_company(company_id));
drop policy csrc_staff on public.company_sources;           create policy csrc_staff on public.company_sources for all using (public.staff_assigned_to_company(company_id)) with check (public.staff_assigned_to_company(company_id));
drop policy cvr_read on public.company_verification_reviews; create policy cvr_read on public.company_verification_reviews for select using (public.staff_assigned_to_company(company_id));
drop policy eca_read on public.enquiry_contact_access;      create policy eca_read on public.enquiry_contact_access for select using (is_admin());
drop policy lr_read on public.lead_responses;               create policy lr_read on public.lead_responses for select using (is_company_member(company_id) or enquiry_buyer(enquiry_id) = auth.uid() or public.staff_can_see_enquiry(enquiry_id));
drop policy media_admin on public.media_assets;             create policy media_admin on public.media_assets for all using (is_admin()) with check (is_admin());
drop policy mod_read on public.moderation_actions;          create policy mod_read on public.moderation_actions for select using (is_admin() or admin_id = auth.uid());
drop policy pimg_del on public.product_images;              create policy pimg_del on public.product_images for delete using (has_company_role(product_company(product_id), array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(product_company(product_id)));
drop policy pimg_read on public.product_images;             create policy pimg_read on public.product_images for select using (is_company_member(product_company(product_id)) or public.staff_assigned_to_company(product_company(product_id)));
drop policy views_read on public.product_view_events;       create policy views_read on public.product_view_events for select using (is_company_member(company_id) or is_admin());
drop policy products_read on public.products;               create policy products_read on public.products for select using (is_company_member(company_id) or public.staff_assigned_to_company(company_id));
drop policy products_staff_upd on public.products;          create policy products_staff_upd on public.products for update using (public.staff_assigned_to_company(company_id)) with check (public.staff_assigned_to_company(company_id));
drop policy fb_staff on public.seller_feedback;             create policy fb_staff on public.seller_feedback for select using (is_admin());
drop policy supp_staff on public.suppression_list;          create policy supp_staff on public.suppression_list for all using (is_admin()) with check (is_admin());
-- storage policies that also used bare is_staff()
drop policy bro_obj_read on storage.objects;  create policy bro_obj_read on storage.objects for select to authenticated using (bucket_id = 'brochures' and (is_company_member(safe_uuid((storage.foldername(name))[1])) or public.staff_assigned_to_company(safe_uuid((storage.foldername(name))[1]))));
drop policy bro_obj_write on storage.objects; create policy bro_obj_write on storage.objects for all to authenticated using (bucket_id = 'brochures' and (has_company_role(safe_uuid((storage.foldername(name))[1]), array['owner'::member_role,'manager'::member_role]) or public.staff_assigned_to_company(safe_uuid((storage.foldername(name))[1])))) with check (bucket_id = 'brochures' and (has_company_role(safe_uuid((storage.foldername(name))[1]), array['owner'::member_role,'manager'::member_role]) or public.staff_assigned_to_company(safe_uuid((storage.foldername(name))[1]))));
drop policy cap_write on storage.objects;     create policy cap_write on storage.objects for all to authenticated using (bucket_id = 'company-assets-public' and (has_company_role(safe_uuid((storage.foldername(name))[1]), array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or is_admin())) with check (bucket_id = 'company-assets-public' and (has_company_role(safe_uuid((storage.foldername(name))[1]), array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or is_admin()));
drop policy pmp_pending_rw on storage.objects; create policy pmp_pending_rw on storage.objects for all to authenticated using (bucket_id = 'product-media-pending' and (has_company_role(safe_uuid((storage.foldername(name))[1]), array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(safe_uuid((storage.foldername(name))[1])))) with check (bucket_id = 'product-media-pending' and (has_company_role(safe_uuid((storage.foldername(name))[1]), array['owner'::member_role,'manager'::member_role,'catalogue_editor'::member_role]) or public.staff_assigned_to_company(safe_uuid((storage.foldername(name))[1]))));
drop policy pmp_public_staff on storage.objects; create policy pmp_public_staff on storage.objects for all to authenticated using (bucket_id = 'product-media-public' and is_admin()) with check (bucket_id = 'product-media-public' and is_admin());
-- import_normalize: same body as staging, guard is_staff() -> is_admin() (import tables are now admin-only)
create or replace function public.import_normalize(p_batch uuid) returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare r record; errs text[]; m uuid; supp boolean; k text; cnt jsonb;
begin
  if not is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  for r in select * from company_import_rows where batch_id=p_batch and status in ('staged','invalid','duplicate_review','suppressed') order by row_no loop
    errs := '{}';
    if coalesce(trim(r.name),'')='' then errs := array_append(errs,'name missing'); end if;
    if r.website is not null and r.website !~* '^https?://[^ ]+\\.[^ ]+$' then errs := array_append(errs,'website not a valid http(s) URL'); end if;
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
end $$;

-- ===== ROUND 4 (B) product image approval: admin-only, provenance + licence + representation, immutable audit =====
alter table public.product_images add column representation text check (representation in ('actual_product','illustrative'));
drop function public.approve_product_image(uuid, text);
create function public.approve_product_image(p_image uuid, p_public_path text, p_representation text, p_note text) returns void
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare im product_images; has_url boolean; has_ev boolean;
begin
  if not is_admin() then raise exception 'admin only: reviewers may recommend, not approve' using errcode='42501'; end if;
  if coalesce(length(trim(p_note)),0) < 5 then raise exception 'approval note required (basis for the decision)'; end if;
  select * into im from product_images where id = p_image for update;
  if not found then raise exception 'image not found'; end if;
  if p_representation is distinct from 'actual_product' then
    raise exception 'only images showing the actual supplier product can be published; illustrative images are not publishable' using errcode='23514'; end if;
  if im.rights_status not in ('owned','licensed','permission_granted','public_domain') then raise exception 'image rights not cleared'; end if;
  has_url := coalesce(trim(im.image_source_url),'') <> '';
  has_ev  := coalesce(trim(im.permission_evidence),'') <> '';
  if not has_url and not has_ev then raise exception 'provenance required: source URL or permission evidence'; end if;
  if has_url and im.image_source_url !~* '^https?://[^ ]+\.[^ ]+$' then raise exception 'source URL is not a valid http(s) URL'; end if;
  if im.rights_status in ('licensed','permission_granted') and not has_ev then raise exception 'licence or supplier authorisation evidence required'; end if;
  if im.rights_status = 'public_domain' and not has_url then raise exception 'public-domain claim needs a source URL'; end if;
  if p_public_path is null or p_public_path !~ '^[a-z0-9][a-z0-9/_.-]{3,200}$' or p_public_path like '%..%' then raise exception 'invalid public path'; end if;
  update product_images set review_status='approved', public_path=p_public_path, representation=p_representation, reviewed_by=auth.uid(), reviewed_at=now() where id = p_image;
  insert into moderation_actions(target_type,target_id,action,reason,admin_id)
    values ('image', p_image::text, 'image_approved:' || im.rights_status::text || ':' || p_representation, left(trim(p_note),500), auth.uid());
end $$;
revoke all on function public.approve_product_image(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.approve_product_image(uuid,text,text,text) to authenticated;

-- ===== ROUND 4 (C) buyer contact: purpose-required, audited, expiring access (no direct table bypass) =====
create table public.buyer_contact_access_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null, actor_role text not null, enquiry_id uuid not null, buyer_id uuid not null,   -- no FKs: audit rows survive deletions
  action text not null check (action in ('open_contact')),
  purpose text not null check (length(trim(purpose)) >= 5), at timestamptz not null default now());
create trigger bcal_immutable before update or delete on public.buyer_contact_access_log for each row execute function public.block_mutation();
create table public.buyer_contact_grants (enquiry_id uuid not null, staff_id uuid not null, expires_at timestamptz not null, primary key (enquiry_id, staff_id));
-- recheck at EVERY read: admin, or staff whose assigned lead case for this enquiry is still open; plus an unexpired grant
create function public.buyer_contact_grant_active(p_enq uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_enq is not null and public.is_staff()
    and (public.is_admin() or exists(select 1 from public.lead_cases lc where lc.enquiry_id = p_enq and lc.assigned_to = auth.uid() and lc.status <> 'closed'))
    and exists(select 1 from public.buyer_contact_grants g where g.enquiry_id = p_enq and g.staff_id = auth.uid() and g.expires_at > now())
$$;
create function public.staff_open_buyer_contact(p_enquiry uuid, p_purpose text) returns table(buyer_name text, buyer_phone text, buyer_email text, buyer_company text, access_expires_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare exp timestamptz := now() + interval '10 minutes'; bid uuid;
begin
  select buyer_id into bid from public.enquiries where id = p_enquiry;
  if bid is null then raise exception 'enquiry not found'; end if;
  if not public.is_staff() or not (public.is_admin() or exists(select 1 from public.lead_cases lc where lc.enquiry_id = p_enquiry and lc.assigned_to = auth.uid() and lc.status <> 'closed')) then
    raise exception 'not authorised for this enquiry' using errcode = '42501'; end if;
  if coalesce(length(trim(p_purpose)),0) < 5 then raise exception 'purpose required (min 5 characters)'; end if;
  perform public.check_rate('buyer_contact_open', 100, interval '1 day');
  insert into public.buyer_contact_access_log(actor_id, actor_role, enquiry_id, buyer_id, action, purpose) values (auth.uid(), current_user, p_enquiry, bid, 'open_contact', trim(p_purpose));
  insert into public.buyer_contact_grants(enquiry_id, staff_id, expires_at) values (p_enquiry, auth.uid(), exp)
    on conflict (enquiry_id, staff_id) do update set expires_at = excluded.expires_at;
  return query select ep.buyer_name, ep.buyer_phone, ep.buyer_email, ep.buyer_company, exp from public.enquiry_private ep where ep.enquiry_id = p_enquiry;
end $$;
create function public.admin_revoke_buyer_contact_access(p_enquiry uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  delete from public.buyer_contact_grants where enquiry_id = p_enquiry;
  insert into public.audit_log(actor_id, actor_role, action, entity, entity_id, new_value) values (auth.uid(), current_user, 'buyer_contact_grants_revoked', 'enquiries', p_enquiry::text, '{}'::jsonb);
end $$;
drop policy epriv_read on public.enquiry_private;
create policy epriv_read on public.enquiry_private for select using (enquiry_buyer(enquiry_id) = auth.uid() or public.buyer_contact_grant_active(enquiry_id));
alter table public.buyer_contact_access_log enable row level security; alter table public.buyer_contact_access_log force row level security;
alter table public.buyer_contact_grants enable row level security; alter table public.buyer_contact_grants force row level security;
revoke all on public.buyer_contact_access_log, public.buyer_contact_grants from public, anon, authenticated;
grant select on public.buyer_contact_access_log to authenticated;
create policy bcal_admin_read on public.buyer_contact_access_log for select to authenticated using (public.is_admin());
revoke all on function public.buyer_contact_grant_active(uuid), public.staff_open_buyer_contact(uuid,text), public.admin_revoke_buyer_contact_access(uuid) from public, anon, authenticated;
grant execute on function public.buyer_contact_grant_active(uuid), public.staff_open_buyer_contact(uuid,text), public.admin_revoke_buyer_contact_access(uuid) to authenticated;

-- ===== ROUND 6 evidence-link service: staff_request_evidence_links (defined with the evidence section above) =====
revoke all on function public._evidence_gate(uuid,text,uuid[],integer,boolean) from public, anon, authenticated;
revoke all on function public.staff_request_evidence_links(uuid,uuid[],text,integer) from public, anon, authenticated;
grant execute on function public.staff_request_evidence_links(uuid,uuid[],text,integer) to authenticated;

revoke all on function public.admin_assign_claim_reviewer(uuid,uuid), public.evidence_grant_active(uuid), public.staff_open_claim_evidence(uuid,text), public.seller_product_enquiry_visible(uuid) from public, anon;
grant execute on function public.admin_assign_claim_reviewer(uuid,uuid), public.evidence_grant_active(uuid), public.staff_open_claim_evidence(uuid,text), public.seller_product_enquiry_visible(uuid) to authenticated;
commit;

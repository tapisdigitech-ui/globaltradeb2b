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
  claim_id uuid not null,            -- deliberately NO foreign key: audit rows must survive deletions
  company_id uuid not null,
  purpose text not null check (length(trim(purpose)) >= 5),
  evidence_count integer not null,
  at timestamptz not null default now()
);
create trigger ceal_immutable before update or delete on public.claim_evidence_access_log for each row execute function public.block_mutation();
create table public.claim_evidence_grants (
  claim_id uuid not null, staff_id uuid not null, expires_at timestamptz not null, primary key (claim_id, staff_id)
);
create function public.evidence_grant_active(p_claim uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_claim is not null and exists(select 1 from public.claim_evidence_grants g where g.claim_id = p_claim and g.staff_id = auth.uid() and g.expires_at > now())
    and public.staff_can_review_claim(p_claim)
$$;
create function public.staff_open_claim_evidence(p_claim uuid, p_purpose text) returns table(evidence_id uuid, storage_path text, description text, uploaded_at timestamptz, access_expires_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare cid uuid; n int; exp timestamptz := now() + interval '10 minutes';
begin
  if not public.staff_can_review_claim(p_claim) then raise exception 'not authorised for this claim' using errcode = '42501'; end if;
  if coalesce(length(trim(p_purpose)),0) < 5 then raise exception 'purpose required (min 5 characters)'; end if;
  perform public.check_rate('evidence_open', 100, interval '1 day');
  select company_id into cid from public.company_claims where id = p_claim;
  select count(*) into n from public.company_claim_evidence e where e.claim_id = p_claim;
  insert into public.claim_evidence_access_log(actor_id, claim_id, company_id, purpose, evidence_count) values (auth.uid(), p_claim, cid, trim(p_purpose), n);
  insert into public.claim_evidence_grants(claim_id, staff_id, expires_at) values (p_claim, auth.uid(), exp)
    on conflict (claim_id, staff_id) do update set expires_at = excluded.expires_at;
  return query select e.id, e.storage_path, e.description, e.created_at, exp from public.company_claim_evidence e where e.claim_id = p_claim order by e.created_at;
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

revoke all on function public.admin_assign_claim_reviewer(uuid,uuid), public.evidence_grant_active(uuid), public.staff_open_claim_evidence(uuid,text), public.seller_product_enquiry_visible(uuid) from public, anon;
grant execute on function public.admin_assign_claim_reviewer(uuid,uuid), public.evidence_grant_active(uuid), public.staff_open_claim_evidence(uuid,text), public.seller_product_enquiry_visible(uuid) to authenticated;
commit;

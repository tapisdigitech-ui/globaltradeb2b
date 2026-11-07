-- DOWN for 0006_real_schema_hardening. DRAFT, not applied to any Supabase project.
-- Restores the exact post-0005 definitions (generated from a local replica of the staging schema + migrations 0001-0005).
begin;
-- policies first (they reference functions that are dropped below)
drop policy cev_read on public.company_claim_evidence;
create policy cev_read on public.company_claim_evidence for select using (((claim_claimant(claim_id) = auth.uid()) OR is_staff()));
drop policy vd_read on storage.objects;
create policy vd_read on storage.objects for select to authenticated using (((bucket_id = 'verification-docs'::text) AND ((claim_claimant(safe_uuid((storage.foldername(name))[1])) = auth.uid()) OR staff_can_review_claim(safe_uuid((storage.foldername(name))[1])))));
drop policy enq_company_read on public.enquiries;
create policy enq_company_read on public.enquiries for select using (((company_id IS NOT NULL) AND has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role])));
drop policy enq_status_upd on public.enquiries;
create policy enq_status_upd on public.enquiries for update using (((company_id IS NOT NULL) AND has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role]))) with check (((company_id IS NOT NULL) AND has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role, 'sales'::member_role])));
drop policy cpriv_read on public.company_private;
create policy cpriv_read on public.company_private for select using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
drop policy cpriv_upd on public.company_private;
create policy cpriv_upd on public.company_private for update using ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff())) with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
drop policy cpriv_write on public.company_private;
create policy cpriv_write on public.company_private for insert with check ((has_company_role(company_id, ARRAY['owner'::member_role, 'manager'::member_role]) OR is_staff()));
drop policy profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles for select using (((id = auth.uid()) OR is_staff()));
drop policy cra_read on public.claim_reviewer_assignments; drop policy ceal_admin_read on public.claim_evidence_access_log;
-- F-R9: 0006 forced RLS on these 0001-0005 tables; restore non-forced state
alter table public.claim_invitations no force row level security;
alter table public.claim_verification_outbox no force row level security;
alter table public.claim_verifications no force row level security;
alter table public.company_contacts no force row level security;
alter table public.contact_access_log no force row level security;
alter table public.lead_cases no force row level security;
alter table public.lead_distribution_events no force row level security;
alter table public.lead_routing_settings no force row level security;
alter table public.lead_status_history no force row level security;
alter table public.requirement_details no force row level security;
alter table public.requirement_matches no force row level security;
-- new objects
drop function public.staff_open_claim_evidence(uuid,text); drop function public.evidence_grant_active(uuid); drop function public.admin_assign_claim_reviewer(uuid,uuid); drop function public.seller_product_enquiry_visible(uuid);
drop table public.claim_evidence_grants; drop table public.claim_evidence_access_log; drop table public.claim_reviewer_assignments;
-- replaced functions (restore post-0005 bodies)
CREATE OR REPLACE FUNCTION public.guard_company_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_can_review_claim(p_claim uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.company_claims c where c.id = p_claim and c.status in ('claim_submitted','evidence_requested','under_review')))
$function$
;
CREATE OR REPLACE FUNCTION public.staff_can_access_company(p_company uuid, p_case uuid DEFAULT NULL::uuid, p_claim uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.is_admin() or (public.is_staff() and (
    (p_case is not null and exists(select 1 from public.lead_cases lc join public.requirement_matches rm on rm.enquiry_id = lc.enquiry_id
        where lc.id = p_case and lc.assigned_to = auth.uid() and rm.company_id = p_company and rm.route = 'admin'))
    or (p_claim is not null and exists(select 1 from public.company_claims cl where cl.id = p_claim and cl.company_id = p_company
        and cl.status in ('claim_submitted','evidence_requested','under_review')))))
$function$
;
CREATE OR REPLACE FUNCTION public.review_claim(p_claim uuid, p_decision claim_status, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.seller_can_reply(eid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists(select 1 from enquiries e where e.id=eid and (
      (e.kind='product' and has_company_role(e.company_id, array['owner','manager','sales']::member_role[]))
   or (e.kind='requirement' and exists(select 1 from lead_responses lr where lr.enquiry_id=e.id
        and has_company_role(lr.company_id, array['owner','manager','sales']::member_role[]))))) $function$
;
CREATE OR REPLACE FUNCTION public.respond_to_lead(p_enquiry uuid, p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.reveal_buyer_contact(p_enquiry uuid, p_company uuid)
 RETURNS TABLE(buyer_name text, buyer_phone text, buyer_email text, buyer_company text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.notify_on_enquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.submit_enquiry(p_kind enquiry_kind, p_product uuid, p_company uuid, p_category integer, p_subject text, p_quantity numeric, p_unit text, p_message text, p_city text, p_buyer_name text, p_phone text, p_email text, p_buyer_company text, p_consent boolean, p_notice_version text)
 RETURNS TABLE(enquiry_ref text, delivery enquiry_delivery, notice text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
commit;

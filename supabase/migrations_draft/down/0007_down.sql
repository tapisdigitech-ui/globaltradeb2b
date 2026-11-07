-- DOWN for 0007_function_hardening. DRAFT, local only. Restores the exact post-0006 function bodies/ACLs (definitions taken from a LOCAL clone at 0006).
-- Data notes: company_import_audit and its rows are dropped (audit history of imports done under 0007 is lost - export first if needed);
-- respond_quotation returns void again (callers reading the text result lose it); quotations set to 'expired' by 0007 stay expired.
begin;
alter table public.company_members drop constraint company_members_invite_has_expiry;
alter table public.company_data_corrections drop constraint corrections_evidence_url_http;
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
CREATE OR REPLACE FUNCTION public.start_claim_verification(p_claim uuid, p_channel text, p_target text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$;
CREATE OR REPLACE FUNCTION public.confirm_claim_verification(p_claim uuid, p_channel text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$;
CREATE OR REPLACE FUNCTION public.staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$;
CREATE OR REPLACE FUNCTION public.redeem_invitation(p_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare i public.claim_invitations;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '28000'; end if;
  perform public.check_rate('invite_redeem', 5, interval '1 hour');
  select * into i from public.claim_invitations where token_hash = digest(coalesce(p_token,''), 'sha256') and status = 'sent_manual' and expires_at > now();
  if not found then raise exception 'invalid or expired invitation'; end if;
  update public.claim_invitations set status = 'redeemed', redeemed_by = auth.uid(), redeemed_at = now() where id = i.id;
  return i.company_id;  -- the caller must still use submit_claim(); an invitation approves nothing
end $function$;
CREATE OR REPLACE FUNCTION public.import_normalize(p_batch uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$;
drop function public.respond_quotation(uuid, boolean);
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
revoke all on function public.respond_quotation(uuid, boolean) from public, anon;
grant execute on function public.respond_quotation(uuid, boolean) to authenticated, service_role;
drop table public.company_import_audit;
commit;

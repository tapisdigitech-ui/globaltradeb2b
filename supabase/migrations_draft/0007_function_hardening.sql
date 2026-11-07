-- 0007_function_hardening.sql  — DRAFT, LOCAL ONLY. Not applied to any Supabase project (staging, branch or production).
-- Applies on top of baseline + 0001..0006 (real schema). Does NOT edit historical migrations.
-- Findings (docs/STUBBED_FUNCTIONS_REPORT.md): F1 invitation expiry, F2 duplicate company requests, F3 correction ownership + URL scheme,
-- F5 import audit, F6 rollback guard, F7 quotation expiry + NULL-unsafe owner check, F8 order-time recheck, F9 pgcrypto schema qualification (hosted-only break).
-- Business decisions are listed in docs/ROUND7_TEST_REPORT.md (section 2). Down script: down/0007_down.sql.
begin;

-- ===== F9 pgcrypto lives in schema "extensions" on Supabase; function search_path is public,pg_temp, so unqualified digest()/gen_random_bytes() fail there =====
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
  if p_channel = 'email' then code := encode(extensions.gen_random_bytes(16), 'hex'); exp := now() + interval '24 hours';
    select public.norm_domain(website) into site from public.companies where id = cl.company_id;
    dm := coalesce(site,'') <> '' and lower(split_part(v,'@',2)) = site;
  else code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0'); exp := now() + interval '10 minutes'; end if;
  insert into public.claim_verifications(claim_id, channel, target, domain_matches_website, code_hash, expires_at, id)
    values (p_claim, p_channel, lower(v), dm, extensions.digest(code, 'sha256'), exp, gen_random_uuid()) returning id into vid;
  update public.claim_verifications set code_hash = extensions.digest(code || ':' || vid::text, 'sha256') where id = vid;
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
  if r.code_hash is distinct from extensions.digest(coalesce(trim(p_code),'') || ':' || r.id::text, 'sha256') then
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
  tok := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.claim_invitations(company_id, contact_id, case_id, created_by, token_hash) values (p_company, p_contact, p_case, auth.uid(), extensions.digest(tok, 'sha256')) returning id into iid;
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
  select * into i from public.claim_invitations where token_hash = extensions.digest(coalesce(p_token,''), 'sha256') and status = 'sent_manual' and expires_at > now();
  if not found then raise exception 'invalid or expired invitation'; end if;
  update public.claim_invitations set status = 'redeemed', redeemed_by = auth.uid(), redeemed_at = now() where id = i.id;
  return i.company_id;  -- the caller must still use submit_claim(); an invitation approves nothing
end $function$;

-- ===== F1 invitations: NULL expires_at used to mean "never expires" (NULL < now() is NULL -> check skipped). Fail closed + constraint for pending invites =====
alter table public.company_members add constraint company_members_invite_has_expiry check (status <> 'invited' or expires_at is not null) not valid;
create or replace function public.accept_invitation(p_member uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); em text; m company_members;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  select lower(email) into em from auth.users where id=uid and email_confirmed_at is not null;
  if em is null then raise exception 'confirmed email required'; end if;
  perform check_rate('accept_invite',10,interval '1 day');
  select * into m from company_members where id=p_member and status='invited' and user_id is null for update;
  if not found or lower(m.invite_email) is distinct from em then raise exception 'invitation not found'; end if;
  if m.expires_at is null or m.expires_at < now() then raise exception 'invitation expired'; end if;   -- F1: NULL = expired (fail closed)
  if not company_is_claimed(m.company_id) then raise exception 'company workspace is not active'; end if;
  if exists(select 1 from company_members where company_id=m.company_id and user_id=uid) then raise exception 'already a member'; end if;
  update company_members set user_id=uid, status='active' where id=p_member;
  update profiles set app_role='seller' where id=uid and app_role='buyer';
end $$;

-- ===== F2 company requests: same creator repeating the same name+city created unlimited duplicates (and burned the rate limit) =====
-- Decision: idempotent per creator (returns the existing open request). Cross-user duplicates are NOT blocked (a different person may legitimately
-- claim the same business; existence of other users' requests must not leak) and stay a staff dedupe review item.
create or replace function public.create_company_request(p_name text, p_type text, p_city text, p_statement text) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); cid uuid; nm text := left(trim(coalesce(p_name,'')),160); ct text := left(p_city,80);
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if nm = '' then raise exception 'name required'; end if;
  -- serialise concurrent identical requests from the same user (transaction-scoped; released at commit)
  perform pg_advisory_xact_lock(hashtextextended('company_request:'||uid::text||':'||lower(nm)||':'||lower(coalesce(trim(ct),'')),0));
  select c.id into cid from companies c
   where c.created_by=uid and lower(c.name)=lower(nm) and lower(coalesce(trim(c.city),''))=lower(coalesce(trim(ct),''))
     and c.claim_status in ('claim_submitted','evidence_requested','under_review') limit 1;
  if cid is not null then return cid; end if;
  perform check_rate('company_request',3,interval '1 day');
  insert into companies(slug,name,business_type,city,created_by,claim_status)
    values (make_slug(nm)||'-'||substr(gen_random_uuid()::text,1,6), nm, left(p_type,80), ct, uid, 'claim_submitted')
    returning id into cid;
  insert into company_sources(company_id,field_name,source_type,source_name,source_url,collected_at,recorded_by)
    values (cid,'name','direct_submission','Direct submission','direct-submission:'||uid::text,now(),uid);
  insert into company_claims(company_id,claimant_id,statement,claimant_role_title) values (cid,uid,left(p_statement,2000),'Creator');
  return cid;
end $$;

-- ===== F3 corrections: product not tied to company; evidence_url stored raw (javascript:, data:, file: ...) =====
alter table public.company_data_corrections add constraint corrections_evidence_url_http check (evidence_url is null or evidence_url ~* '^https?://[^[:space:]]+$') not valid;
create or replace function public.report_correction(p_company uuid, p_product uuid, p_field text, p_value text, p_url text, p_note text) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare id uuid; u text := nullif(trim(coalesce(p_url,'')),'');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='28000'; end if;
  if not company_is_live(p_company) then raise exception 'company not available'; end if;
  if p_product is not null and not exists(select 1 from products pr where pr.id=p_product and pr.company_id=p_company) then raise exception 'product does not belong to this company'; end if;
  if u is not null and (u !~* '^https?://[^[:space:]]+$' or length(u) > 500) then raise exception 'evidence url must be an http(s) link of at most 500 characters'; end if;
  perform check_rate('correction',10,interval '1 day');
  insert into company_data_corrections(company_id,product_id,field_name,proposed_value,evidence_url,reporter_note,reporter_id)
    values (p_company,p_product,left(p_field,60),left(p_value,1000),u,left(p_note,1000),auth.uid()) returning company_data_corrections.id into id;
  return id;
end $$;

-- ===== F5 import audit: immutable, import-specific (who applied / rolled back which batch, with counts) =====
create table public.company_import_audit (
  id bigint generated always as identity primary key,
  batch_id uuid not null,            -- deliberately NO foreign key: audit rows must outlive batch deletion
  actor_id uuid not null,
  action text not null check (action in ('apply','rollback')),
  rows_approved integer, inserted integer, skipped_duplicates integer, deleted_companies integer,
  rollback_ref text,
  at timestamptz not null default now()
);
create trigger cia_immutable before update or delete on public.company_import_audit for each row execute function public.block_mutation();
alter table public.company_import_audit enable row level security; alter table public.company_import_audit force row level security;
create policy cia_read on public.company_import_audit for select to authenticated using (is_admin());
revoke all on public.company_import_audit from public, anon, authenticated;
grant select on public.company_import_audit to authenticated;

create or replace function public.import_apply(p_batch uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare b company_import_batches; r record; cid uuid; ins int := 0; skipped int := 0; appr int := 0;
begin
  if not is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  select * into b from company_import_batches where id=p_batch for update;
  if not found then raise exception 'batch not found'; end if;
  if not b.terms_checked then raise exception 'source terms have not been confirmed for this batch'; end if;
  if b.status not in ('validated','applied') then raise exception 'batch must be validated first'; end if;
  for r in select * from company_import_rows where batch_id=p_batch and status='approved' order by row_no loop
    cid := null; appr := appr+1;
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
  insert into company_import_audit(batch_id,actor_id,action,rows_approved,inserted,skipped_duplicates) values (p_batch,auth.uid(),'apply',appr,ins,skipped);
  return jsonb_build_object('inserted',ins,'skipped_duplicates',skipped);
end $$;

-- ===== F6 rollback: requirement_matches (and quotations) reference companies; the cascade used to delete lead matches silently =====
-- Decision: refuse the rollback (like enquiries/claims/members). Already rolled-back batch: no-op returning 0 (no rewrite of rolled_back_at/rollback_ref).
create or replace function public.import_rollback(p_batch uuid, p_ref text) returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n int; b company_import_batches;
begin
  if not is_admin() then raise exception 'admin only' using errcode='42501'; end if;
  select * into b from company_import_batches where id=p_batch for update;          -- serialises with import_apply and a concurrent rollback
  if not found then raise exception 'batch not found'; end if;
  if b.status = 'rolled_back' then return 0; end if;
  perform 1 from companies where import_batch_id=p_batch for update;                -- blocks concurrent FK inserts (matches/quotes) until we finish
  if exists(select 1 from companies c where c.import_batch_id=p_batch and (
        exists(select 1 from enquiries e where e.company_id=c.id) or exists(select 1 from company_claims cc where cc.company_id=c.id)
     or exists(select 1 from company_members m where m.company_id=c.id) or c.directory_status='published'
     or exists(select 1 from requirement_matches rm where rm.company_id=c.id) or exists(select 1 from quotations qq where qq.company_id=c.id))) then
    raise exception 'cannot roll back: batch companies are published or have enquiries/claims/members/lead matches/quotations';
  end if;
  delete from companies where import_batch_id=p_batch; get diagnostics n = row_count;
  update company_import_rows set status='approved', match_company_id=null where batch_id=p_batch and status='imported';
  update company_import_batches set status='rolled_back', rolled_back_at=now(), rollback_ref=p_ref where id=p_batch;
  insert into company_import_audit(batch_id,actor_id,action,deleted_companies,rollback_ref) values (p_batch,auth.uid(),'rollback',n,left(p_ref,200));
  return n;
end $$;

-- ===== F7 respond_quotation: the expiry UPDATE was undone by the exception that followed it; NULL uid passed `<>` owner check =====
-- Return type changes void -> text ('accepted'|'declined'|'expired'), so the function is dropped and recreated (ACL re-applied below).
-- Behaviour change (documented): a response to an expired quote no longer raises; it persists status 'expired' and returns 'expired'.
drop function public.respond_quotation(uuid, boolean);
create function public.respond_quotation(p_quote uuid, p_accept boolean) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare q quotations; e enquiries; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  select * into q from quotations where id=p_quote for update;
  if not found then raise exception 'quotation not found'; end if;
  select * into e from enquiries where id=q.enquiry_id;
  if e.buyer_id is distinct from uid then raise exception 'not your quotation' using errcode='42501'; end if;
  if q.status <> 'sent' then raise exception 'quotation is not open'; end if;
  if q.valid_until is not null and q.valid_until < current_date then
    update quotations set status='expired', responded_at=now() where id=p_quote; return 'expired'; end if;
  update quotations set status=case when p_accept then 'accepted' else 'declined' end::quote_status, responded_at=now() where id=p_quote;
  return case when p_accept then 'accepted' else 'declined' end;
end $$;
revoke all on function public.respond_quotation(uuid, boolean) from public, anon;
grant execute on function public.respond_quotation(uuid, boolean) to authenticated, service_role;

-- ===== F8 create_order: only status + claimed were checked; NULL uid; no lock; validity/eligibility not rechecked =====
-- Decision (documented): an accepted quote can only be turned into an order while valid_until is null or not past, and while the supplier is still
-- eligible (claim approved, directory not paused/rejected/suspended, verification not rejected/expired).
create or replace function public.create_order(p_quote uuid) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare q quotations; e enquiries; oid uuid; uid uuid := auth.uid(); co companies;
begin
  if uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  select * into q from quotations where id=p_quote for update;
  if not found then raise exception 'quotation not found'; end if;
  select * into e from enquiries where id=q.enquiry_id;
  if e.buyer_id is distinct from uid then raise exception 'not your quotation' using errcode='42501'; end if;
  if q.status <> 'accepted' then raise exception 'quotation must be accepted first'; end if;
  if q.valid_until is not null and q.valid_until < current_date then raise exception 'quotation validity has passed'; end if;
  select * into co from companies where id=q.company_id;
  if not found or co.claim_status <> 'approved' or co.directory_status in ('paused','rejected','suspended') or co.verification_status in ('rejected','expired') then
    raise exception 'supplier not active'; end if;
  perform check_rate('order',20,interval '1 day');
  insert into orders(quotation_id,buyer_id,company_id,total,currency) values (q.id,uid,q.company_id,q.amount,q.currency) returning id into oid;
  return oid;
end $$;

-- ===== F10 (found in Round 7 review of 0006): import_normalize in 0006 carried the website regex as '\\.' (a literal backslash + any char), so EVERY normal http(s) URL was flagged 'website not a valid http(s) URL'.
-- Restored to the staging form '\.' (dot). Only the regex differs from the 0006 body. =====
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
end $function$;

commit;

-- DRAFT — NOT APPLIED. Claim email-token / phone-OTP verification, claim invitations, approval gate.
-- No message is sent by this migration: codes are written to a service-role-only outbox that nothing reads until an email/SMS provider is separately approved.
begin;

create table public.claim_verifications (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.company_claims(id) on delete cascade,
  channel text not null check (channel in ('email','phone')),
  target text not null,
  domain_matches_website boolean,              -- evidence only; never auto-approves
  code_hash bytea not null,
  expires_at timestamptz not null,
  attempts smallint not null default 0,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index claim_verifications_claim_idx on public.claim_verifications(claim_id, channel, created_at desc);
create table public.claim_verification_outbox (
  verification_id uuid primary key references public.claim_verifications(id) on delete cascade,
  channel text not null, target text not null, code text not null,
  status text not null default 'queued' check (status in ('queued','sent','failed')),
  expires_at timestamptz not null, created_at timestamptz not null default now()
);
comment on table public.claim_verification_outbox is 'class=system; plaintext one-time codes awaiting an (unapproved) delivery provider. service_role only. Rows are deleted on successful verification.';
create table public.claim_invitations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  contact_id uuid not null references public.company_contacts(id),
  case_id uuid references public.lead_cases(id) on delete set null,
  created_by uuid not null, approved_by uuid, approved_at timestamptz,
  token_hash bytea not null,
  expires_at timestamptz not null default now() + interval '14 days',
  status text not null default 'draft' check (status in ('draft','approved','sent_manual','redeemed','expired','cancelled')),
  delivery public.outreach_delivery not null default 'logged_manual',
  provider_ref text, sent_at timestamptz, redeemed_by uuid, redeemed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index claim_invitations_one_active on public.claim_invitations(company_id) where status in ('draft','approved','sent_manual');

do $$ declare t text; begin
  foreach t in array array['claim_verifications','claim_verification_outbox','claim_invitations'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop; end $$;
grant select, update, delete on public.claim_verification_outbox to service_role;
grant select on public.claim_invitations to authenticated;
create policy cinv_read on public.claim_invitations for select to authenticated using (public.is_admin() or (public.is_staff() and created_by = auth.uid()));
-- claim_verifications: no policies at all (not readable by any API role; summary function only)

create function public.start_claim_verification(p_claim uuid, p_channel text, p_target text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
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
end $$;

create function public.confirm_claim_verification(p_claim uuid, p_channel text, p_code text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
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

create function public.claim_verification_summary(p_claim uuid) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
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

-- Approval gate: never approve on a match alone; email must be verified and no competing open claim may exist.
create function public._claim_approval_gate() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    if not exists(select 1 from public.claim_verifications where claim_id = new.id and channel = 'email' and verified_at is not null) then raise exception 'claim cannot be approved: claimant email not verified'; end if;
    if exists(select 1 from public.company_claims o where o.company_id = new.company_id and o.id <> new.id and o.claimant_id <> new.claimant_id and o.status in ('claim_submitted','evidence_requested','under_review')) then raise exception 'claim cannot be approved: conflicting open claim needs separate review'; end if;
  end if; return new; end $$;
create trigger company_claims_approval_gate before update of status on public.company_claims for each row execute function public._claim_approval_gate();

-- ---------- claim invitations (individual, staff-initiated, manual delivery) ----------
create function public.staff_create_invitation(p_company uuid, p_contact uuid, p_case uuid, p_purpose text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
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
create function public.admin_approve_invitation(p_inv uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update public.claim_invitations set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_inv and status = 'draft'; if not found then raise exception 'invitation not in draft'; end if; end $$;
create function public.staff_mark_invitation_sent(p_inv uuid, p_provider_ref text default null) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare i public.claim_invitations;
begin
  select * into i from public.claim_invitations where id = p_inv; if not found then raise exception 'not found'; end if;
  if not (public.is_admin() or (public.is_staff() and i.created_by = auth.uid())) then raise exception 'not authorised' using errcode = '42501'; end if;
  if i.status <> 'approved' then raise exception 'invitation must be approved by an admin first'; end if;
  update public.claim_invitations set status = 'sent_manual', sent_at = now(), delivery = case when coalesce(trim(p_provider_ref),'') <> '' then 'sent'::public.outreach_delivery else 'logged_manual'::public.outreach_delivery end, provider_ref = nullif(trim(p_provider_ref),'') where id = p_inv;
  insert into public.company_outreach_events(company_id, event_type, channel, summary, delivery, provider_ref, recorded_by) values (i.company_id, 'invitation', 'email', 'claim invitation marked sent', case when coalesce(trim(p_provider_ref),'') <> '' then 'sent'::public.outreach_delivery else 'logged_manual'::public.outreach_delivery end, nullif(trim(p_provider_ref),''), auth.uid());
  if i.case_id is not null then perform set_config('app.lead_note', 'claim invitation marked sent', true); update public.lead_cases set status = 'claim_invitation_sent', updated_at = now() where id = i.case_id and status not in ('closed','seller_activated'); end if;
end $$;
create function public.redeem_invitation(p_token text) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare i public.claim_invitations;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '28000'; end if;
  perform public.check_rate('invite_redeem', 5, interval '1 hour');
  select * into i from public.claim_invitations where token_hash = digest(coalesce(p_token,''), 'sha256') and status = 'sent_manual' and expires_at > now();
  if not found then raise exception 'invalid or expired invitation'; end if;
  update public.claim_invitations set status = 'redeemed', redeemed_by = auth.uid(), redeemed_at = now() where id = i.id;
  return i.company_id;  -- the caller must still use submit_claim(); an invitation approves nothing
end $$;
do $$ declare f text; begin
  foreach f in array array['start_claim_verification(uuid,text,text)','confirm_claim_verification(uuid,text,text)','claim_verification_summary(uuid)','staff_create_invitation(uuid,uuid,uuid,text)','admin_approve_invitation(uuid)','staff_mark_invitation_sent(uuid,text)','redeem_invitation(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f); execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;
revoke all on function public._claim_approval_gate() from public, anon, authenticated;
commit;

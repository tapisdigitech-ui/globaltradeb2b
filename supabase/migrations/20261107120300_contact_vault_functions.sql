-- DRAFT — NOT APPLIED. Contact vault access functions: explicit purpose, assignment scope, immutable audit with related lead/claim.
-- Direct table access is closed in 0001 (no staff policy); these are the only staff path.
begin;
create function public.staff_add_contact(p_company uuid, p_kind text, p_value text, p_source_type public.source_type, p_source_name text,
  p_source_url text default null, p_purpose text default null, p_case uuid default null, p_claim uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
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
end $$;
create function public.staff_get_contacts(p_company uuid, p_purpose text, p_case uuid default null, p_claim uuid default null)
returns table(id uuid, kind text, value text, status text, source_name text, source_url text, last_verified_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_staff() then raise exception 'staff only' using errcode = '42501'; end if;
  if not public.staff_can_access_company(p_company, p_case, p_claim) then raise exception 'not authorised for this supplier' using errcode = '42501'; end if;
  if coalesce(trim(p_purpose),'') = '' then raise exception 'purpose required'; end if;
  insert into public.contact_access_log(actor_id, action, company_id, purpose, lead_case_id, claim_id) values (auth.uid(), 'view', p_company, left(p_purpose,200), p_case, p_claim);
  return query select c.id, c.kind, case when c.status = 'do_not_contact' then null else c.value end, c.status, c.source_name, c.source_url, c.last_verified_at
    from public.company_contacts c where c.company_id = p_company order by c.kind, c.created_at;
end $$;
create function public.staff_set_contact_status(p_contact uuid, p_status text, p_purpose text, p_case uuid default null, p_claim uuid default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
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
do $$ declare f text; begin
  foreach f in array array['staff_add_contact(uuid,text,text,public.source_type,text,text,text,uuid,uuid)','staff_get_contacts(uuid,text,uuid,uuid)','staff_set_contact_status(uuid,text,text,uuid,uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f); execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;
commit;

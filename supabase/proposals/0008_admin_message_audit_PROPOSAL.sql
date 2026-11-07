-- 0008_admin_message_audit_PROPOSAL.sql — PROPOSAL ONLY. NOT in migrations_draft/, NOT applied anywhere (not local DBs used by the
-- standard suites, not staging, not any branch). Requires explicit approval before being moved into migrations_draft/ and renumbered.
-- Purpose: admins currently read private buyer/seller messages and quotations through RLS with NO per-read record ("admin oversight", AUDIT_DECISIONS.md).
-- This proposal removes the is_admin() shortcut from the four message policies and routes admin access through an audited, time-limited, purpose-bound grant.
-- Applies on top of baseline + 0001..0007.
begin;

-- 1. immutable access log: successful AND refused attempts
create table public.admin_comms_access_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  scope text not null check (scope in ('enquiry','thread')),
  target_id uuid,                       -- no FK: audit rows survive deletions; NULL only when the caller sent NULL
  purpose text not null,
  outcome text not null check (outcome in ('granted','denied','invalid','rate_limited')),
  denial_reason text,
  at timestamptz not null default now(),
  constraint acal_purpose_when_granted check (outcome <> 'granted' or length(trim(purpose)) >= 10)
);
create trigger acal_immutable before update or delete on public.admin_comms_access_log for each row execute function public.block_mutation();
create table public.admin_comms_grants (
  scope text not null, target_id uuid not null, admin_id uuid not null, expires_at timestamptz not null,
  primary key (scope, target_id, admin_id)
);
alter table public.admin_comms_access_log enable row level security; alter table public.admin_comms_access_log force row level security;
alter table public.admin_comms_grants     enable row level security; alter table public.admin_comms_grants     force row level security;
create policy acal_admin_read on public.admin_comms_access_log for select to authenticated using (public.is_admin());
revoke all on public.admin_comms_access_log, public.admin_comms_grants from public, anon, authenticated;
grant select on public.admin_comms_access_log to authenticated;

-- 2. grant check used by the policies (no admin shortcut: needs a live grant for THIS admin and THIS target)
create function public.admin_comms_grant_active(p_scope text, p_target uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_target is not null and public.is_admin() and exists(
    select 1 from public.admin_comms_grants g where g.scope = p_scope and g.target_id = p_target and g.admin_id = auth.uid() and g.expires_at > now())
$$;

-- 3. the audited entry point. NON-RAISING for admins on purpose (a raised exception would roll back the log row): returns 'ok'|'denied'|'invalid'|'rate_limited'.
--    Non-admins get a plain error and no row (same convention as _evidence_gate). Limits: 30 granted per admin per hour, 200 per day, 20 refusals per hour.
create function public.admin_open_comms(p_scope text, p_target uuid, p_purpose text) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); pur text := left(trim(coalesce(p_purpose,'')),500); outcome text := 'ok'; reason text; exp timestamptz := now() + interval '10 minutes';
begin
  if uid is null or not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if (select count(*) from public.admin_comms_access_log l where l.actor_id = uid and l.outcome = 'granted' and l.at > now() - interval '1 hour') >= 30
     or (select count(*) from public.admin_comms_access_log l where l.actor_id = uid and l.outcome = 'granted' and l.at > now() - interval '1 day') >= 200 then outcome := 'rate_limited'; reason := 'grant limit reached';
  elsif (select count(*) from public.admin_comms_access_log l where l.actor_id = uid and l.outcome in ('invalid','denied') and l.at > now() - interval '1 hour') >= 20 then outcome := 'rate_limited'; reason := 'too many refused attempts';
  elsif p_scope not in ('enquiry','thread') or p_target is null then outcome := 'invalid'; reason := 'bad scope or target';
  elsif length(pur) < 10 then outcome := 'invalid'; reason := 'purpose too short (min 10 characters)';
  elsif p_scope = 'enquiry' and not exists(select 1 from public.enquiries where id = p_target) then outcome := 'invalid'; reason := 'enquiry not found';
  elsif p_scope = 'thread'  and not exists(select 1 from public.direct_threads where id = p_target) then outcome := 'invalid'; reason := 'thread not found';
  end if;
  if outcome = 'ok' then
    insert into public.admin_comms_access_log(actor_id, scope, target_id, purpose, outcome) values (uid, p_scope, p_target, pur, 'granted');
    insert into public.admin_comms_grants(scope, target_id, admin_id, expires_at) values (p_scope, p_target, uid, exp)
      on conflict (scope, target_id, admin_id) do update set expires_at = excluded.expires_at;
  else
    insert into public.admin_comms_access_log(actor_id, scope, target_id, purpose, outcome, denial_reason)
      values (uid, case when p_scope in ('enquiry','thread') then p_scope else 'enquiry' end, p_target, pur, outcome,
        case when p_scope in ('enquiry','thread') then reason else reason||' (scope sent: '||left(coalesce(p_scope,'NULL'),30)||')' end);
  end if;
  return outcome;
end $$;
revoke all on function public.admin_comms_grant_active(text, uuid), public.admin_open_comms(text, uuid, text) from public, anon;
grant execute on function public.admin_comms_grant_active(text, uuid), public.admin_open_comms(text, uuid, text) to authenticated;   -- admin check is inside

-- 4. policies: the is_admin() shortcut is removed from the four message-related read policies (existing staff-grant paths unchanged)
drop policy dt_read on public.direct_threads;
create policy dt_read on public.direct_threads for select using (buyer_id = auth.uid() or has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or public.admin_comms_grant_active('thread', id) or public.staff_thread_comms_ok(id));
drop policy dm_read on public.direct_messages;
create policy dm_read on public.direct_messages for select using (thread_buyer(thread_id) = auth.uid() or has_company_role(thread_company(thread_id), array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or public.admin_comms_grant_active('thread', thread_id) or public.staff_thread_comms_ok(thread_id));
drop policy replies_read on public.enquiry_replies;
create policy replies_read on public.enquiry_replies for select using (enquiry_buyer(enquiry_id) = auth.uid() or seller_can_reply(enquiry_id) or public.admin_comms_grant_active('enquiry', enquiry_id) or public.comms_grant_active(enquiry_id));
drop policy quotes_read on public.quotations;
create policy quotes_read on public.quotations for select using (has_company_role(company_id, array['owner'::member_role,'manager'::member_role,'sales'::member_role]) or public.admin_comms_grant_active('enquiry', enquiry_id) or public.comms_grant_active(enquiry_id) or ((enquiry_buyer(enquiry_id) = auth.uid()) and (status = any (array['sent'::quote_status,'accepted'::quote_status,'declined'::quote_status,'expired'::quote_status]) or (status = 'withdrawn'::quote_status and sent_at is not null))));
-- NOT changed (decision for the approver): orders_read keeps is_admin() - orders are an operational/finance record, not message content.
commit;

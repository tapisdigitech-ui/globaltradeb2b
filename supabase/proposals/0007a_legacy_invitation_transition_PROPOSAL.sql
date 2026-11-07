-- 0007a_legacy_invitation_transition_PROPOSAL.sql — PROPOSAL ONLY. Not in migrations_draft/, not applied anywhere (local replica tests only).
-- Context: 0007 (F1) made accept_invitation treat NULL expires_at as expired and added company_members_invite_has_expiry (NOT VALID).
-- Facts (local catalogue): the guard trigger forces expires_at := now()+14 days on every invite created by a non-trusted session, and my_invitations()
-- already hid NULL-expiry rows. NULL-expiry pending invites can therefore only come from trusted-session inserts (service role / SQL editor).
-- Rule applied retroactively (no new rule, no extension beyond the normal 14-day lifetime): expires_at := created_at + 14 days.
--   invites younger than 14 days keep their remaining normal lifetime; older ones are expired (row kept, owner re-invites). Rows are never activated or deleted.
begin;
create table public.legacy_invitation_transition_log (
  member_id uuid primary key, previous_expires_at timestamptz, new_expires_at timestamptz not null, transitioned_at timestamptz not null default now()
);
alter table public.legacy_invitation_transition_log enable row level security; alter table public.legacy_invitation_transition_log force row level security;
revoke all on public.legacy_invitation_transition_log from public, anon, authenticated;   -- no policy: internal, trusted sessions only
create trigger lit_immutable before update or delete on public.legacy_invitation_transition_log for each row execute function public.block_mutation();

with moved as (
  update public.company_members m set expires_at = m.created_at + interval '14 days'
   where m.status = 'invited' and m.user_id is null and m.expires_at is null
   returning m.id, m.expires_at)
insert into public.legacy_invitation_transition_log(member_id, previous_expires_at, new_expires_at) select id, null, expires_at from moved;

alter table public.company_members validate constraint company_members_invite_has_expiry;   -- fails (and rolls back everything) if any pending invite still lacks an expiry
commit;

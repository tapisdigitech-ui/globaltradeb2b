-- DOWN for the invitation-transition PROPOSAL. WARNING: restores the unsafe state (pending invites without expiry) for the transitioned rows only.
begin;
alter table public.company_members drop constraint company_members_invite_has_expiry;
update public.company_members m set expires_at = null from public.legacy_invitation_transition_log l where l.member_id = m.id and m.status = 'invited' and m.user_id is null and m.expires_at = l.new_expires_at;
alter table public.company_members add constraint company_members_invite_has_expiry check (status <> 'invited' or expires_at is not null) not valid;   -- as left by 0007
drop table public.legacy_invitation_transition_log;
commit;

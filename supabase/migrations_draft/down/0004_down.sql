begin;
drop trigger if exists company_claims_approval_gate on public.company_claims;
drop function if exists public._claim_approval_gate(), public.start_claim_verification(uuid,text,text), public.confirm_claim_verification(uuid,text,text), public.claim_verification_summary(uuid), public.staff_create_invitation(uuid,uuid,uuid,text), public.admin_approve_invitation(uuid), public.staff_mark_invitation_sent(uuid,text), public.redeem_invitation(text);
drop table public.claim_invitations, public.claim_verification_outbox, public.claim_verifications;
commit;

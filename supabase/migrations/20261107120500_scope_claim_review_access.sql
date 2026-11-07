-- DRAFT — NOT APPLIED. Reviewers see only OPEN claims and their verification documents; admins see all; claimants their own.
-- Replaces company_claims.claims_read and storage.objects vd_read (original predicates captured from staging catalog 2026-11-07; restored by down/0005).
-- NOT covered (open blocker): company_claim_evidence.cev_read — its real predicate was not captured; it only exposes metadata (storage_path), the files are protected by vd_read below.
begin;
create function public.staff_can_review_claim(p_claim uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or (public.is_staff() and exists(select 1 from public.company_claims c where c.id = p_claim and c.status in ('claim_submitted','evidence_requested','under_review')))
$$;
revoke all on function public.staff_can_review_claim(uuid) from public, anon; grant execute on function public.staff_can_review_claim(uuid) to authenticated;
drop policy claims_read on public.company_claims;
create policy claims_read on public.company_claims for select using (claimant_id = auth.uid() or public.staff_can_review_claim(id));
drop policy vd_read on storage.objects;
create policy vd_read on storage.objects for select to authenticated using (bucket_id = 'verification-docs' and (public.claim_claimant(public.safe_uuid((storage.foldername(name))[1])) = auth.uid() or public.staff_can_review_claim(public.safe_uuid((storage.foldername(name))[1]))));
commit;

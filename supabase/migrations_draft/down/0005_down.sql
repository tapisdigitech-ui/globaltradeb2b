begin;
drop policy claims_read on public.company_claims; create policy claims_read on public.company_claims for select using (((claimant_id = auth.uid()) OR is_staff()));
drop policy vd_read on storage.objects; create policy vd_read on storage.objects for select to authenticated using (((bucket_id = 'verification-docs'::text) AND ((claim_claimant(safe_uuid((storage.foldername(name))[1])) = auth.uid()) OR is_staff())));
drop function public.staff_can_review_claim(uuid);
commit;

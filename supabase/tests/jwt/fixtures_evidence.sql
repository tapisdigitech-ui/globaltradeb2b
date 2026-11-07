grant select on storage.objects to authenticated;   -- stub fidelity (the real platform grants this; RLS policies decide), same as tests/real_schema_tests.sql
-- SYNTHETIC evidence fixtures (claim, 2 evidence rows, reviewer assignment). Loaded after fixtures.sql. No real company/person/document.
insert into public.companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status,is_demo) values
 ('c0000000-0000-0000-0000-0000000e0c01','synthetic-evidence-co','SYNTHETIC Evidence Co (test, not a supplier)','Nowhere','IN','draft','claim_submitted','not_verified','pending',true);
insert into public.company_claims(id,company_id,claimant_id,statement,status) values
 ('a1a00000-0000-0000-0000-0000000e0c01','c0000000-0000-0000-0000-0000000e0c01','00000000-0000-0000-0000-00000000e001','synthetic claim','claim_submitted');
set role authenticated; set request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000e001","role":"authenticated","aud":"authenticated"}';
insert into public.company_claim_evidence(id,claim_id,storage_path,uploaded_by) values
 ('e7e00000-0000-0000-0000-0000000e0001','a1a00000-0000-0000-0000-0000000e0c01','a1a00000-0000-0000-0000-0000000e0c01/e1.pdf','00000000-0000-0000-0000-00000000e001'),
 ('e7e00000-0000-0000-0000-0000000e0002','a1a00000-0000-0000-0000-0000000e0c01','a1a00000-0000-0000-0000-0000000e0c01/e2.pdf','00000000-0000-0000-0000-00000000e001');
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-00000000e0a1","role":"authenticated","aud":"authenticated"}';
select public.admin_assign_claim_reviewer('a1a00000-0000-0000-0000-0000000e0c01','00000000-0000-0000-0000-00000000e0b1') \g /dev/null
reset role; reset request.jwt.claims;
insert into storage.objects(bucket_id,name) values ('verification-docs','a1a00000-0000-0000-0000-0000000e0c01/e1.pdf'),('verification-docs','a1a00000-0000-0000-0000-0000000e0c01/e2.pdf');

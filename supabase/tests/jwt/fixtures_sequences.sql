-- SYNTHETIC fixtures for sequence-role tests: one published demo company + product (so record_product_view reaches its INSERT). Loaded as table owner; category from seed.
\i seed.sql
-- fixture only: owner bypasses the publish/provenance guards (triggers re-enabled right after)
alter table public.companies disable trigger user; alter table public.products disable trigger user;
insert into public.companies(id,slug,name,city,country,directory_status,claim_status,verification_status,data_review_status,is_demo)
 values ('c0000000-0000-0000-0000-0000000e5e01','synthetic-seq-co','SYNTHETIC Seq Co (test, not a supplier)','Nowhere','IN','published','approved','not_verified','approved',true);
insert into public.products(id,company_id,category_id,name,directory_status,data_review_status)
 values ('d0000000-0000-0000-0000-0000000e5e01','c0000000-0000-0000-0000-0000000e5e01',1,'SYNTHETIC product','published','approved');
alter table public.companies enable trigger user; alter table public.products enable trigger user;

-- supabase/seed.sql — REFERENCE DATA ONLY: the 14 approved top-level marketplace categories. LOCAL / ISOLATED-BRANCH USE. Never run against staging, production-candidate or TAPIS KASA.
-- Provenance: names and hue values are copied verbatim, in order, from the SECTIONS array in /index.html (the application's own category list, 14 entries).
--   They were NOT read from, and are not asserted to equal, the hosted staging categories table. Compare before any hosted use (docs/CATEGORY_SEED.md).
--   Slugs are the output of public.make_slug(name) so they match what the app's own slug function would produce (checked by tests/seed_tests.sql).
--   spec_template is deliberately left at its column default ('[]'): the staging spec_template JSON shape was not inspected, so none is invented here.
-- Idempotent: fixed ids 1..14, ON CONFLICT DO NOTHING (an admin's later edits to a seeded row are preserved), sequence advanced past the seed ids,
--   and a final guard that fails loudly if any approved slug is missing (e.g. another row already owns one of the ids).
-- Contains no suppliers, buyers, contact details or test accounts. Synthetic test data lives only under tests/ and is never loaded by this file.
begin;
insert into public.categories (id, slug, name, hue, "position") values
  (1, 'industrial-plants-machinery', 'Industrial Plants & Machinery', 215, 1),
  (2, 'architecture-interiors', 'Architecture & Interiors', 25, 2),
  (3, 'consumer-electronics', 'Consumer Electronics', 265, 3),
  (4, 'carpets-rugs-home-furnishing', 'Carpets, Rugs & Home Furnishing', 350, 4),
  (5, 'textiles-garments', 'Textiles & Garments', 300, 5),
  (6, 'food-agro-products', 'Food & Agro Products', 95, 6),
  (7, 'building-construction', 'Building & Construction', 15, 7),
  (8, 'packaging-printing', 'Packaging & Printing', 35, 8),
  (9, 'medical-healthcare', 'Medical & Healthcare', 175, 9),
  (10, 'automotive-spare-parts', 'Automotive & Spare Parts', 200, 10),
  (11, 'handicrafts-gifts', 'Handicrafts & Gifts', 45, 11),
  (12, 'renewable-energy', 'Renewable Energy', 60, 12),
  (13, 'chemicals-dyes', 'Chemicals & Dyes', 150, 13),
  (14, 'safety-security', 'Safety & Security', 5, 14)
on conflict do nothing;

select setval('public.categories_id_seq', greatest((select max(id) from public.categories), 14), true);

do $$
declare n int;
begin
  select count(*) into n from public.categories where slug in ('industrial-plants-machinery','architecture-interiors','consumer-electronics','carpets-rugs-home-furnishing','textiles-garments','food-agro-products','building-construction','packaging-printing','medical-healthcare','automotive-spare-parts','handicrafts-gifts','renewable-energy','chemicals-dyes','safety-security') ;
  if n <> 14 then raise exception 'category seed incomplete: % of 14 approved slugs present', n; end if;
end $$;
commit;

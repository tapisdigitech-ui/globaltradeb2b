# Category seed (Round 9 · B3)

`supabase/seed.sql` seeds the **14 approved top-level categories**. It contains reference data only: no suppliers, buyers, contacts or test accounts.

## Provenance
| Item | Source |
|---|---|
| 14 names + `hue`, in this order | the `SECTIONS` array in `/index.html` (the application's own category list) – copied verbatim, nothing invented |
| `slug` | `public.make_slug(name)`, the application's own slug function (verified by test SD4) |
| `position` | 1…14 in `SECTIONS` order |
| `spec_template` | left at the column default `[]` – the hosted JSON shape was never inspected, so none is invented |

The hosted staging `categories` rows were **not** read for this seed and equality with them is **unverified**. Before any hosted use compare names/slugs with a read-only `select id, slug, name, hue, position from categories order by id` (approved catalogue SELECT) and reconcile.

Order: 1 Industrial Plants & Machinery · 2 Architecture & Interiors · 3 Consumer Electronics · 4 Carpets, Rugs & Home Furnishing · 5 Textiles & Garments · 6 Food & Agro Products · 7 Building & Construction · 8 Packaging & Printing · 9 Medical & Healthcare · 10 Automotive & Spare Parts · 11 Handicrafts & Gifts · 12 Renewable Energy · 13 Chemicals & Dyes · 14 Safety & Security.

## Behaviour
- Fixed ids 1–14, `ON CONFLICT DO NOTHING` → repeatable; later admin edits to a seeded row are preserved (not overwritten).
- `setval(categories_id_seq, max(id))` so the next admin-created category gets id 15.
- A closing guard raises (and rolls the seed back) if any of the 14 slugs is missing, e.g. another row already owns one of ids 1–14 under a different slug – it never silently half-seeds.
- Never to be run against staging / production-candidate / TAPIS KASA. `config.toml` runs it only for local `db reset` and branch creation.

## Tests (`tests/seed_tests.sql`, `tests/run_seed.sh`) – 18 checks, all pass
empty DB (SD1) · 14 rows (SD2) · stable ids/positions (SD3) · slug = make_slug, unique, none hidden (SD4) · exact approved names (SD5) · repeated seed is byte-identical (SD6) · sequence advanced (SD7) · admin edits preserved (SD8) · no dangling FKs (SD9) · duplicate slug rejected (SD10) · id-collision guard fails loudly and rolls back (SD11/12) · public read by anon/authenticated (SD13/14) · non-admin and anon cannot write, anon cannot use the sequence (SD15–17) · seed creates no company/profile rows (SD18). Synthetic test rows elsewhere are always named `SYNTHETIC …`, use `.invalid` emails and `is_demo=true`.

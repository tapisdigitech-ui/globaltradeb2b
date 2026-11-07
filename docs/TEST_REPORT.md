# TEST REPORT

Legend: **Local (stub)** = scratch Postgres 16 with a minimal stand-in baseline, not the real schema. **Staging** = not yet executed for any migration.

## Migration 0001 — Phase 1 supplier foundation (contact vault v2, profile extensions, subcategories)
Run: `supabase/tests/stub_baseline.sql` → `migrations_draft/0001_…sql` → `tests/0001_test.sql` (Postgres 16.15). **24/24 assertions passed. Status: Implemented + Locally tested (stub). NOT staging tested. NOT applied.**

| Area | Result |
|---|---|
| Contact privacy: anon cannot SELECT vault; anon cannot execute staff RPCs | pass |
| Buyer sees 0 contacts; seller sees only own company's; seller cannot call staff RPC | pass |
| Staff cannot read vault directly (0 rows) — only via audited RPC with mandatory purpose | pass |
| Staff cannot read the access log; admin can | pass |
| Do-not-contact value withheld; reviewer cannot clear it; admin can, and it is logged | pass |
| Invalid email / invalid phone / missing source / case-insensitive duplicate rejected | pass |
| Access log update and delete blocked by trigger | pass |
| Multiple business types stored; invalid type rejected; `is_demo` defaults false; subcategory link | pass |

### Known limits of this test (do not read as staging proof)
* The stub baseline omits real triggers on `companies` (e.g. `guard_company_columns`), the six `public_*` views, and real RLS on `companies`. Before staging apply: run against a schema-only copy of staging, and confirm the new `companies` columns are not exposed by any view and that the guard trigger permits the intended writes.
* "Staff" is still role-wide (admin/reviewer). Assignment scoping is Phase 5.
* No frontend is connected to any of this.

## Frontend (prototype) — executed earlier in this project
Playwright, 360–2560 px, views home/seller/admin/enquiries/signin/buy: zero horizontal overflow; For Buyers flow (select → quantities → submit → My Enquiries) executed on desktop and mobile. Demonstration data only; localStorage.

## Not yet executed
Claim workflow, lead-routing scenarios 1–7, staff assignment tests, ingestion tests, SEO, Vercel preview checks for this branch.

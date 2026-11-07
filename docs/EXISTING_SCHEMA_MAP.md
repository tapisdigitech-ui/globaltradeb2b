# EXISTING SCHEMA MAP — BLOCKED (Phase 0)

The Phase 2 staging schema could not be inspected from this session (see CURRENT_STATE_AUDIT §3). Nothing below is assumed to exist.

## What I need (read-only, either option)
1. A schema-only export of staging `lhmexhafyuzojrmcbtbz` (`supabase db dump --schema-only`, or the Phase 2 migration `.sql` files), **no data and no secrets**; or
2. Supabase MCP access to staging (read-only role) in a session where I can see that project.

## Checklist to fill once available
| Area | Query/source | Status |
|---|---|---|
| Tables & columns, FKs | `information_schema` / `pg_catalog` | pending |
| RLS enabled + policies per table | `pg_policies` | pending |
| Grants to anon/authenticated | `information_schema.role_table_grants` | pending |
| Functions, triggers, SECURITY DEFINER, search_path | `pg_proc` | pending |
| Public views and columns exposed | `pg_views` | pending |
| Storage buckets + policies | `storage.buckets`, `pg_policies` | pending |
| Auth hooks / roles / admin model | policies + functions | pending |
| Advisors (security/performance) | Supabase advisors | pending |

## Logical-module reuse map (from the brief; mapping to real tables is TBD)
Existing concepts named in the brief — company, product, enquiry, quotation, claim, verification — will be **extended, not duplicated**. The brief's module list (business_sources … notification_events) is treated as logical requirements; each will be mapped to an existing table or justified as new after the schema is read.

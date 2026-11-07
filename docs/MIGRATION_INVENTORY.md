# Migration inventory and chain audit (Round 8, local, PostgreSQL 16.15)

Method: empty database → `baseline/load_baseline.sh` (platform stand-in + baseline 0000) → `0001`…`0007` in order with `ON_ERROR_STOP`, then catalogue queries on the result. Nothing was applied to Supabase; staging was not queried for this section.

| File | Lines | Creates | Down script | Notes |
|---|---|---|---|---|
| `baseline/0000_baseline_reconstructed.sql` | 1549 | 46 tables, 70 functions, 105 policies, 42 triggers, 24 enums, 6 views, grants, 5 buckets | none (disposable DB) | generated; fingerprint-matches staging for 13 kinds |
| `0001_supplier_foundation_and_contact_vault.sql` | 59 | 2 tables, 2 policies, 1 trigger | 8 lines | |
| `0002_requirements_matching_lead_desk.sql` | 320 | 6 tables, 21 functions, 10 policies, 3 triggers | 15 | redefines 4 baseline functions |
| `0003_contact_vault_functions.sql` | 52 | 3 functions | 3 | |
| `0004_claim_verification_and_invitations.sql` | 151 | 3 tables, 8 functions | 5 | 4 functions later re-qualified by 0007 (pgcrypto) |
| `0005_scope_claim_review_access.sql` | 13 | 1 function, 2 policies | 5 | |
| `0006_real_schema_hardening.sql` | 628 | 8 tables, 29 functions, 19 policies, 4 triggers | 450 (regenerated Round 7) | |
| `0007_function_hardening.sql` | 292 | 1 table, 12 functions, 2 NOT VALID checks | 264 | |

Final schema on a fresh local database: **66 public tables** (46 + 20), 115 functions (97 `SECURITY DEFINER`), 120 policies (incl. 8 on `storage.objects`), 52 non-internal triggers, 106 indexes, 6 views.

## Checks and results
| Check | Result |
|---|---|
| Order / dependencies | each file applies cleanly on the output of the previous one from an empty DB; no forward references |
| Duplicate / conflicting objects | no table created twice; 27 functions are (re)defined across files — all intentional `CREATE OR REPLACE` or `DROP`+`CREATE` (`approve_product_image`, `respond_quotation` change signature/return type with an explicit drop); no overloaded function names remain; every policy re-created in a later file is preceded by `DROP POLICY` (the chain applies without error) |
| RLS | 66/66 tables have RLS enabled **and forced**. 6 tables have RLS and **no policy** by design (deny-all internal tables: `rate_events`, `claim_verifications`, `claim_verification_outbox`, `claim_evidence_grants`, `staff_comms_grants`, `buyer_contact_grants`) |
| Grants | `anon`: SELECT on 9 relations only (`categories`, `cms_pages`, `media_assets`, 6 `public_*` views), no write, no function execute. `authenticated`: one dead grant (`product_group_items` UPDATE without an UPDATE policy — harmless under RLS, least-privilege nit) |
| SECURITY DEFINER | all 97 set `search_path` explicitly (`public, pg_temp`, or `''` for pure helpers); none lacks it |
| Extensions | no unqualified pgcrypto calls remain (0007 F9); two trigram indexes (`companies_name_idx`, `products_name_idx`) need `pg_trgm` visible at index creation (baseline sets `search_path = public, extensions`) |
| Public views | 6, all `security_invoker=false` by design (owner-run, filter on published/approved); only `anon`-readable objects besides 3 tables |
| Storage policies | 8 on `storage.objects` (brochures, company-assets-public, product-media-pending/public, verification-docs); defined in baseline/0005/0006; 5 buckets with size and MIME limits; two buckets are public (reads bypass policies, by design) |
| Rollback ordering | `0007_down` → `0006_down` → … → `0001_down`; verified in Round 7 (normalised comparison equal); the 25-line raw dump difference is whitespace only |
| Fresh empty DB reproduces final schema | yes (this audit, plus Round 7 suites) |

## Discrepancies (documented, nothing historical modified)
1. **Two "baseline" artifacts.** `tests/baseline_reconstructed.sql` (older hand-built synthetic schema used only by the legacy 138-test suite, 0001–0005) is different from `migrations_draft/baseline/0000_baseline_reconstructed.sql`. The legacy suite never runs 0006/0007. Naming is confusing; keep separate, do not mix.
2. **Not Supabase-CLI layout.** Files live in `migrations_draft/` with sequential numbers; there is no `supabase/migrations/` directory and no `config.toml`. A GitHub-integrated branch builds from `supabase/migrations/` with timestamp versions (`YYYYMMDDHHMMSS_name.sql`); the baseline version must sort before 0001.
3. **Nested transactions.** Every file wraps itself in `begin; … commit;`. The CLI also wraps each migration in a transaction; the inner `commit` ends it early. Probably harmless (history row is inserted afterwards) but unverified on hosted.
4. **Identity-sequence privileges depend on platform default ACLs.** Staging's default ACL (read in Round 6) gives `anon`/`authenticated` nothing on new objects, so the chain yields no anon sequence access. With classic Supabase defaults (`ALTER DEFAULT PRIVILEGES … GRANT ALL … TO anon, authenticated, service_role`; simulated by `baseline/local_platform_classic_defaults.sql`) the full suite still passes (404/0), table/function exposure is unchanged, **but 7 identity sequences gain `anon` USAGE** (`contact_access_log_id_seq`, `lead_status_history_id_seq`, `lead_distribution_events_id_seq`, `claim_evidence_access_log_id_seq`, `staff_comms_access_log_id_seq`, `buyer_contact_access_log_id_seq`, `company_import_audit_id_seq`) and `service_role` gains full table rights on new tables. Impact: `nextval()` abuse (gaps), no data exposure. Fix (not applied): explicit `revoke all on sequence … from anon, authenticated` in a new migration.
5. **Two unvalidated constraints** (`company_members_invite_has_expiry`, `corrections_evidence_url_http`): `NOT VALID` by design; see INVITATION_TRANSITION_PROPOSAL.md.
6. **0006 defect fixed in 0007** (import_normalize regex) — history preserved, fix is forward-only.
7. **Helper oracles.** 9 `SECURITY DEFINER` lookup helpers are executable by every authenticated user (`claim_company`, `company_is_claimed`, `company_is_live`, `enquiry_company`, `group_company`, `product_company`, `seller_can_reply`, `seller_lead_visible`, `thread_company`) because RLS policies call them as the querying role. They only reveal a mapping for a UUID the caller already knows. Accepted; revoking would break policies.

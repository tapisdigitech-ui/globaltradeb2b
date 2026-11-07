# EXISTING SCHEMA MAP — staging `lhmexhafyuzojrmcbtbz` (read-only audit, 2026-11-07)

Method: read-only catalog queries (`pg_class`, `pg_policies`, `pg_proc`, `storage.*`, advisors). No data read beyond row counts; no writes. Production-candidate `kwtveqzeayupwrxpwkce` and TAPIS KASA were not queried.
State: **44 public tables, all RLS-enabled, all empty except `categories` (14 rows).** Staging-only; nothing is in production.

## Tables by domain (and which brief module they cover)
| Brief module | Existing table(s) | Notes |
|---|---|---|
| company_profiles | `companies` | `directory_status` (draft/pending_review/published/paused/rejected/suspended), `claim_status`, `verification_status`, `data_review_status`, `dedupe_key`, `import_batch_id`. Single `business_type` text (brief wants several). No export markets/capabilities/employees/etc. |
| company_contacts_private | `company_private` | one row per company: phone, email, address, pin, contact_person. **No per-contact status, last-verified, source, legal basis, do-not-contact; no read-audit.** |
| business_sources / provenance | `company_sources` (field-level: source_type, name, url, collected_at, last_checked_at, data_confidence), `company_import_batches` (`terms_checked` gate, rollback_ref) | Good field-level provenance already. |
| supplier_import_jobs / review queue | `company_import_batches`, `company_import_rows` (raw→normalised→duplicate_review→approved→imported), RPCs `import_normalize`, `import_apply`, `import_rollback`, `norm_name`, `norm_domain`, `suppression_list` | Pipeline foundation exists. |
| claims | `company_claims`, `company_claim_evidence`, `company_verification_reviews`, RPCs `submit_claim` (rate-limited 3/day), `review_claim`, `withdraw_claim`, `set_verification`, `create_company_request`; bucket `verification-docs` | **No email token / phone OTP / invitation records.** |
| members/sellers | `company_members` (owner/manager/sales/catalogue_editor/viewer), `company_membership_audit`, invitation RPCs | |
| products & images | `products`, `product_images` (pending_path/public_path + rights_status + review), `company_images`, `media_assets`, buckets `product-media-pending` (private), `product-media-public`, `company-assets-public` | Image rights model matches brief. |
| enquiries / requirements | `enquiries` (kind product\|requirement; `delivery` enum stored/awaiting_admin/visible_to_seller/sent_external/failed), `enquiry_private` (buyer contact, consent), `enquiry_contact_access` (audit), `enquiry_replies`, `lead_responses`, RPCs `submit_enquiry`, `respond_to_lead`, `reveal_buyer_contact`, `staff_mark_enquiry` | Requirement is only quantity/unit/message/city/category. |
| quotations/orders | `quotations`, `orders` + RPCs | |
| admin acquisition | `company_acquisition` (status: not_contacted…do_not_contact, owner, next_follow_up), `company_outreach_events` (call/email/invitation…, `delivery=sent` needs provider_ref else `logged_manual`), `company_follow_ups`, `company_internal_notes`, `moderation_actions`, `audit_log`, `company_data_corrections` | |
| messaging/notifications | `direct_threads/messages`, `notifications` (kinds: lead, enquiry, claim, admin…), `seller_settings` (notify flags) | No external channel/event config. |
| misc | `profiles` (`app_role`: buyer/seller/reviewer/admin), `categories` (flat), `cms_pages`, `rate_events` + `check_rate()`, `product_view_events` | |

## Public surface (anon)
anon has SELECT only on: `categories`, `cms_pages`, `media_assets` and six views — `public_companies` (id, slug, name, business_type, about, city, state, country, website, logo_path, `public_label`, is_claimed, is_verified, data_as_of, updated_at), `public_company_categories`, `public_company_images`, `public_company_sources`, `public_product_images`, `public_products`. **No contact columns in any public view** (verified from catalog column lists).

## Functions
79 functions in `public`. All SECURITY DEFINER ones set `search_path=public, pg_temp`. Authenticated-executable RPC surface (42) includes helpers (`is_staff`, `is_admin`, `has_company_role`…) and workflows. `is_staff()` = profile role admin OR reviewer; `is_admin()` = admin. `record_product_view` is service_role only.

## Storage
Buckets: `brochures` (private), `product-media-pending` (private), `product-media-public` (public), `company-assets-public` (public), `verification-docs` (private). Policies are folder-prefix = company id + `has_company_role`/`is_staff`; verification-docs read = claimant or staff, insert only while own claim open, delete admin only.

## Advisor results (security)
* ERROR ×6 `security_definer_view`: all six `public_*` views have `security_invoker=false` (they intentionally run as owner to expose only approved columns to anon). Needs a documented decision; alternative is security_invoker views + narrowly scoped anon policies.
* WARN ×42 `authenticated_security_definer_function_executable`: the intentional RPC surface; each function body must keep its own auth checks (spot-checked: `staff_mark_enquiry`, `submit_claim`, `is_staff`).
* INFO ×1 `rate_events` RLS with no policy (intentional: system table, accessed only via `check_rate`).

## Note (2026-11-07, later)
After the owner's instruction "no staging SQL execution", no further queries were run on staging. The map above is from the single read-only catalog pass. Draft additions (not applied) are in `supabase/migrations_draft/` and described in `MIGRATION_IMPACT_REPORT.md`.

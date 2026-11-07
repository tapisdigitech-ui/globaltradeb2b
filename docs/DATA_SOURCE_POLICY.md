# DATA SOURCE POLICY (v1, for review)

1. **Allow-list only.** A source is usable only after a staff member records it in `company_import_batches` with `terms_checked = true` and a `terms_note` (terms of service, robots.txt, licence, API terms). No batch may be applied otherwise (existing gate).
2. **Permitted source types** (enum `source_type`): official_website, public_business_directory, trade_association, exhibitor_directory, government_registry, direct_submission, licensed_data_provider, other_approved.
3. **Prohibited:** bypassing CAPTCHA/login/paywall/anti-bot, ignoring robots or rate limits, copying proprietary competitor databases, collecting personal (non-business) data, using fabricated records, hotlinking or republishing competitor photos.
4. **Controlled batches:** first batch ≤ 50 records, manual review of every row; scale only after a clean review. Target 1,000–5,000 over time.
5. **Provenance:** every published field has a `company_sources` row (source type/name/url, collected_at, last_checked_at, confidence). Missing values stay empty — never inferred or invented.
6. **Contacts:** found phones/emails go only to the contact vault (`company_contacts`), status starts `unverified`, never shown publicly, never used by automation. Outreach is manual and individually initiated by staff; suppression list and do-not-contact are honoured and block re-import.
7. **Publication:** public profile only after `data_review_status = approved` and `directory_status = published`; labels Unclaimed / Claimed / Verified follow `claim_status` and `verification_status`, never contact presence.
8. **Removal:** a supplier's removal request goes to `suppression_list` and takes effect before the next import.
9. **Images:** see IMAGE_LICENSING_POLICY (to be written in Phase 2); unclaimed profiles may use clearly labelled category illustrations only.
10. **No automated fetching is implemented yet.** This policy gates the future connectors.

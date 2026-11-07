# URL-field inventory (Round 8) — audit and proposal, nothing applied

Sources: final local schema (baseline + 0001–0007, PG 16.15), function signatures/bodies, `index.html` demo UI, Edge Function code. Staging was not queried.

## 1. Inventory
| Field | Written by | Read by | Class | DB check today | Risks |
|---|---|---|---|---|---|
| `companies.website` | company owner/manager edit; imports; staff | `public_companies.website` (**anon**) → public profile | **Public clickable link** | none | `javascript:`/`data:` href (XSS on click); `http://user:pw@host` phishing form; scheme-less values common |
| `company_sources.source_url` | staff, imports, `create_company_request` (internal token `direct-submission:<uid>`) | `public_company_sources.source_url` (**anon**; internal token filtered out) | Public clickable link | none | same XSS class; view filters only the internal token, not unsafe schemes |
| `products.source_url` | staff / imports (guarded column) | `public_products.source_url` (**anon**) | Public clickable link | none | same |
| `company_data_corrections.evidence_url` | any authenticated user via `report_correction` | staff review screens | Staff-visible clickable link (user-submitted) | **0007: http(s) only, ≤500, NOT VALID check + function check** | XSS in staff UI if rendered unescaped; phishing; SSRF only if a future fetcher uses it |
| `company_contacts.source_url` | `staff_add_contact(p_source_url)` | `staff_get_contacts` (staff) | Administrative-only, may be rendered as link | none | stored XSS in staff console |
| `company_images.source_url`, `product_images.image_source_url` | staff / sellers (provenance) | staff; `approve_product_image` requires non-empty | Administrative-only provenance | none | link rendering in staff UI |
| `company_import_batches.source_url`, `company_import_rows.website`/`domain` | staff import | import screens; `import_apply` copies website to `companies.website` | Administrative-only → becomes public via `website` | `import_normalize` flags non-http(s) websites (regex fixed in 0007) but batch `source_url` unchecked | unsafe scheme survives into batch metadata |
| `notifications.link` | server-side only (`notify_on_enquiry`, `review_claim`, …); `authenticated` has no INSERT | owner's UI | Internal navigation | n/a (users cannot write) | low; keep relative app routes only |
| `suppression_list.domain`, `claim_verifications.domain_matches_website` | staff / system | staff | Plain-text reference / flag | none needed | none |
| Storage paths: `companies.logo_path`, `company_images.path`, `product_images.public_path/pending_path`, `brochures.path`, `company_claim_evidence.storage_path`, `media_assets.path` | server/staff/seller upload flows | public views expose `logo_path`, `path`, `public_path` | Internal references (bucket keys), turned into URLs by the client | folder-based storage policies | path traversal prevented by `storage.foldername()` + `safe_uuid()` in policies; client must build URLs from the project base, not from raw column text |
| Function parameters | `report_correction(p_url)`, `staff_add_contact(p_source_url)`; evidence-link Edge Function takes ids, not URLs | | | | |
| Redirect destinations | **none in the repo** (no `next=`, `returnTo`, `location =` from user input) | | Redirect | — | no open redirect today; Supabase Auth redirect allow-list is a hosted setting (unverified) |
| Server-side fetch of user URLs | **none** (Edge Function only calls Supabase APIs; no crawler/importer fetches URLs in code) | | SSRF | — | none today; any future fetcher must resolve DNS and block private/link-local ranges |

### Frontend (demo `index.html`, localStorage only, not connected to Supabase)
- Company website link: scheme enforced (`/^https?:\/\//` else `https://` prefix) then escaped — safe pattern, but `https://javascript:…`-style and `javascript:alert(1)` become `https://javascript:alert(1)` (inert). Videos: `^https?://` required.
- **Finding U1:** image/logo `src` values from stored data are concatenated into HTML without escaping (`'<img … src="'+u+'">'`, `c.logo`). Values come from local file uploads (data URLs) in the demo; with real data this must use `esc()` and a `https:`/`blob:`/`data:image/` allow-list.
- The demo has no code path reading `source_url`, `evidence_url`, or any API; the real console is not built, so there is no live XSS today.

## 2. Findings
| # | Severity | Finding |
|---|---|---|
| U1 | Medium (future) | Unescaped `src` interpolation in the demo; fix before any real data binding |
| U2 | Medium | Three **anon-readable** URL fields (`website`, two `source_url`) have no scheme restriction at the DB: a `javascript:` value that reaches a published company would be served to the public API and rendered by any naive client |
| U3 | Low–Medium | Staff-only URL fields (`company_contacts.source_url`, image sources, batch URLs) unchecked → stored XSS risk in the staff console |
| U4 | Info | No open-redirect or SSRF surface exists in the repository; both remain hosted-config / future-code concerns |
| U5 | Info | `http://localhost`, private IPs and `169.254.169.254` are syntactically valid http(s) URLs; scheme validation does not address SSRF — it must be handled where a fetch is implemented |

## 3. Proposed validation rules (proposal `supabase/proposals/0009_url_validation_PROPOSAL.sql`, not applied)
- `is_http_url(u)`: http/https only (case-insensitive), 8–500 chars, no whitespace/control characters, no `<>"'`, **no userinfo** (`user:pw@`).
- `is_website_value(u)`: `is_http_url(u)` **or** a scheme-less value (no `scheme:` prefix), so existing "example.com" data and the UI's `https://` prefixing keep working.
- `NOT VALID` check constraints on: `companies.website`, `products.source_url`, `company_sources.source_url` (plus the internal `direct-submission:<uuid>` token), `company_contacts.source_url`, `company_images.source_url`, `product_images.image_source_url`, `company_import_batches.source_url`, `company_import_rows.website`. `report_correction` keeps its 0007 rule.
- Recommended follow-up (not in the proposal SQL): add `source_url ~* '^https?://'` to the `public_company_sources` and `public_products` view definitions as defence in depth; re-run the fingerprint comparison after that change.
- Client rule: render links only when the value passes the same regex; always `rel="noopener noreferrer"`, escape attribute values, build storage URLs from the project base + bucket + path.

### Compatibility
- NOT VALID: no existing row is scanned or rejected; later updates to a row with a bad value must fix that column (same behaviour as the 0007 constraints). Before `VALIDATE`, count violators with a read-only aggregate (needs approval; unknown today).
- Scheme-less websites remain accepted. Values with spaces or angle brackets that were previously accepted will be refused on write.
- Imports (`import_apply`) copy `website` into `companies`; a row failing the new check would abort the apply — `import_normalize` should flag it earlier (already flags non-http(s) websites).

## 4. Tests
`bash tests/run_proposal_urls.sh control|proposal` (local PG16): control 2/2 (javascript: accepted today; public source view has no scheme filter); proposal 9/9 (accept/reject matrices incl. `javascript:`, `data:`, `file:`, `ftp:`, `vbscript:`, `blob:`, `mailto:`, `tel:`, protocol-relative, whitespace, control chars, quotes, userinfo, oversize, NULL; website tolerance; table-level enforcement on 3+ tables; NOT VALID state; down).

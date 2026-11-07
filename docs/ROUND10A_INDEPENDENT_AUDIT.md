# Round 10A — Independent Engineering Audit

Repository `tapisdigitech-ui/globaltradeb2b`, branch `feature/supplier-intelligence-phase0`, starting commit `ff4abed` (clean tree).
Scope: this repository only. No hosted Supabase access of any kind this round (not even read-only), no Docker/Supabase services started, no migration or proposal modified or applied, nothing deployed, no communications, synthetic data only.
Companion documents: `docs/PRIORITISED_LAUNCH_CHECKLIST.md` (every finding with file, fix, tests, migration need) and `docs/FRONTEND_BACKEND_INTEGRATION_CONTRACT.md`.

## 0. Method and evidence labels

The final schema was rebuilt in a throw-away **local PostgreSQL 17.11** database (baseline + 0001–0008 + seed, via `baseline/load_baseline.sh`) and audited through the catalogue, then probed with synthetic fixtures under `SET ROLE authenticated` with injected JWT claims. That database was dropped afterwards. Evidence labels used below:

- **CONFIRMED** — reproduced in the local PG17.11 replica by a probe run this round.
- **CATALOGUE** — read directly from the final schema catalogue (policies, grants, function bodies, constraints).
- **STATIC** — from reading code/config; not executed.
- **NOT VERIFIED** — needs the real Supabase stack (GoTrue, PostgREST, Storage, Edge runtime) which was not available.

Everything here is a local-replica result. Earlier passing suites were not treated as proof; the audit looked for paths they might not cover.

## 1. Result summary

- **No path was found that exposes private supplier contacts, buyer contacts or claim evidence to an unauthorised role** in the final schema. The contact vault, buyer-contact reveal, evidence grants, Storage policies and anon surface held up under catalogue review and probes.
- **Four integrity/trust gaps were confirmed** (F-A product re-publication bypass, F-B verified-company identity edits, F-C demo rows unlabelled in public views, F-E no erasure path). F-A, F-B and F-C already exist in the baseline, i.e. in the currently deployed schema, not in 0001–0008.
- Several operational gaps (retention, invitation lifecycle, idempotency, CI) and frontend-integration risks are listed.
- **No P0 data-exposure vulnerability.** The P0 items are process/validation gates (§8).
- Not verifiable here: everything that depends on the real stack (the previous round's blocker is unchanged).

## 2. Task 1 — Repository and migration integrity

| Check | Result |
|---|---|
| Branch / commit / tree | `feature/supplier-intelligence-phase0`, `ff4abed`, clean |
| Migration ordering | `supabase/migrations/` has 9 files, 14-digit timestamps `20261107120000…120800`, strictly ascending, no duplicates, names match `^\d{14}_[a-z0-9_]+\.sql$` |
| Drafts vs CLI copies | `migrations_draft/000[1-8]_*.sql` and the baseline are **byte-identical** to the CLI copies (`packaging/sync_cli_migrations.sh` by design) |
| Begin/commit | each of 0001–0008 has exactly one `begin;` and one `commit;` |
| Rollback inventory | `migrations_draft/down/0001_down.sql … 0008_down.sql` all present (3–450 lines); down files are deliberately not in `migrations/` |
| CLI config | `config.toml`: `major_version = 17`, seed `./seed.sql`, `[functions.evidence-link] verify_jwt = true`, storage 50 MiB; see F-T for Auth settings |
| Seed | `seed.sql`: 14 categories, idempotent, ends with a loud completeness guard; contains no suppliers/buyers/accounts |
| Guard scripts | `ops/guard_target.sh`, `verify_fingerprint.sh` present; `bash -n` passes on all 28 shell scripts |
| Secrets | pattern scan of all tracked files found no JWTs, service keys, private keys, DB URLs with passwords, AWS/Google keys |
| Hosted identifiers | project refs (not secrets) appear in 10 docs and `ops/guard_target.sh` (intended) |
| `staging_schema/` | exists locally, **untracked and git-ignored** (read-only catalogue extract, no table data) — correct |

Duplicate / obsolete / conflicting files (nothing deleted or renamed; each is documented, not changed):

1. `supabase/tests/baseline_reconstructed.sql` — a *different* (legacy synthetic) schema with the same base name as the real baseline; used only by the legacy 138-test suite. Confusing name; rename later (P2).
2. `supabase/reports/*` — Round-5-era schema dumps (≈310 KB) and an old test output; stale, committed. Candidates for removal (P2).
3. `supabase/proposals/0008_*`, `0009_*` — **numbering collides** with real `0008_sequence_privileges`; they must be renumbered (≥0009) when approved. The proposal header already says so.
4. 16 shell scripts are mode `0644` (not executable): `tests/run_*.sh`, `concurrency_0007.sh`, `dry_run_*.sh`, `rollback_fingerprint.sh`, `packaging/*.sh`, `baseline/load_baseline_classic.sh`. They work via `bash script`; documented usage is `bash …` (P2).
5. `supabase/migrations_draft/` + `supabase/migrations/` duplication is intentional (source of truth vs CLI layout); `sync_cli_migrations.sh --check` is the safeguard.
6. No `package.json`, lockfile, CI workflow, `.env.example` exists (see §6, §7).

## 3. Task 2 — Security architecture audit

Method: catalogue queries on the final schema plus targeted probes. Table = area → what was checked → result.

| Area | Checked | Result |
|---|---|---|
| Tables / RLS | all 66 public tables | RLS **enabled and forced on all 66** (CATALOGUE) |
| Anon surface | grants, policies, functions | anon has SELECT only on `categories`, `cms_pages`, `media_assets` and the 6 `public_*` views; **zero** anon-executable functions; policies on `to public` (many) are inert for anon because anon has no table grants — relies on grants, not policy roles (F-Q) |
| Public views | columns, filters | `public_companies`: no phone/email/address; label logic correct for claim/verification state; filters `published` + `data_review_status='approved'`. Demo rows not excluded and not flagged → **F-C (CONFIRMED)** |
| SECURITY DEFINER | 97 definer functions (of 115 in `public`) | every definer function is owned by `postgres` with a pinned `search_path` (query returned 0 exceptions); `_company_lead_eligible`, `_match_requirement`, `_evidence_gate` etc. are not executable by API roles |
| Supplier contacts | `company_contacts`, `staff_*_contact*` | no direct staff table access; owner/manager read own; staff path = purpose + assignment + immutable log; `do_not_contact` values returned as NULL |
| Buyer contacts | `enquiry_private`, `reveal_buyer_contact`, `staff_open_buyer_contact` | seller reveal needs eligible, matched/own-company + prior lead response; eligibility re-checked at access time; logged; rate 100/day; staff path = assignment + purpose + 10-min grant + log |
| Claim ownership / reviewers | `staff_can_review_claim`, `review_claim`, assignments | assignment-scoped since 0006; closed claims drop out of access; approval needs evidence + verified email (via `claim_verifications`) + no competing claim |
| Evidence access | `cev_read`, `vd_*`, `_evidence_gate`, Edge | claimant-only table; staff only via audited grant (≤600 s link, 10-min grant, rate limits, non-raising audit); Edge adds path-prefix check `claimId/…`; Storage read policy re-evaluated with caller JWT. See F-G for gaps |
| Lead routing | `_company_lead_eligible`, `_match_requirement` | verified-only direct routing; cap per requirement; demo companies excluded from matching; duplicates blocked by unique index |
| Seller notifications | `notify_on_enquiry`, routing | requirement creation notifies nobody; only eligible companies get product-enquiry notifications; subject only (80 chars) |
| Buyer enquiry privacy | `enquiries` guards, `guard_enquiry` | all buyer-authored columns immutable to sellers/staff (only `status` changes); **sellers can read `buyer_id` and free-text fields** (F-I) |
| Messages / quotations | `dm_*`, `dt_*`, `quotes_*`, `guard_quote` | buyer + seller roles + admin; other staff only via logged grant. **Admin reads are unlogged** (F-O, known; proposals exist) |
| Orders | `create_order`, `advance_order`, `cancel_order` | ownership enforced (`for update`), transition table enforced; buyer cancel only while `placed` |
| Import pipeline | import tables, `import_apply` | admin-only; requires `terms_checked`; imported companies default `draft`/`pending`/`unclaimed`/`not_verified`; no contacts imported; rollback refuses when dependent rows exist |
| Staff / admin | `is_staff`, `is_admin`, `guard_profile_role` | `app_role` not user-editable (**CONFIRMED**: update raises `app_role is not user-editable`); `user_metadata`/`app_metadata` claims `admin` give `is_admin() = false` (**CONFIRMED**); `handle_new_user` always creates `buyer` |
| Audit log | `audit_log`, `audit_changes` | immutable trigger; audit triggers are UPDATE-only on status columns, so **no PII is copied into `audit_log`** (hypothesis tested and refuted). Name/website changes are not audited (F-B) |
| Sequences | 0008 | no `anon`/`authenticated` rights except `USAGE` on `categories_id_seq`; default privileges narrowed |
| Storage | 8 policies, 5 buckets | `verification-docs` private, 10 MiB, pdf/jpeg/png; `brochures` private; public buckets image-only 5 MiB; `product-media-public` admin-write only; `company-assets-public` is owner/manager/editor-writable and **public with no moderation** (P2) |

### Confirmed findings (probe evidence)

**F-A — Seller can republish edited product content without review (CONFIRMED).** `guard_product` (baseline, line ~258) resets review when a *published* product's text changes, but allows `published → paused` and `paused → published`, and applies no reset while paused. Probe, as an owner of a synthetic claimed company: set `paused`; change `description` to an unreviewed claim ("ISO certified, FDA approved"); set `published`. Result: `directory_status = published`, `data_review_status = approved`, and the new text is returned by `public_products`. Impact: unreviewed, potentially false claims go live; defeats "review before publish". Pre-existing in baseline.

**F-B — Verified company can change identity fields; badge persists (CONFIRMED).** `companies_member_update` + `guard_company_columns` protect status columns only. Probe: a member of a *verified* company set `name`, `website`, `about` to different values; `public_companies` immediately showed the new name and website with `public_label = 'Verified'`. No review reset and no audit entry (`audit_changes` on companies tracks four status columns only). Impact: verification attaches to the old identity; hijack/phishing via the verified badge. Pre-existing in baseline.

**F-C — Demo companies indistinguishable in public views (CONFIRMED).** A published, approved `is_demo = true` company appears in `public_companies` with label `Unclaimed — Not Verified` and no demo marker; the view has no `is_demo` column and no filter. Matching excludes demo rows, but the directory does not. Impact: demo data can be presented as real listings. Pre-existing view in baseline.

### Other findings (CATALOGUE / STATIC)

- **F-D** (STATIC) `claim_invitations`: no function sets `expired` or `cancelled` (only `redeemed`/`sent_manual`/`approved`). The partial unique index `claim_invitations_one_active` (`draft|approved|sent_manual`) therefore blocks any new invitation for a company after an unredeemed/expired one. Redemption correctly fails after `expires_at`, so this is operational, not a security hole. Not executed.
- **F-E** (CATALOGUE) No erasure/anonymisation function exists; foreign keys from 27 tables to `profiles` are `NO ACTION` (e.g. `enquiries.buyer_id`, `orders.buyer_id`, `direct_threads.buyer_id`), so a user with activity cannot be deleted; `enquiry_private` (buyer name/phone/email/company) has no retention rule.
- **F-F** (CATALOGUE) No purge/retention function and no `pg_cron`; 14 log/event tables (`rate_events`, `product_view_events`, `audit_log`, notifications, access logs, `claim_verification_outbox`, …) grow without bound against the Free plan's 500 MB cap. Expired unverified OTP rows (plaintext code + phone/email target) in `claim_verification_outbox` are never purged.
- **F-G** (STATIC) Evidence: (1) `company_claim_evidence.storage_path` has no constraint tying it to `<claim_id>/…` or a safe name; Storage and Edge reject cross-claim paths (second barrier confirmed in code: `startsWith(claimId + '/')`, `SAFE_NAME`), but one malformed row makes the whole Edge request return 502 for that claim. (2) `vd_read` allows an assigned reviewer with an active grant to read **every** object under the claim folder directly through Storage for 10 minutes; those direct reads are not individually logged (the grant and requested ids are). (3) Issued signed URLs cannot be revoked (documented in the Edge response note).
- **F-H** (STATIC) Claim approval requires a verified email, but codes are written to an outbox with no delivery provider ("provider not enabled"), so the gate cannot currently be satisfied through the product; and local `config.toml` has `enable_confirmations = false`.
- **F-I** (CATALOGUE) Sellers with a visible lead can `SELECT` `enquiries.buyer_id` and `requirement_details.buyer_id` (stable pseudonymous id) plus all free-text columns; buyers may type phone/email into `message/additional/specifications`.
- **F-J** (STATIC) `submit_enquiry` for product enquiries has no duplicate/idempotency protection (only 10/h, 30/day rate limits); `check_rate` is read-then-insert without a lock (small overshoot possible under concurrency); `create_requirement` raises `duplicate requirement` *after* the step-1 `submit_enquiry` already stored an `enquiries` + `enquiry_private` row (orphan).
- **F-L** (design) `review_claim` lets one assigned reviewer approve a claim and make the claimant owner/seller (no second approver).
- **F-N** (CATALOGUE) Company-image approval is allowed to assigned staff (`guard_company_image`, `cimg_upd`), while product-image approval is admin-only (Round 4) — inconsistent.
- **F-O** (known) Admin reads of messages, orders and profiles are unlogged (`ADMIN_MESSAGE_AUDIT_PROPOSAL.md`, `PRIVACY_REVIEW_PROPOSAL.md`).
- **F-Q** (CATALOGUE) 91 of the 120 policies (public + storage) are `to public` rather than `to authenticated`; safe today only because `anon` has no table grants and no function execute rights.
- **F-T** (STATIC) `config.toml`: `[auth.email] enable_confirmations = false`, `minimum_password_length = 6`, `enable_signup = true`, `secure_password_change = false` — local defaults. They matter if config is ever pushed or the hosted dashboard mirrors them.

Items checked and **not** a finding: role self-escalation, metadata admin claims, buyer-column tampering by sellers, audit PII leakage, product-image bypass (image edits reset review), import auto-publication, direct thread creation with unclaimed companies (blocked by `guard_direct_thread`), cross-claim evidence paths, sequence leakage.

## 4. Task 3 / 4 — Frontend contract and privacy (summary)

Details are in `FRONTEND_BACKEND_INTEGRATION_CONTRACT.md`. Headlines:

- `index.html` (5,210 lines, one file) is a client-only demo: every record lives in `localStorage` (`gtb2b-*` keys); no network calls to a backend; demo ribbon and "saved in this browser only / nothing sent" notes are present on most flows.
- Copy that could be read as real delivery or capability (should carry a demo qualifier or change at integration): FAQ line 1046 ("matching suppliers will send quotations"), how-it-works line 1085 ("Your details go to each supplier"), static "Contact Supplier" / "Get Best Price" buttons on sample cards (lines ~2740, 2937, 3320, 3335), seller onboarding line 3700 ("Buyers will contact you on these details"). The simulated lead desk labels delivery "(simulated)" correctly (line 3474).
- Admin console and Seller Centre are reachable by anyone through `#admin` / `#seller` (client-side `UI.role`). Not a vulnerability in a demo; it must never be treated as access control.
- Buyer name/phone/email are stored in plaintext in the browser and rendered to the admin view (line ~5134). Demo only.
- No private supplier phone/email is rendered anywhere; sellers' contact statuses ("email verified") are shown only as statuses.
- 103 `innerHTML` assignments with `esc()` used 139 times; no unescaped user-field concatenation was found by pattern search, but a proper XSS review is required before real data is rendered.
- Third-party requests: 103 Unsplash image URLs, Google Fonts, YouTube links (no consent mechanism, no CSP/Referrer-Policy meta). Product photos are category illustrations, not supplier photos (stated in the footer/README); real listings need provenance and usage rights, which the schema already models (`rights_status`, `image_source_url`, `permission_evidence`, public view requires `owned|licensed|permission_granted|public_domain` and `approved`).

## 5. Task 5 — Operational readiness

| Topic | State | Gap |
|---|---|---|
| Error handling | RPCs raise SQLSTATE-coded errors (`42501`, `28000`, `P0001` rate limit); Edge returns generic 401/403/429/502/503 without ids/paths | mapping to HTTP via PostgREST not verified (real stack); no CORS/OPTIONS handling in `index.ts` |
| Duplicate protection | requirements: 24 h dedupe + advisory lock; leads: unique `(enquiry, company)`; invitations: one active per company | product enquiries and orders lack idempotency keys (F-J) |
| Rate limiting | `check_rate` called from 14 functions (plus generic rate triggers, e.g. on direct_threads, direct_messages, enquiry_replies, claim evidence); evidence gate has its own limits | non-atomic (F-J); no IP/anon limiting (platform-level only) |
| Idempotency | `on conflict do nothing` on matches/events/responses | no client idempotency key convention |
| Audit logging | immutable audit/log tables for contacts, evidence, buyer contact, comms, imports, moderation | admin message/order/profile reads unlogged (F-O); name/website edits unaudited (F-B) |
| Import rollback | `import_rollback` guarded and audited | none new |
| Invitation expiry | company member invites expire in 14 days (fail-closed, 0007); claim invitations expire on redeem but never change status (F-D) | lifecycle function |
| Evidence-link expiry | grant 10 min, link ≤600 s capped by remaining grant | links not revocable (documented) |
| DB recovery | `FREE_PLAN_DEPLOYMENT_STRATEGY.md`, rehearsal scripts | no backup exists; no automatic backups on Free |
| Env vars | Edge reads `SUPABASE_URL`/`SUPABASE_ANON_KEY` only (no service key); `.env*` git-ignored | no `.env.example`; Studio `OPENAI_API_KEY` placeholder in config |
| Build / deploy | none (static HTML + SQL); no CI, no workflow, no package manifest | CI that runs the local suite is missing |

## 6. Task 6 — Static checks: what actually ran

| Check | Ran? | Result |
|---|---|---|
| Migration naming / ordering / begin-commit / down-file presence | yes (custom script) | pass |
| Drafts vs CLI copies identical | yes (`diff`) | pass |
| `bash -n` on all shell scripts | yes | pass |
| Script permission check | yes | 16 non-executable (P2) |
| `node --check` on Edge `.mjs` | yes | pass |
| ESLint 10.1.0 on `handler.mjs` (temporary minimal config in `/tmp`, not committed) | yes | 0 errors, 1 warning (unused `e` at line 50) |
| TypeScript 7.0.2 on `index.ts` | ran, **not meaningful** | only Deno/npm-specifier type errors (no Deno types installed) — unavailable |
| Secret scan | yes (regex patterns; no gitleaks/trufflehog installed) | no findings |
| SQL static check | partially: all 9 migrations apply cleanly on PG17.11; catalogue queries for RLS/definer/search_path/grants | pass; no sqlfluff installed |
| Dependency / lockfile consistency | n/a — repository has no package manifest | — |
| Test discovery | yes | 53 files under `tests/` and `ops/`; suite entry point `tests/run_round9_all.sh`; not re-run this round (no change to code) |
| Docker / hosted checks | not run (restricted) | — |

No dependencies were installed or upgraded.

## 7. Task 7 — Outstanding proposals

| Proposal | Touches | Depends on | Conflicts / overlaps |
|---|---|---|---|
| `0007a` legacy invitation transition | data fix on `company_members.expires_at`; validates `company_members_invite_has_expiry` | 0007 | none; only needed if hosted data has NULL-expiry pending invites (requires a read-only count first) |
| `0008` admin message audit (`proposals/0008_…`) | `dt_read`, message/quotation policies, new grant/log tables | 0001–0007 (+ current policies) | **number collision with real 0008**; overlaps `PRIVACY_REVIEW_PROPOSAL` (admin reads of orders/profiles) — one grant mechanism should serve both |
| `0009` URL validation (`proposals/0009_…`) | `NOT VALID` CHECK constraints on 8 tables, 2 pure functions | 0007 F3/F10 (URL scheme work) | partial overlap with 0007 F3 (corrections `evidence_url`); verify no duplicate constraint; `VALIDATE` only after a read-only violator count |
| Privacy review proposal | docs only | — | design input for the admin-audit migration and for F-E/F-F |
| `EVIDENCE_LINK_FUNCTION.md` | documentation of existing Edge function | 0006 | consistent with code; add F-G items |
| `FREE_PLAN_DEPLOYMENT_STRATEGY.md` | process | — | independent; P0 gates feed it |

**Recommended implementation order** (each step: local suite green, then separate approval; nothing here is applied):
1. **New hardening migration (call it 0009-candidate, from this audit):** F-A, F-B (+ audit of identity fields), F-C (view change or filter), F-D lifecycle function, F-G(1) path constraint. One reviewed unit, with new regression tests.
2. `0009` URL validation proposal (renumber after step 1) — `NOT VALID` first.
3. Retention/erasure design (F-E, F-F) — policy decision first, then migration + scheduled job (Free plan includes `pg_cron`; confirm before enabling).
4. Admin-access audit (merge the admin-message-audit proposal and the privacy-review items into one migration) — before real buyer messaging.
5. `0007a` only if the staging/prod data contain legacy NULL-expiry invites.

## 8. Remaining verification (cannot be done here)
Real Auth/PostgREST/Storage/Edge behaviour (P0-1), hosted Auth settings (P0-2), Storage and signed-URL expiry on the real service, HTTP status mapping of SQLSTATEs, hosted-only quotas and timeouts. See `ROUND10_LOCAL_SUPABASE_VALIDATION.md` §9.

## 9. Limitations of this audit
Local replica with a platform stand-in; probes cover the paths named above, not every function body (97 definer functions; ~25 bodies read in full). Findings marked STATIC were not executed. The frontend was reviewed by pattern search and sampling, not line by line. Legal sufficiency of the consent/legitimate-interest basis (`company_contacts.legal_basis`) is a counsel decision and is not assessed.

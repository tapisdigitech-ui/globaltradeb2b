# IMPLEMENTATION ROADMAP

Branching: each phase on `feature/<phase-name>` branched from the previous reviewed branch (base now: `main` @ 31316d7, which already contains `redesign/homepage-v2`). Vercel preview per branch. No merge/push to main without approval.

| Phase | Deliverables | Depends on | Can proceed now? |
|---|---|---|---|
| 0 Audit | These 5 docs | — | Done except schema map (blocked) |
| 1 Supplier intelligence foundation | **Extend, not rebuild**: contact-vault v2 (`company_contacts`), company profile extensions (business types, capabilities, export markets), subcategories, demo flag, DATA_SOURCE_POLICY, DATA_DICTIONARY, SUPPLIER_DATA_MODEL; SQL drafted and tested on a local scratch Postgres before any staging apply | Staging schema (now read) | Yes |
| 2 Public directory | Profile pages with Unclaimed/Claimed/Verified labels, Claim button, directory search, SEO structure (real URLs, sitemap, noindex for thin pages) | Phase 1 data model | UI on demo data labelled as demo: yes |
| 3 Claim & verification | Claim flow UI + DB, email/phone verification, private docs, admin review | Phase 1; Auth | UI prototype only |
| 4 Requirements & matching | Requirement form (all brief fields), SQL scoring with explanations, duplicate protection | Phase 1 | Form UI + matching logic locally |
| 5 Admin lead desk | Overview, assignments, calls, follow-ups, invitations (individual, disabled until approved), reports | Phases 1,4 | UI prototype |
| 6 Direct routing | Eligibility, Path A/B, delivery audit, scenarios 1–7 tests | 3,4,5 | After DB |
| 7 Seller experience | Extend existing Seller Centre to the new data | 6 | Later |
| 8 Growth/SEO, 9 Monetisation | per brief; billing stays off | — | Later |

## Decisions made without asking
* Keep the static prototype as the UI reference. Backend = the existing Supabase Phase 2 schema, extended by numbered migrations in `supabase/migrations_draft/`. Not applied to staging until reviewed.
* Pure-logic modules (normalise, dedupe, scoring, routing eligibility) are written dependency-free with unit tests, so they port to SQL/Edge functions.
* Demo records stay demo-flagged forever.

## Approvals needed before specific steps
Applying any migration to staging; creating real accounts; enabling email/SMS; first real ingestion batch (source list + terms review); any production change.

## Gap list driving Phases 1–6 (from the schema audit)
| # | Gap | Phase | Approach |
|---|---|---|---|
| G1 | Contact vault v2 with per-contact status, source, legal basis, last verified, do-not-contact, audited reads | 1 | new `company_contacts` + audited RPC; migrate from `company_private` later |
| G2 | Profile extensions: multiple business types, capabilities, export markets | 1 | additive columns/tables on companies |
| G3 | Subcategories | 1 | `categories.parent_id` |
| G4 | Structured buyer requirement + matching + explanation | 4 | `requirement_details`, `requirement_matches` (score + reasons jsonb) |
| G5 | Lead case (admin lead desk), assignment, status history, distribution events, duplicate protection | 5/6 | `lead_cases`, `lead_status_history`, `lead_distribution_events` with unique (enquiry, company) |
| G6 | Path A eligibility = verified + contact verified + active | 6 | `seller_is_lead_eligible(company)`; replace `enq_leads_read` predicate |
| G7 | Assignment-scoped staff | 5 | `is_assigned_staff()` helper, audited |
| G8 | Claim email-token / phone OTP / invitations | 3 | `claim_verifications` (hashed tokens, expiry, attempts), `claim_invitations` (individual, staff-initiated, delivery logged_manual until provider enabled) |
| G9 | Reports excluding demo data | 5 | views over real rows, `is_demo` flag |

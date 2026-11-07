# IMPLEMENTATION ROADMAP

Branching: each phase on `feature/<phase-name>` branched from the previous reviewed branch (base now: `main` @ 31316d7, which already contains `redesign/homepage-v2`). Vercel preview per branch. No merge/push to main without approval.

| Phase | Deliverables | Depends on | Can proceed now? |
|---|---|---|---|
| 0 Audit | These 5 docs | — | Done except schema map (blocked) |
| 1 Supplier intelligence foundation | SQL migrations (drafted, not applied), source registry, normalisation + duplicate detection (pure functions, unit-tested locally), provenance, contact vault design, DATA_SOURCE_POLICY, DATA_DICTIONARY, SUPPLIER_DATA_MODEL | Staging schema | Docs + local-tested pure logic: yes. SQL: after schema read |
| 2 Public directory | Profile pages with Unclaimed/Claimed/Verified labels, Claim button, directory search, SEO structure (real URLs, sitemap, noindex for thin pages) | Phase 1 data model | UI on demo data labelled as demo: yes |
| 3 Claim & verification | Claim flow UI + DB, email/phone verification, private docs, admin review | Phase 1; Auth | UI prototype only |
| 4 Requirements & matching | Requirement form (all brief fields), SQL scoring with explanations, duplicate protection | Phase 1 | Form UI + matching logic locally |
| 5 Admin lead desk | Overview, assignments, calls, follow-ups, invitations (individual, disabled until approved), reports | Phases 1,4 | UI prototype |
| 6 Direct routing | Eligibility, Path A/B, delivery audit, scenarios 1–7 tests | 3,4,5 | After DB |
| 7 Seller experience | Extend existing Seller Centre to the new data | 6 | Later |
| 8 Growth/SEO, 9 Monetisation | per brief; billing stays off | — | Later |

## Decisions made without asking
* Keep the static prototype as the UI reference; production backend/Next.js structure to be decided after the schema read (the brief mentions Next.js but this repo has none).
* Pure-logic modules (normalise, dedupe, scoring, routing eligibility) are written dependency-free with unit tests, so they port to SQL/Edge functions.
* Demo records stay demo-flagged forever.

## Approvals needed before specific steps
Applying any migration to staging; creating real accounts; enabling email/SMS; first real ingestion batch (source list + terms review); any production change.

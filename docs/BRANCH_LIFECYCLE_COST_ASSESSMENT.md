# Branch lifecycle and cost assessment (Round 8) — no branch created

Public sources read on 2026-11-07: [Manage Branching usage](https://supabase.com/docs/guides/platform/manage-your-usage/branching), [Branching](https://supabase.com/docs/guides/deployment/branching), [Pricing](https://supabase.com/pricing).

## Plan requirement (publicly verifiable part)
- Pricing page: branching is **not included on Free**; listed at "$0.01344 per branch, per hour" for Pro and Team; its FAQ says "available on the Pro Plan and above". The branching docs themselves say you can deploy from GitHub "on any plan" but do not name a required plan for branches. **The organisation's actual plan is not known to me and must be confirmed by you**; I did not look it up.

## Cost model (documented rates; Micro compute default)
| Duration | Compute |
|---|---|
| 24 h | $0.32 |
| 48 h | $0.65 |
| 72 h | $0.97 |
| 7 days | $2.26 |
Other lines: **disk** billed at the parent's rate; the usage page's example stayed within the plan's included 8 GB disk, adding $0 (a schema-only branch with synthetic rows is far below that); **egress** and **storage** at parent rates (a few test PDFs: negligible; Pro includes 250 GB egress); **Edge Function** invocations at normal rates. Branches are **not covered by the Spend Cap** and count toward plan quota. Pro advertises $10/month compute credits; whether they offset branch hours is not stated — treat as unknown.

## Unknown or unverified charges
Plan of the organisation; whether compute credits apply; billing granularity (hourly rounding) and the exact stop time after deletion (docs advise deleting unused branches but do not state it); any branch-creation fee on a larger compute size; cost of "Include data" (not used); additional-disk auto-scaling thresholds; Edge Function counts if the parent's functions are copied (docs: a new branch starts with the base project's Edge Functions deployed — staging's deployed functions were not inspected this round).

## Lifecycle (proposed, needs approval)
1. **Before creating:** confirm plan and cost line; layout fixes in section "Before applying the baseline"; synthetic seed ready; `Include data` OFF.
2. **Create** one persistent branch from a pushed Git branch (GitHub integration builds from `supabase/migrations/`) or a dashboard branch only after the baseline is part of the history. Preview branches are auto-deleted on PR close; persistent ones are never paused for inactivity — so deletion must be manual.
3. **Initialise:** baseline 0000 → 0001 → … → 0007 (never the proposals 0007a/0008/0009); seed synthetic categories; run `compare/` fingerprints on the branch (read-only) and diff against local.
4. **Validate** (≤ 1 working day target) per HOSTED_PG17_VALIDATION_CHECKLIST.md using synthetic users only; no emails/SMS (auth email disabled or branch SMTP placeholders left unset — docs say auth secrets get placeholders).
5. **Retention:** keep reports and logs in the repo, not the branch. No production or real data ever enters the branch.
6. **Delete** the same day validation ends (dashboard branch list or management tool); verify it disappears and the next day's usage shows no branch hours; delete any Edge Function copy with it.
7. **Budget cap:** 72 h hard limit (≈ $0.97 compute); if exceeded, stop and report.

## How the baseline initialises an isolated branch
A branch does not clone the schema ("The database schema isn't cloned"): GitHub branches replay `supabase/migrations/`, dashboard branches replay the parent's migration history. Staging's history is **empty**, so a branch from staging today would be an empty database. The reconstructed baseline therefore must be the first file in the replayed history, followed by 0001–0007. It contains no data, roles, platform schemas or secrets, so it is safe on a fresh platform instance; auth/storage platform objects come from the branch itself.

## Checks required before applying it
1. Filename/versioning: copy to `supabase/migrations/<timestamp>_baseline_reconstructed.sql` earlier than the 0001 timestamp; keep it out of the original staging project (objects already exist there — only a metadata `migration repair` would be appropriate, and only with approval).
2. Decide on `begin/commit` inside files (CLI wraps in a transaction).
3. Add `supabase/config.toml` with explicit `verify_jwt = true` for `evidence-link`, and the function directory in the layout the CLI expects.
4. Re-run `baseline/compare/` on staging to confirm the extract has not drifted since Round 7 (read-only).
5. Add a synthetic categories seed (the 14 real rows were not captured).
6. Decide on the identity-sequence revokes (MIGRATION_INVENTORY §4) and whether proposals 0007a/0009 are part of the first run (recommended: no — first run = exactly the validated chain).
7. Confirm the platform default privileges on the branch before running the suite.

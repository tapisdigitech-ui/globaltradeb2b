# Temporary Supabase branch: cost and configuration (PREPARATION ONLY - nothing created)

Sources: [Manage Branching usage](https://supabase.com/docs/guides/platform/manage-your-usage/branching), [Branching](https://supabase.com/docs/guides/deployment/branching). Prices below are the documented figures; confirm in the dashboard / tool cost prompt before approval.

| Item | Value |
|---|---|
| Required plan | **Not stated on the pages I could read.** Branching bills as "Branching Compute Hours", so assume a paid org plan; the organisation `GlobalTradeB2B` plan is not visible to me. Confirm before approving. If a plan upgrade is needed its monthly fee is an additional cost I cannot quote |
| Branch compute | default Micro (documented as the default; no other size listed) |
| Hourly cost | **$0.01344/hour**, no fixed fee per branch |
| 24 h | $0.32 |
| 48 h | $0.65 |
| 72 h | $0.97 |
| Other charges | disk size, egress and storage are billed like the parent project; for ~20 synthetic rows and a few test PDFs they are negligible. Branch usage counts toward plan quotas, is **not covered by the Spend Cap**, and Compute Credits do not apply to branch compute |
| Expected lifetime | 1-2 working days; delete on the same day validation ends |
| Pause / delete | persistent branches are not auto-paused; preview branches are deleted when their PR is merged/closed; manual deletion is available from the dashboard branch list (and the MCP `delete_branch` tool). Deleting stops billing. I could not confirm a manual pause for preview branches, so plan on delete-and-recreate rather than pause |
| Isolation | "Each branch is a separate environment with its own Supabase instance and API credentials." Branches are data-less by default (no production data or storage objects copied unless "Include data" is chosen - we will NOT choose it). Schema comes from migrations, not a clone. Auth/SMTP secrets get placeholders (so no real e-mail can be sent unless secrets are set - we will not set them). A branch cannot modify `globaltradeb2b-staging` or production unless merged; merge will not be used |

## Blocker discovered: staging has no recorded migrations
`list_migrations` on `globaltradeb2b-staging` returns `[]`. A branch builds its schema by replaying the parent's migration history, so a branch created now would contain an EMPTY schema. Before any validation we need a **baseline migration** (the reconstructed staging schema: tables, functions, policies, grants, storage buckets) applied to the branch first, then 0001-0006 as ordered migrations. The baseline must be compared with staging by read-only catalogue queries (policies, grants, functions, triggers, buckets) before the tests count as meaningful. This adds roughly half a day of preparation but no hosted cost until the branch exists. The same applies to Postgres version: staging is PG 17, the local replica is 16.15.

## Confirmation requested
Create the branch only after you approve: (1) the plan/cost line above, (2) synthetic data only with "Include data" off, (3) deletion the same day, (4) the baseline-migration approach. Not created.

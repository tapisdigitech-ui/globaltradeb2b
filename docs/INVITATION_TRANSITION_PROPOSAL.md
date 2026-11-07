# Legacy invitation transition (Round 8) — PROPOSAL, not applied

## What 0007 does to invitations
`accept_invitation` now treats `expires_at IS NULL` as expired; a `NOT VALID` check forbids pending (`invited`) member rows without an expiry. Staff invitations (`claim_invitations`, token flow) are unaffected.

## Which rows can be affected — local evidence
- The guard trigger `trg_guard_member` forces `expires_at := now() + 14 days` on every invitation created by a non-trusted session (owners via PostgREST). `my_invitations()` already filtered `expires_at > now()`, so NULL-expiry rows were never listed to invitees.
- Therefore NULL-expiry pending invites can only have been created from a trusted session (service role / SQL editor / dashboard), i.e. by hand.
- No function inserts invited members; `review_claim` inserts only the active owner, so the owner-insert policy path (trigger-guarded) is the only non-trusted creator.

## Can a read-only aggregate establish the affected number?
**Not within this round's rules, so the count is UNKNOWN.** The exact number needs `SELECT count(*) … FROM company_members WHERE status='invited' AND expires_at IS NULL`, which is a data query, not a catalogue read, so I did not run it. I read only statistics views on staging (no row content): `company_members` shows `n_live_tup = 0`, `n_tup_ins/upd/del = 0` and never analysed since the statistics reset on 2026-11-03 (4 days). The same zero DML holds for `profiles`, `companies` and `enquiries`. This is consistent with an empty/unused table but is **not proof**: rows inserted before the reset would not appear in these counters. If you approve a data aggregate, the query to run (counts only, no emails, ids or contents) is:
```sql
select count(*) filter (where status='invited' and user_id is null and expires_at is null) as legacy_null_expiry,
       count(*) filter (where status='invited' and user_id is null and expires_at is null and created_at > now() - interval '14 days') as younger_than_14d
from public.company_members;
```

## Proposed transition (`supabase/proposals/0007a_legacy_invitation_transition_PROPOSAL.sql`)
Apply the **normal rule retroactively**, once, from a trusted session: `expires_at := created_at + 14 days` for pending rows with NULL expiry. Invitations younger than 14 days keep exactly the remaining lifetime they would have had; older ones are already expired (rows kept, owner re-invites). Nothing is extended beyond the standard 14 days, nothing is activated or deleted, new NULL-expiry invites stay impossible. A log table (`legacy_invitation_transition_log`, immutable, no access for app roles) records each changed row id with previous/new expiry. The final statement `VALIDATE CONSTRAINT` fails the whole transaction if any pending invite still lacks an expiry, and the membership audit trigger records each update.

Time-bounded: after the 14-day window every transitioned row has expired by itself; the log table can be dropped then.

## Tests (local PG 16.15)
`bash tests/run_proposal_invitation.sh control|proposal`: control 2/2 (0007 alone refuses even a 3-day-old legacy invite); proposal 12/12 (precondition; no NULL pending left and constraint validated; young rows get created_at+14 d, 20-day-old row expired; untouched rows; log content and immutability; young invitee can list and accept; expired invitee refused; buyer/anon cannot read the log; audit rows; new NULL invite still refused; down).

## Rollback implications
`0007a_…_DOWN.sql` restores NULL expiries for the transitioned rows from the log and re-adds the constraint as `NOT VALID` (state left by 0007). That restores the pre-transition state in which those invites are unusable under 0007; it does **not** reintroduce the vulnerability (the function still fails closed). A validated constraint cannot be "un-validated", so the down drops and re-adds it. Accepted invitations remain active.

## Not applied to hosted staging.

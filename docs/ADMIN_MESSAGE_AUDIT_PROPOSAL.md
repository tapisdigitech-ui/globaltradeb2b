# Admin message-read audit — PROPOSAL (not implemented, not applied)

Files: `supabase/proposals/0008_admin_message_audit_PROPOSAL.sql`, `…_DOWN.sql`, tests `supabase/tests/proposals/admin_message_audit_tests.sql`, runner `supabase/tests/run_proposal_admin_audit.sh`. The proposal is **not** in `migrations_draft/` and is **not** run by `run_real.sh`, the legacy suite or the dry runs. Waiting for explicit approval.

## Problem
After 0006, buyer/seller messages and quotations are readable by **any admin through RLS (`is_admin()` in the policy) with no purpose, no time limit and no per-read record**; only non-admin staff go through the audited 10-minute grant (`staff_open_enquiry_comms`).

## Policies that change (4)
| Table | Policy | Change |
|---|---|---|
| `direct_threads` | `dt_read` | `is_admin()` → `admin_comms_grant_active('thread', id)` |
| `direct_messages` | `dm_read` | `is_admin()` → `admin_comms_grant_active('thread', thread_id)` |
| `enquiry_replies` | `replies_read` | `is_admin()` → `admin_comms_grant_active('enquiry', enquiry_id)` |
| `quotations` | `quotes_read` | `is_admin()` → `admin_comms_grant_active('enquiry', enquiry_id)` |

`orders_read` (a fifth policy that also contains `is_admin()`) is **deliberately left unchanged**: orders are an operational/finance record, not message content. Decision for the approver; changing it is a one-line addition.

## Audited function that replaces direct access
`admin_open_comms(scope 'enquiry'|'thread', target uuid, purpose text) → 'ok'|'denied'|'invalid'|'rate_limited'`, admin only, `SECURITY DEFINER`. It creates a **10-minute grant** for that admin and that target only. A separate `thread` scope exists because direct threads that are not linked to an enquiry cannot be covered by the existing enquiry-based staff path.

## How admins retain legitimate access
Call `admin_open_comms` with a purpose of at least 10 characters (dispute id, abuse report id…), then read through the normal tables for 10 minutes; re-call to extend. Non-message admin functions are unaffected.

## What is recorded
`admin_comms_access_log` (immutable via `block_mutation`, admin-readable, no FK so rows outlive deletions): actor, scope, target, purpose, outcome, denial reason, time.
- **Successful** opens: `granted` row.
- **Refused for admins**: `invalid` (short purpose, bad scope, NULL/unknown target) and `rate_limited` rows — the function is deliberately **non-raising** for admins so the log row is not rolled back. Limits: 30 grants/h, 200/day, 20 refusals/h (checked first, so refusal floods are throttled).
- **Non-admins** (reviewer, buyer, seller, anonymous, service role) get a plain error and **no log row** (raising rolls the insert back; logging attempts by arbitrary users would let anyone fill the table). The `denied` outcome value is reserved and currently unused. Limitation to accept or change.
- Individual message *rows* read during a grant are not logged; the grant (who, what, why, when) is.

## Existing workflows that would break
- Any admin screen that lists or previews threads, replies or quotes by direct table query would return nothing until the admin opens the target. The current demo UI is not connected to real data, so nothing breaks today; a real admin console must call `admin_open_comms` first (UI change needed).
- Support/dispute handling gains one step and requires a stated purpose.
- Buyers, sellers, assigned-staff grant flow, orders, and `SECURITY DEFINER` functions are unchanged (tests AP9b/AP10b/AP14/AP15b).
- Rollback: `0008_…_DOWN.sql` restores the 0006 policies exactly (schema diff 0 lines) and drops the log/grants tables (audit history lost; export first).

## Tests (local PG 16.15, proposal only)
Control (current behaviour, 0007 only): 2/2 pass — admin reads everything with no grant and no log. Proposal applied: 26/26 pass (no-grant read blocked; invalid/refused logged; enquiry and thread grants scoped; expiry; immutability; reviewer/buyer/seller/anonymous/service-role refused and still reading only their own data; refusal-flood throttle). Rollback: 0-line diff.

## Round 8 review (confirmation against the current chain; still unapplied)
| Item | Confirmed? | Evidence |
|---|---|---|
| Four policy changes (`dt_read`, `dm_read`, `replies_read`, `quotes_read`) | Yes | policy text on baseline+0001–0007; AP15 asserts none of the four mentions `is_admin()` directly after the proposal |
| Audited admin workflow | Yes | `admin_open_comms` → grant + immutable log; tests AP3–AP7 |
| Ten-minute grant | Yes | grant `expires_at = now() + 10 minutes`; AP7 (expiry) uses a forced-expired row, not a 10-minute wait; re-open extends |
| Denied-access logging gap | Yes, two forms | (a) non-admin callers raise before any insert, so there is no log (AP8–AP12); (b) the pre-existing staff routes (`staff_open_enquiry_comms`, `reveal_buyer_contact`, evidence) also log only successes except the evidence gate |
| Admin-console UI changes | Required, console not built | the demo `index.html` contains no Supabase calls; a real console must call `admin_open_comms` before listing threads/replies/quotes and handle the empty result |
| Rollback | Yes | `…_DOWN.sql`; schema diff 0 lines |
| Test coverage | Control 2/2; proposal 30/30 | `tests/run_proposal_admin_audit.sh control|proposal|rollback` |

### New review findings
1. **A second, weaker admin route already exists.** `staff_can_see_enquiry()` is true for admins, so after the proposal an admin can still call `staff_open_enquiry_comms(enquiry, purpose≥5 chars)` and read enquiry-scoped replies/quotes (tests AP16–AP16c: logged in `staff_comms_access_log`, but with a 5-character purpose, a 200/day limit and no refusal logging). The proposal's *thread* scope is genuinely new (that route cannot open a thread with no enquiry between the parties, AP16b). Decision needed: keep both routes, or make admins use only `admin_open_comms` by excluding admins from `staff_can_see_enquiry` in comms functions.
2. **Other admin shortcuts remain outside the four message policies**, by design of the proposal: `orders_read`, `profiles_self_read` (admins read every profile incl. `phone`), `product_view_events`, `seller_feedback`, `suppression_list`, `moderation_actions`, `media_assets`. Of these, `profiles.phone` is the personal-data item worth a decision.
3. The vault itself has **no** admin shortcut: `company_private` (owner/manager), `enquiry_private` (buyer or active grant), `company_claim_evidence` (claimant only) — staff/admin reach them only through audited functions.
4. The grant row is not revoked on logout; it simply expires. Row-level reads during a grant are not logged.
